import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peli/data/local/app_database.dart';
import 'package:peli/data/local/key_manager.dart';

/// 加密链路的**主机可运行**验证。
///
/// 覆盖两件事：
/// 1. 密钥管理：`PRAGMA key` 的生成格式（裸密钥 `x'<hex>'`）、长度校验、随机性与幂等；
/// 2. 明文文件头检测：`looksLikePlaintextSqlite` 的判断逻辑（防"加密静默失效"）。
///
/// APK 里确实打包了真实 SQLCipher 原生库由 `tool/verify_apk_encryption.dart` 校验；
/// 真机上的"库文件确为密文"由 `AppDatabase._verifyEncryption()` 在启动时断言，
/// 该断言会拒绝在明文库上启动，因此不存在"静默降级为明文"的路径。
void main() {
  group('DatabaseKeyManager', () {
    test('PRAGMA key 使用裸密钥格式（x\'hex\'，64 个十六进制字符 = 256 位）', () {
      final Uint8List dek = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final String pragma = DatabaseKeyManager.pragmaKey(dek);

      expect(pragma.startsWith("x'"), isTrue);
      expect(pragma.endsWith("'"), isTrue);
      final String hex = pragma.substring(2, pragma.length - 1);
      expect(hex.length, 64, reason: '32 字节密钥 = 64 个十六进制字符');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hex), isTrue);
      // 前几个字节按小写、两位补零展开。
      expect(hex.substring(0, 8), '00010203');
      expect(hex.substring(62), '1f', reason: '第 32 字节是 0x1f');
    });

    test('密钥必须是 32 字节，长度不符的存储内容会被拒绝', () async {
      // 这里用假存储模拟"存储里的密钥被截断"的场景。
      final _FakeSecureStorage storage = _FakeSecureStorage(
        value: base64Encode(Uint8List.fromList(<int>[1, 2, 3])),
      );
      final DatabaseKeyManager manager = DatabaseKeyManager(storage: storage);
      await expectLater(manager.loadOrCreate(), throwsA(isA<StateError>()));
    });

    test('首次调用生成并持久化 32 字节随机密钥，第二次读到同一个', () async {
      final _FakeSecureStorage storage = _FakeSecureStorage();
      final DatabaseKeyManager manager = DatabaseKeyManager(storage: storage);
      final Uint8List first = await manager.loadOrCreate();
      expect(first.length, 32);
      final Uint8List second = await manager.loadOrCreate();
      expect(second, first);
      expect(storage.writes, 1, reason: '第二次不应重复写入');
    });

    test('连续生成的密钥不相同（随机性冒烟检查）', () async {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 8; i++) {
        final Uint8List key = await DatabaseKeyManager(storage: _FakeSecureStorage()).loadOrCreate();
        expect(seen.add(base64Encode(key)), isTrue);
      }
    });
  });

  group('明文数据库检测（防止加密静默失效）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('memos-enc-check');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('明文 SQLite 头会被识别出来', () async {
      final File file = File('${dir.path}${Platform.pathSeparator}plain.db');
      await file.writeAsBytes(<int>[
        0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, //
        ...List<int>.filled(64, 0x41),
      ]);
      expect(await looksLikePlaintextSqlite(file.path), isTrue);
    });

    test('SQLCipher 密文（随机头）不会被误判为明文', () async {
      final Random random = Random(7);
      final File file = File('${dir.path}${Platform.pathSeparator}enc.db');
      await file.writeAsBytes(List<int>.generate(512, (_) => random.nextInt(256)));
      expect(await looksLikePlaintextSqlite(file.path), isFalse);
    });

    test('文件不存在时返回 false（不误报）', () async {
      expect(await looksLikePlaintextSqlite('${dir.path}${Platform.pathSeparator}nope.db'), isFalse);
    });

    test('太短的文件不会被误判', () async {
      final File file = File('${dir.path}${Platform.pathSeparator}short.db');
      await file.writeAsBytes(<int>[0x53, 0x51, 0x4c]);
      expect(await looksLikePlaintextSqlite(file.path), isFalse);
    });
  });

}

/// 内存版安全存储（避免测试依赖平台通道）。
class _FakeSecureStorage implements SecureStorageLike {
  _FakeSecureStorage({this.value});

  String? value;
  int writes = 0;

  @override
  Future<String?> read({required String key}) async => value;

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    this.value = value;
  }

  @override
  Future<void> delete({required String key}) async => value = null;
}
