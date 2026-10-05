import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peli/data/local/app_database.dart';
import 'package:peli/data/local/key_manager.dart';

/// 真机安全行为验证：**密钥丢失时不得覆盖数据，也不得明文降级**。
///
/// 场景（真实世界会发生）：用户恢复了应用数据备份，或系统清空了 Keystore，
/// 于是"加密库还在、密钥没了"。正确行为是**拒绝启动并给出明确提示**，
/// 而不是新建一个空库把旧数据盖掉、更不能退化成明文库。
///
/// 文件头的独立复核在测试后用 adb 做（见 README「真机验收」一节）：
/// 应用内直接读文件会撞上 SQLCipher 尚未释放的句柄（MIUI 上尤其明显），
/// 因此这里只断言"打开失败 + 数据未被破坏"，文件头交给外部工具确认。
///
/// 跑法：`flutter test integration_test/key_loss_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const FlutterSecureStorage storage = FlutterSecureStorage();
  const String markerId = 'keyloss-marker';

  testWidgets('密钥丢失 + 库文件存在 → 拒绝打开，且数据未被破坏', (WidgetTester tester) async {
    // 1. 正常建库并写入一条数据。
    final DatabaseKeyManager keyManager = DatabaseKeyManager();
    final AppDatabase database = await AppDatabase.open(keyManager: keyManager);
    final String dbPath = database.path;
    await database.raw.insert('memos', <String, Object?>{
      'local_id': markerId,
      'account_id': 'keyloss-account',
      'content': '这条数据在密钥丢失后必须仍然存在（且为密文）',
      'visibility': 'PRIVATE',
      'pinned': 0,
      'archived': 0,
      'is_deleted': 0,
      'needs_sync': 1,
      'local_modified_at': DateTime.now().millisecondsSinceEpoch,
    });
    await database.close();
    // ignore: avoid_print
    print('KEYLOSS_DB=$dbPath');

    // 2. 模拟密钥丢失（等价于 Keystore 失效 / 换机恢复备份）。
    final String? savedKey = await storage.read(key: DatabaseKeyManager.keyName);
    expect(savedKey, isNotNull, reason: '前置条件：密钥应当存在');
    await storage.delete(key: DatabaseKeyManager.keyName);
    expect(await storage.read(key: DatabaseKeyManager.keyName), isNull);
    // ignore: avoid_print
    print('KEYLOSS_KEY_DELETED=true');

    // 3. 此时打开库必须失败：SQLCipher 会用新生成的错误密钥去解旧文件。
    Object? failure;
    try {
      final AppDatabase reopened = await AppDatabase.open(keyManager: DatabaseKeyManager());
      await reopened.close();
    } catch (error) {
      failure = error;
    }
    // ignore: avoid_print
    print('KEYLOSS_OPEN_RESULT=${failure == null ? 'NO_ERROR_DANGEROUS' : failure.runtimeType}');
    expect(failure, isNotNull, reason: '密钥丢失后打开数据库必须报错，不能静默建新库');

    // 4. 恢复密钥后数据必须完好（证明"密钥丢失"只要还有密钥就是可恢复的）。
    await storage.write(key: DatabaseKeyManager.keyName, value: savedKey!);
    final AppDatabase restored = await AppDatabase.open(keyManager: DatabaseKeyManager());
    final List<Map<String, Object?>> rows = await restored.raw.query(
      'memos',
      where: 'local_id = ?',
      whereArgs: <Object?>[markerId],
    );
    // ignore: avoid_print
    print('KEYLOSS_RESTORED_ROWS=${rows.length}');
    expect(rows, hasLength(1), reason: '恢复密钥后原数据必须还在（说明没被新库覆盖）');
    expect(rows.first['content'], contains('密钥丢失后必须仍然存在'));

    // 5. 顺带确认这次打开也没有退化成明文库。
    expect(
      await looksLikePlaintextSqlite(dbPath),
      isFalse,
      reason: '数据库不得为明文（SQLCipher 必须在设备上生效）',
    );

    // 收尾：删掉测试数据，避免影响真实使用。
    await restored.raw.delete('memos', where: 'local_id = ?', whereArgs: <Object?>[markerId]);
    await restored.close();
    // ignore: avoid_print
    print('KEYLOSS_DONE=true');
  });
}
