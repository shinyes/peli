import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储的最小接口。
///
/// 抽出接口是为了让密钥逻辑可以在主机上被测试（真机实现走平台通道，测试里注入内存实现）。
abstract interface class SecureStorageLike {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

/// 生产实现：Android 走 Keystore 支撑的加密存储，iOS/macOS 走 Keychain。
class FlutterSecureStorageAdapter implements SecureStorageLike {
  const FlutterSecureStorageAdapter([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// 数据库主密钥（DEK）的生成、保存与读取。
///
/// 设计（对应方案文档 §7.1）：
/// - DEK 是 32 字节随机数，**不由用户口令派生**，用户无需记住任何东西（无感解锁）；
/// - DEK 以 base64 存在平台安全存储里：
///   * Android：Keystore 包裹（`flutter_secure_storage` 10.x 用 RSA-OAEP 包裹密钥 +
///     AES-GCM 加密存储内容）；
///   * iOS/macOS：Keychain；
/// - 设备被 root 或安全存储被清空时，DEK 不可恢复 —— 因此必须引导用户做加密导出。
///
/// 注意：Keystore 密钥**不会**被云备份带走，所以应用必须关闭 `allowBackup`
/// 并自行提供加密导出（见 `AndroidManifest.xml`、`data_extraction_rules.xml` 与设置页）。
class DatabaseKeyManager {
  DatabaseKeyManager({SecureStorageLike? storage})
      : _storage = storage ?? const FlutterSecureStorageAdapter();

  static const String keyName = 'memos_db_key_v1';
  static const int keyLength = 32;

  final SecureStorageLike _storage;
  final Random _random = Random.secure();

  /// 读取已有 DEK；不存在时生成并保存。
  ///
  /// 返回 32 字节密钥（数据库用它的十六进制形式做 `PRAGMA key`）。
  Future<Uint8List> loadOrCreate() async {
    final String? existing = await _storage.read(key: keyName);
    if (existing != null && existing.isNotEmpty) {
      final Uint8List decoded = base64Decode(existing);
      if (decoded.length == keyLength) return decoded;
      // 长度不对说明存储被破坏；直接报错，避免静默新建密钥导致旧库永久打不开。
      throw StateError('本地密钥格式异常（长度 ${decoded.length}），无法打开数据库');
    }
    final Uint8List created = _randomBytes(keyLength);
    await _storage.write(key: keyName, value: base64Encode(created));
    return created;
  }

  /// DEK 是否已经存在（用于区分"首次启动"与"密钥丢失"）。
  Future<bool> exists() async => (await _storage.read(key: keyName))?.isNotEmpty ?? false;

  /// 删除 DEK（仅用于"清除全部本地数据"）。
  Future<void> delete() => _storage.delete(key: keyName);

  /// SQLCipher 的 `PRAGMA key` 参数：`x'<hex>'` 表示 32 字节裸密钥。
  ///
  /// 用裸密钥而不是口令：口令形式会让 SQLCipher 再做一次 KDF（默认 PBKDF2 256000 轮），
  /// 而我们的密钥本身已是高熵随机值，重复 KDF 只会拖慢每次打开数据库。
  static String pragmaKey(Uint8List dek) =>
      "x'${dek.map((int b) => b.toRadixString(16).padLeft(2, '0')).join()}'";

  Uint8List _randomBytes(int length) {
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
