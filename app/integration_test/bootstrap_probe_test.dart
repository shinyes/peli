import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peli/data/local/app_database.dart';
import 'package:peli/data/local/key_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 分步复现应用启动链路，逐步计时以定位"卡在哪一步"。
///
/// 跑法：`flutter test integration_test/bootstrap_probe_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> step(String label, Future<void> Function() body) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      await body().timeout(const Duration(seconds: 20));
      // ignore: avoid_print
      print('STEP_OK   $label  ${watch.elapsedMilliseconds}ms');
    } catch (error) {
      // ignore: avoid_print
      print('STEP_FAIL $label  ${watch.elapsedMilliseconds}ms  $error');
      rethrow;
    }
  }

  testWidgets('启动链路分步探测', (WidgetTester tester) async {
    late Directory support;
    late DatabaseKeyManager keyManager;

    await step('getApplicationSupportDirectory', () async {
      support = await getApplicationSupportDirectory();
      // ignore: avoid_print
      print('  support=${support.path}');
    });

    await step('secure_storage.read(key exists?)', () async {
      const FlutterSecureStorage storage = FlutterSecureStorage();
      final String? value = await storage.read(key: DatabaseKeyManager.keyName);
      // ignore: avoid_print
      print('  existing_key=${value == null ? 'null' : 'len=${value.length}'}');
    });

    await step('keyManager.exists()', () async {
      keyManager = DatabaseKeyManager();
      final bool exists = await keyManager.exists();
      // ignore: avoid_print
      print('  key_exists=$exists');
    });

    await step('keyManager.loadOrCreate()', () async {
      final DateTime t0 = DateTime.now();
      final List<int> key = await keyManager.loadOrCreate();
      // ignore: avoid_print
      print('  key_len=${key.length} took=${DateTime.now().difference(t0).inMilliseconds}ms');
    });

    await step('keyManager.exists() 二次（确认落盘）', () async {
      final bool exists = await keyManager.exists();
      // ignore: avoid_print
      print('  key_exists_after=$exists');
    });

    await step('AppDatabase.open()', () async {
      final AppDatabase db = await AppDatabase.open(keyManager: keyManager);
      // ignore: avoid_print
      print('  db_path=${db.path} exists=${File(db.path).existsSync()}');
      await db.close();
    });

    await step('AppDatabase.open() 二次（复用已有库）', () async {
      final AppDatabase db = await AppDatabase.open(keyManager: keyManager);
      final List<Map<String, Object?>> rows =
          await db.raw.rawQuery('SELECT count(*) AS c FROM memos');
      // ignore: avoid_print
      print('  memo_count=${rows.first['c']}');
      await db.close();
    });

    await step('shared_prefs 目录检查（flutter_secure_storage 落盘位置）', () async {
      final Directory prefs = Directory(p.join(support.parent.path, 'shared_prefs'));
      if (await prefs.exists()) {
        for (final FileSystemEntity entity in prefs.listSync()) {
          // ignore: avoid_print
          print('  pref: ${p.basename(entity.path)}');
        }
      } else {
        // ignore: avoid_print
        print('  shared_prefs 不存在');
      }
    });
  });
}
