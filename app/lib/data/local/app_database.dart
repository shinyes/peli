import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'key_manager.dart';

/// 本地加密数据库：SQLCipher 4（`sqflite_sqlcipher` 自带原生库）。
///
/// 加密要点：
/// - 打开后**第一条语句**必须是 `PRAGMA key`，否则 SQLCipher 会把文件当明文库处理；
/// - 使用裸密钥形式 `x'<hex>'`，密钥来自 [DatabaseKeyManager]（Keystore 保护）；
/// - 当前只保存账号（实例地址 + 长效 PAT），因此"把库文件拉走"也读不到可用凭据。
///
/// 为什么不用官方推荐的 `sqlite3` build hook（`source: sqlite3mc`）：
/// `sqlite3 >= 3.6.0 → hooks ^2.2.0 → record_use → meta ^1.19.0`，而当前 Flutter
/// 把 `meta` 钉在 1.18.0，依赖无法解析；`drift` 又会强制 `sqlite3 ^3.0.0`。
/// 因此改用不依赖 `sqlite3` 包的 `sqflite_sqlcipher`，DAO 手写 SQL。
class AppDatabase {
  AppDatabase._(this._db, this.path);

  final Database _db;
  final String path;

  static const int schemaVersion = 5;
  static const String fileName = 'memos.db';

  Database get raw => _db;

  /// 打开（必要时创建）加密数据库。
  static Future<AppDatabase> open({
    required DatabaseKeyManager keyManager,
    String? overrideDirectory,
  }) async {
    final String directory =
        overrideDirectory ?? (await getApplicationSupportDirectory()).path;
    await Directory(directory).create(recursive: true);
    final String dbPath = p.join(directory, fileName);

    final Uint8List dek = await keyManager.loadOrCreate();

    final Database db = await openDatabase(
      dbPath,
      password: DatabaseKeyManager.pragmaKey(dek),
      version: schemaVersion,
      onConfigure: (Database db) async {
        // 外键约束必须显式打开（SQLite 默认关闭）。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );

    final AppDatabase result = AppDatabase._(db, dbPath);
    await result._verifyEncryption();
    return result;
  }

  /// 断言当前库确实是加密库：明文 SQLite 文件的头部是 `SQLite format 3\0`。
  ///
  /// 这一步能挡住"加密开关失效但应用照常运行"这种最危险的静默降级。
  Future<void> _verifyEncryption() async {
    if (await looksLikePlaintextSqlite(path)) {
      throw StateError(
        '本地数据库未加密（文件头是明文 SQLite）。已中止启动以避免明文落盘。',
      );
    }
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id            TEXT PRIMARY KEY,
        base_url      TEXT NOT NULL,
        access_token  TEXT NOT NULL,
        display_name  TEXT,
        username      TEXT,
        created_at    INTEGER NOT NULL,
        last_used_at  INTEGER
      )
    ''');
  }

  static Future<void> _upgradeSchema(Database db, int from, int to) async {
    // v5：移除"本地优先架构"遗留的表 —— 本地时间线（memos / FTS5 索引）、附件、
    // 同步游标与同步日志；accounts 也重建为只保留当前架构使用的列。
    //
    // 为什么直接丢弃而不是迁移：这些表里只有"服务端数据的本地副本"，删除不会
    // 影响服务端；本客户端的界面是官方 Web 前端，本地不存在唯一的业务数据。
    if (from < 5) {
      for (final String table in <String>[
        'memos_fts',
        'memos',
        'attachments',
        'sync_cursors',
        'sync_logs',
        'settings',
      ]) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }

      // SQLite 的 DROP COLUMN 有版本门槛，这里用"重建 + 拷贝"确保任何版本都能跑。
      await db.execute('''
        CREATE TABLE accounts_v5 (
          id            TEXT PRIMARY KEY,
          base_url      TEXT NOT NULL,
          access_token  TEXT NOT NULL,
          display_name  TEXT,
          username      TEXT,
          created_at    INTEGER NOT NULL,
          last_used_at  INTEGER
        )
      ''');
      await db.execute('''
        INSERT INTO accounts_v5 (id, base_url, access_token, display_name, username, created_at, last_used_at)
        SELECT id, base_url, access_token, display_name, username, created_at, last_used_at FROM accounts
      ''');
      await db.execute('DROP TABLE accounts');
      await db.execute('ALTER TABLE accounts_v5 RENAME TO accounts');
    }
  }
}

/// 明文 SQLite 文件头：`SQLite format 3\0`。
const List<int> plaintextSqliteHeader = <int>[
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72,
  0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, //
];

/// 判断文件是否是**明文** SQLite 数据库。
///
/// 这是"加密是否真的生效"的最后一道自检：SQLCipher 加密后的文件头是随机盐值，
/// 不可能是这个固定 16 字节序列。一旦为 true 就说明加密没有生效，必须拒绝启动。
///
/// 抽成顶层函数是为了能在主机上直接测试（无需真机与 SQLCipher）。
Future<bool> looksLikePlaintextSqlite(String path) async {
  final File file = File(path);
  if (!await file.exists()) return false;
  final RandomAccessFile handle = await file.open();
  try {
    final List<int> header = await handle.read(plaintextSqliteHeader.length);
    if (header.length != plaintextSqliteHeader.length) return false;
    for (int i = 0; i < header.length; i++) {
      if (header[i] != plaintextSqliteHeader[i]) return false;
    }
    return true;
  } finally {
    await handle.close();
  }
}
