import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peli/data/local/app_database.dart';
import 'package:peli/data/local/key_manager.dart';

/// 真机（Android）上的加密验证：在**设备**上打开真实 SQLCipher 库，写入数据，
/// 然后直接读文件头确认落盘内容是密文。
///
/// 这一项无法在主机上完成：
/// - 主机没有 SQLCipher 原生库，无法真正打开加密库；
/// - 只有当 `sqflite_sqlcipher` 在设备上成功加载 `libsqlcipher.so` 时，
///   文件头才会是随机盐值而不是 `SQLite format 3\0`。
///
/// 跑法：
///   `flutter test integration_test/encryption_e2e_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 令牌里出现中文与 emoji，用来确认密文往返不损坏字节。
  const String secretContent = '真机加密验证 #secret ⚠️ emoji 与中文都要能正确往返';

  testWidgets('设备上打开 SQLCipher 库并写入数据', (WidgetTester tester) async {
    final DatabaseKeyManager keyManager = DatabaseKeyManager();
    final AppDatabase database = await AppDatabase.open(keyManager: keyManager);
    addTearDown(database.close);

    // 走真实 schema：写入一个账号（本地唯一持久化的业务数据）并读回。
    await database.raw.insert('accounts', <String, Object?>{
      'id': 'itest-account',
      'base_url': 'https://memos.example.com',
      'access_token': secretContent,
      'display_name': 'ITest',
      'username': 'itest',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final List<Map<String, Object?>> rows = await database.raw.query(
      'accounts',
      where: 'id = ?',
      whereArgs: <Object?>['itest-account'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['access_token'], secretContent);

    // 关键断言：文件头不能是明文 SQLite。
    final File dbFile = File(database.path);
    expect(await dbFile.exists(), isTrue, reason: '数据库文件应当已落盘：${database.path}');
    expect(
      await looksLikePlaintextSqlite(database.path),
      isFalse,
      reason: '设备上数据库仍是明文！说明 SQLCipher 没有生效（原生库未加载）',
    );

    // 打印文件头前 16 字节，便于人工核对（应为随机盐值）。
    final RandomAccessFile handle = await dbFile.open();
    final List<int> header = await handle.read(16);
    await handle.close();
    // ignore: avoid_print
    print('DB_PATH=${database.path}');
    // ignore: avoid_print
    print('DB_SIZE=${await dbFile.length()}');
    // ignore: avoid_print
    print('DB_HEADER=${header.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  });

  testWidgets('Keystore 保护的密钥在设备上稳定可读（无感解锁）', (WidgetTester tester) async {
    final DatabaseKeyManager keyManager = DatabaseKeyManager();
    expect(await keyManager.exists(), isTrue, reason: '前面的用例应当已经创建了密钥');
    final Uint8List first = await keyManager.loadOrCreate();
    final Uint8List second = await keyManager.loadOrCreate();
    expect(first.length, 32);
    expect(second, first, reason: '同一设备多次读取必须得到同一密钥（否则库会打不开）');
    // ignore: avoid_print
    print('KEY_AVAILABLE=true');
  });
}
