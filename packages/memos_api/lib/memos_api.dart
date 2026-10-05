/// 纯 Dart 实现的 memos 0.31.0 服务端 API 客户端（只覆盖登录所需端点）。
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
