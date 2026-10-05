import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memos_api/memos_api.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local/account_dao.dart';
import '../data/local/app_database.dart';
import '../data/local/key_manager.dart';

/// 应用启动后持有的服务集合。
class AppServices {
  AppServices({
    required this.database,
    required this.dao,
    required this.accounts,
  });

  /// 加密库句柄 —— 由这里持有，保证整个进程生命周期内连接不被关闭。
  final AppDatabase database;
  final AccountDao dao;

  /// 已保存的账号（按最近使用排序，见 [AccountDao.listAccounts]）。
  final List<AccountRecord> accounts;
}

/// 启动流程：打开加密库 → 载入账号。
///
/// 注意 `keyManager.exists()` 为 false 但数据库文件已存在，说明密钥丢了
/// （例如恢复了备份但 Keystore 不可用），此时必须显式报错而不是静默新建库。
///
/// **每一步都有超时**：启动链路依赖多个平台通道（path_provider、
/// flutter_secure_storage、sqflite_sqlcipher）。任一通道无响应时，Future 会永久挂起，
/// 表现为"白屏且永远不结束"。真机上确实偶发过这种挂起，因此这里用
/// [_withTimeout] 把"静默挂起"变成"明确的失败提示"，让用户至少知道发生了什么。
Future<AppServices> bootstrapServices() async {
  final Stopwatch watch = Stopwatch()..start();
  void mark(String label) {
    // ignore: avoid_print
    print('[bootstrap] $label  ${watch.elapsedMilliseconds}ms');
  }

  mark('begin');

  final DatabaseKeyManager keyManager = DatabaseKeyManager();
  final Directory support = await _withTimeout(
    'getApplicationSupportDirectory',
    getApplicationSupportDirectory(),
  );
  mark('supportDir=${support.path}');

  final String dbPath = p.join(support.path, AppDatabase.fileName);
  final bool keyExists = await _withTimeout('keyManager.exists', keyManager.exists());
  mark('keyExists=$keyExists');
  final bool dbExists = File(dbPath).existsSync();
  mark('dbExists=$dbExists');
  if (!keyExists && dbExists) {
    throw StateError(
      '本地数据库存在但密钥丢失（通常发生在恢复备份后）。'
      '为避免数据被覆盖，应用已停止启动。请清除应用数据后重新登录。',
    );
  }

  final AppDatabase database = await _withTimeout(
    'AppDatabase.open',
    AppDatabase.open(keyManager: keyManager),
  );
  mark('dbOpened path=${database.path}');

  final AccountDao dao = AccountDao(database);
  final List<AccountRecord> accounts = await _withTimeout('listAccounts', dao.listAccounts());
  mark('accounts=${accounts.length}');

  return AppServices(database: database, dao: dao, accounts: accounts);
}

/// 给启动步骤加超时，把"永久挂起"变成"可诊断的失败"。
Future<T> _withTimeout<T>(String label, Future<T> future) {
  return future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw StateError(
      '启动步骤「$label」超过 20 秒未完成，可能是系统服务（钥匙串/文件系统）无响应。'
      '请重启应用；若反复出现，请检查设备是否限制了后台/存储权限。',
    ),
  );
}

/// 启动服务（首次读取时执行一次）。
final FutureProvider<AppServices> appServicesProvider = FutureProvider<AppServices>(
  (Ref ref) => bootstrapServices(),
);

/// 当前激活账号 id（null = 未登录）。
final NotifierProvider<ActiveAccountNotifier, String?> activeAccountIdProvider =
    NotifierProvider<ActiveAccountNotifier, String?>(ActiveAccountNotifier.new);

/// 当前激活账号的选择。
///
/// ## 设计（为什么这样做）
///
/// 1. **自动恢复上次使用的账号**：`bootstrapServices()` 已把账号按
///    `last_used_at DESC` 排好（见 [AccountDao.listAccounts]），取第一个即可。
///    绝大多数用户只有一个账号，于是**永远不需要选**。
/// 2. **显式选择优先**：用户切换账号后 `set()` 立即写库（`markAccountUsed`），
///    下次冷启动恢复的就是他最后选的那个。
/// 3. **上次用的账号被删除时**：它已不在排序结果里，自动落到下一个，不会卡在空状态。
///
/// 放在 `build()` 里同步推导而不是异步查库：`AppBootstrap` 已经等
/// `appServicesProvider` 就绪才构建 `MemosApp`，此刻账号列表就在手上，
/// 同步取值可避免"首帧闪一下配置页"。
class ActiveAccountNotifier extends Notifier<String?> {
  @override
  String? build() {
    // 冷启动：取最近使用的账号（列表已按 last_used_at 排序）。
    final AsyncValue<AppServices> services = ref.watch(appServicesProvider);
    return services.maybeWhen(
      data: (AppServices value) => value.accounts.firstOrNull?.id,
      orElse: () => null,
    );
  }

  /// 切换当前账号，并持久化"这是最后使用的账号"。
  void set(String? accountId) {
    state = accountId;
    if (accountId == null) return;
    final AsyncValue<AppServices> services = ref.read(appServicesProvider);
    services.whenData((AppServices value) {
      // 写库失败不阻塞 UI：最坏情况是下次启动恢复到上一个账号。
      unawaited(value.dao.markAccountUsed(accountId));
    });
  }
}

/// 当前激活账号。
final Provider<AccountRecord?> activeAccountProvider = Provider<AccountRecord?>((Ref ref) {
  final AsyncValue<AppServices> services = ref.watch(appServicesProvider);
  final String? id = ref.watch(activeAccountIdProvider);
  return services.maybeWhen(
    data: (AppServices value) => value.accounts.where((AccountRecord a) => a.id == id).firstOrNull,
    orElse: () => null,
  );
});

/// 登录：用户名密码 → 长效 PAT → 存进加密库。
///
/// 这是本客户端**唯一**与 memos API 直接交互的地方：拿到 PAT 之后，所有业务请求
/// 都由页面里的官方前端自己发起，本应用只在 WebView 里替它补上凭据。
class SessionController {
  SessionController(this._ref);

  final Ref _ref;

  AppServices get _services => _ref.read(appServicesProvider).requireValue;

  Future<AccountRecord> signIn({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final MemosClient client = MemosClient(baseUrl: Uri.parse(baseUrl));
    try {
      final SignInResult session = await client.signIn(username: username, password: password);
      client.accessToken = session.accessToken;

      // 版本校验：本项目只支持 memos 0.31.0 及以上的 v1 API。
      final InstanceProfile profile = await client.getProfile();
      if (!profile.isSupported) {
        throw MemosApiException(
          '该实例版本为 ${profile.version}，本客户端要求 0.31.0 及以上',
        );
      }

      // 优先换取长效 PAT；失败（老版本或权限限制）则退回短效 token。
      String token = session.accessToken;
      try {
        token = await client.createPersonalAccessToken(
          userId: session.user.id,
          description: 'Android 客户端',
        );
      } on MemosApiException {
        // 保留短效 token；用户下次启动需要重新登录。
      }

      final AccountRecord account = AccountRecord(
        id: session.user.id,
        baseUrl: baseUrl,
        accessToken: token,
        displayName: session.user.displayName,
        username: session.user.username.isEmpty ? null : session.user.username,
      );
      await _services.dao.upsertAccount(account);
      _services.accounts
        ..removeWhere((AccountRecord a) => a.id == account.id)
        ..add(account);
      _ref.read(activeAccountIdProvider.notifier).set(account.id);
      return account;
    } finally {
      client.close();
    }
  }
}

final Provider<SessionController> sessionControllerProvider =
    Provider<SessionController>(SessionController.new);
