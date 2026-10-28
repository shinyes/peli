import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// API 调用失败。所有非 2xx 响应与解析错误都会抛出该异常。
class MemosApiException implements Exception {
  MemosApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.uri,
    this.body,
  });

  final String message;
  final int? statusCode;

  /// 服务端返回的 gRPC/Connect 状态码（如 16 = UNAUTHENTICATED）。
  final int? code;
  final Uri? uri;
  final String? body;

  /// 凭据无效：HTTP 401 或 Connect 的 UNAUTHENTICATED。
  ///
  /// 服务端在令牌过期、密码变更、PAT 被删除时都返回这个错误，
  /// 它是「必须重新登录」的唯一可靠信号 —— 网络故障、5xx 都不算。
  bool get isUnauthenticated => statusCode == 401 || code == 16;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('MemosApiException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode');
    if (code != null) buffer.write(', code $code');
    if (statusCode != null) buffer.write(')');
    return buffer.toString();
  }
}

/// memos 服务端 API 客户端（兼容 0.31.x 与 26.10+ 两代路由）。
///
/// 只实现本客户端需要的一小部分端点 —— 登录、换取长效 PAT、读取实例版本、
/// 校验已有凭据。拿到 PAT 之后，所有业务请求都由页面里的官方前端自己发起。
///
/// 全部走 grpc-gateway 的 REST 形态（protojson），不依赖 Connect-RPC 与代码生成。
///
/// ## 两代路由（26.10 的破坏性变更）
///
/// 26.10 起 API 去掉了版本段，请求 /api/v1/... 直接返回 410 Gone：
///
/// - 登录：POST /api/v1/auth/signin  →  POST /api/auth/signin
/// - 建 PAT：POST /api/v1/{parent=users/*}/personalAccessTokens
///           →  POST /api/{parent=users/*}/personalAccessTokens
/// - 实例信息：GET /api/v1/instance/profile  →  GET /api/instance/profile
/// - 当前用户：GET /api/v1/auth/me  →  GET /api/auth/me
///
/// 这几个端点的报文结构没有变化（accessToken、token 等 JSON 字段名不变），
/// 所以前缀在**首次请求时探测一次**即可：先按新前缀请求，若服务端明确表示
/// 「没有这条路由」（404/405/410，或把未知路径交给 SPA 兜底回了 HTML），
/// 再退回旧前缀。
class MemosClient {
  MemosClient({
    required Uri baseUrl,
    this.accessToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _baseUrl = _normalizeBase(baseUrl),
        _http = httpClient ?? http.Client();

  /// 26.10 及以后的路由前缀。
  static const String modernApiPrefix = '/api';

  /// 0.31.x 及更早的路由前缀。
  static const String legacyApiPrefix = '/api/v1';

  final Uri _baseUrl;
  final http.Client _http;

  /// 当前使用的凭据：登录后是短效 access token，换取 PAT 后是长效 PAT。
  String? accessToken;

  /// 单请求超时。
  final Duration timeout;

  /// API 路由前缀，首次请求成功后固定下来。
  String _apiPrefix = modernApiPrefix;
  bool _apiPrefixResolved = false;

  Uri get baseUrl => _baseUrl;

  /// 已经确定使用的路由前缀（探测前是默认值）。
  String get apiPrefix => _apiPrefix;

  void close() => _http.close();

  static Uri _normalizeBase(Uri url) {
    Uri result = url;
    if (!result.hasScheme) {
      result = Uri.parse('https://$url');
    }
    // 去掉结尾的 /api/v1、/api 或斜杠，统一成站点根。
    String path = result.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith(legacyApiPrefix)) {
      path = path.substring(0, path.length - legacyApiPrefix.length);
    } else if (path.endsWith(modernApiPrefix)) {
      path = path.substring(0, path.length - modernApiPrefix.length);
    }
    return result.replace(path: path, query: null, fragment: null);
  }

  // -------------------------------------------------------------------------
  // 核心请求
  // -------------------------------------------------------------------------

  Map<String, String> _headers() => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (accessToken != null && accessToken!.isNotEmpty) 'Authorization': 'Bearer $accessToken',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    return _baseUrl.replace(
      path: '${_baseUrl.path}$_apiPrefix$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Never _throwFor(http.Response response, Uri uri) {
    int? code;
    String message = 'HTTP ${response.statusCode}';
    final String body = response.body;
    if (body.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(body);
        if (decoded is Map<String, Object?>) {
          code = asIntOrNull(decoded['code']);
          message = asString(decoded['message']) ?? message;
        }
      } on FormatException {
        message = body.length > 300 ? '${body.substring(0, 300)}…' : body;
      }
    }
    throw MemosApiException(
      message,
      statusCode: response.statusCode,
      code: code,
      uri: uri,
      body: body,
    );
  }

