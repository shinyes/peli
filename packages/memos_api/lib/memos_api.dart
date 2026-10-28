/// 纯 Dart 实现的 memos 服务端 API 客户端（只覆盖登录所需端点）。
///
/// 同时支持两代路由：0.31.x 的 `/api/v1/...` 与 26.10+ 的 `/api/...`
/// （后者移除了版本段，旧路径会返回 410 Gone）。前缀在首次请求时自动探测。
///
/// 用法：
/// ```dart
/// final client = MemosClient(baseUrl: Uri.parse('https://memos.example.com'));
/// final session = await client.signIn(username: 'steven', password: '…');
/// final pat = await client.createPersonalAccessToken(userId: session.user.id);
/// ```
library;

export 'src/client.dart' show MemosApiException, MemosClient, SignInResult;
export 'src/models.dart';
