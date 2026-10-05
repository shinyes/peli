import 'package:sqflite_sqlcipher/sqflite.dart';

import 'app_database.dart';

/// 账号记录 —— 本地唯一持久化的业务数据。
///
/// 当前架构下本地只存"实例地址 + 长效 PAT"：界面是官方 Web 前端，凭据靠页面注入，
/// 因此不需要在本地保存 memo、附件或同步状态。
class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.baseUrl,
    required this.accessToken,
    this.displayName,
    this.username,
    this.lastUsedAt,
  });

  /// 账号 id（等于 memos 用户 id）。
  final String id;

  /// 实例根地址，例如 `https://memos.example.com`。
  final String baseUrl;

  /// 长效 Personal Access Token。
  final String accessToken;

  /// 服务端返回的显示名（可能为空）。
  final String? displayName;

  /// 用户名（显示名缺失时的回退）。
  final String? username;

  /// 最后一次使用的时刻（UTC）。
  ///
  /// 存在的意义：启动时据此**自动恢复**上次用的账号，用户不必每次冷启动都重新选。
  /// 为 null 表示从未使用过。
  final DateTime? lastUsedAt;

  /// 登录页「已保存实例」里显示的名字：显示名 → 用户名 → 主机名。
  String get title {
    final String? name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final String? user = username?.trim();
    if (user != null && user.isNotEmpty) return user;
    return Uri.tryParse(baseUrl)?.host ?? baseUrl;
  }
}

/// 账号表的数据访问层（手写 SQL，全部走加密库）。
class AccountDao {
  AccountDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  /// 写入或更新账号。
  ///
  /// 注意：`replace` 会整行覆盖，因此必须显式保留已有的 `last_used_at` ——
  /// 否则每次重新登录都会把"上次使用的账号"抹掉，用户又得重新选一次。
  Future<void> upsertAccount(AccountRecord account) async {
    final int? preservedLastUsedAt = account.lastUsedAt?.millisecondsSinceEpoch ??
        (await _db.query(
          'accounts',
          columns: <String>['last_used_at'],
          where: 'id = ?',
          whereArgs: <Object?>[account.id],
          limit: 1,
        )).firstOrNull?['last_used_at'] as int?;

    await _db.insert(
      'accounts',
      <String, Object?>{
        'id': account.id,
        'base_url': account.baseUrl,
        'access_token': account.accessToken,
        'display_name': account.displayName,
        'username': account.username,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'last_used_at': preservedLastUsedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 记录"这个账号刚被使用"，供下次冷启动自动恢复。
  Future<void> markAccountUsed(String id) async {
    await _db.update(
      'accounts',
      <String, Object?>{'last_used_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 全部账号，**最近使用的排在最前**（未使用过的按创建时间排在最后）。
  ///
  /// 排序而非额外查询"当前账号"：启动时取第一个即可，少一次往返，
  /// 而且天然处理了"上次用的账号已被删除"的情况。
  Future<List<AccountRecord>> listAccounts() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'accounts',
      orderBy: 'last_used_at IS NULL ASC, last_used_at DESC, created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  AccountRecord _fromRow(Map<String, Object?> row) => AccountRecord(
        id: row['id']! as String,
        baseUrl: row['base_url']! as String,
        accessToken: row['access_token']! as String,
        displayName: row['display_name'] as String?,
        username: row['username'] as String?,
        lastUsedAt: row['last_used_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['last_used_at']! as int, isUtc: true),
      );
}