  Future<Json> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final Uri uri = _uri(path, query);
    final String? payload = body == null ? null : jsonEncode(body);
    http.Response response;
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(_headers())
        ..followRedirects = true;
      if (payload != null) request.body = payload;
      final http.StreamedResponse streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on MemosApiException {
      rethrow;
    } catch (error) {
      throw MemosApiException('网络请求失败：$error', uri: uri);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwFor(response, uri);
    }
    if (response.bodyBytes.isEmpty) return const <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
      return <String, Object?>{'value': decoded};
    } on FormatException catch (error) {
      throw MemosApiException('响应不是合法 JSON：$error', uri: uri, body: response.body);
    }
  }

  /// 发送请求；首次请求时顺带探测路由前缀（见类文档）。
  ///
  /// 只有「服务端明确表示没有这条路由」才换前缀重试一次 —— 认证失败（401）、
  /// 网络故障等必须原样抛出，否则会把「密码错误」误判成「老服务端」。
  Future<Json> _sendResolved(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    if (_apiPrefixResolved) {
      return _send(method, path, query: query, body: body);
    }
    try {
      final Json json = await _send(method, path, query: query, body: body);
      _apiPrefixResolved = true;
      return json;
    } on MemosApiException catch (error) {
      if (!_looksLikeUnknownRoute(error)) rethrow;
      _apiPrefix = _apiPrefix == modernApiPrefix ? legacyApiPrefix : modernApiPrefix;
      final Json json = await _send(method, path, query: query, body: body);
      _apiPrefixResolved = true;
      return json;
    }
  }

  /// 该错误是否意味着「这个前缀下没有这条路由」。
  bool _looksLikeUnknownRoute(MemosApiException error) {
    final int? status = error.statusCode;
    // 26.10 对 /api/v1/* 返回 410 Gone；老服务端对 /api/* 返回 404。
    if (status == 404 || status == 405 || status == 410) return true;
    // 老服务端的 SPA 兜底会把未知路径渲染成 index.html（200 + HTML）。
    return status == null && error.message.contains('响应不是合法 JSON');
  }

  // -------------------------------------------------------------------------
  // 认证与实例
  // -------------------------------------------------------------------------

  /// 用户名密码登录，返回**短效** access token 与用户信息。
  ///
  /// 26.10 起短效令牌只有 15 分钟，且与账号密码哈希绑定（改密码立即失效）。
  /// 客户端必须用它换取长效 PAT（见 [createPersonalAccessToken]），
  /// 绝不能把它当成会话凭据长期存下来。
  Future<SignInResult> signIn({required String username, required String password}) async {
    final Json json = await _sendResolved('POST', '/auth/signin', body: <String, Object?>{
      'passwordCredentials': <String, Object?>{'username': username, 'password': password},
    });
    return SignInResult(
      user: RemoteUser.fromJson(asJson(json['user'])),
      accessToken: asStringOr(json['accessToken'], ''),
    );
  }

  /// 创建长效 Personal Access Token（这是移动端应当持有的凭据）。
  ///
  /// [expiresInDays] 为 0 表示永不过期。**返回值只在创建时出现一次**。
  ///
  /// PAT 不受「令牌与密码绑定」影响，服务器升级也不会让已签发的 PAT 失效 ——
  /// 这正是本客户端能「登录一次、长期免登录」的前提。
  Future<String> createPersonalAccessToken({
    required String userId,
    String description = 'Android 客户端',
    int expiresInDays = 0,
  }) async {
    final Json json = await _sendResolved(
      'POST',
      '/users/$userId/personalAccessTokens',
      body: <String, Object?>{'description': description, 'expiresInDays': expiresInDays},
    );
    final String token = asStringOr(json['token'], '');
    if (token.isEmpty) {
      throw MemosApiException('服务端未返回 PAT（token 字段为空）');
    }
    return token;
  }

  /// GET /api/instance/profile —— 用于版本守门。
  Future<InstanceProfile> getProfile() async =>
      InstanceProfile.fromJson(await _sendResolved('GET', '/instance/profile'));

  /// GET /api/auth/me —— 用当前凭据换回用户，顺带校验凭据是否仍然有效。
  ///
  /// 凭据被服务端拒绝时抛 [MemosApiException]，且
  /// [MemosApiException.isUnauthenticated] 为 true（HTTP 401 / Connect code 16）。
  Future<RemoteUser> getCurrentUser() async {
    final Json json = await _sendResolved('GET', '/auth/me');
    return RemoteUser.fromJson(asJson(json['user']));
  }
}

/// [MemosClient.signIn] 的结果。
class SignInResult {
  const SignInResult({required this.user, required this.accessToken});

  final RemoteUser user;
  final String accessToken;
}
