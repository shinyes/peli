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

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('MemosApiException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode');
    if (code != null) buffer.write(', code $code');
    if (statusCode != null) buffer.write(')');
    return buffer.toString();
  }
}

/// memos 0.31.0 API 客户端。
///
/// 只实现本客户端需要的一小部分端点 —— 登录、换取长效 PAT、读取实例版本。
/// 拿到 PAT 之后，所有业务请求都由页面里的官方前端自己发起。
///
/// 全部走 grpc-gateway 的 REST 形态（protojson），不依赖 Connect-RPC 与代码生成。
class MemosClient {
  MemosClient({
    required Uri baseUrl,
    this.accessToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _baseUrl = _normalizeBase(baseUrl),
        _http = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _http;

  /// 当前使用的凭据：登录后是短效 access token，换取 PAT 后是长效 PAT。
  String? accessToken;

  /// 单请求超时。
  final Duration timeout;

  Uri get baseUrl => _baseUrl;

  void close() => _http.close();

  static Uri _normalizeBase(Uri url) {
    Uri result = url;
    if (!result.hasScheme) {
      result = Uri.parse('https://$url');
    }
    // 去掉结尾的 /api/v1 或斜杠，统一成站点根。
    String path = result.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/api/v1')) {
      path = path.substring(0, path.length - '/api/v1'.length);
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
      path: '${_baseUrl.path}$path',
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

  // -------------------------------------------------------------------------
  // 认证与实例
  // -------------------------------------------------------------------------

  /// 用户名密码登录，返回**短效** access token 与用户信息。
  ///
  /// 客户端主要用它来换取长效 PAT（见 [createPersonalAccessToken]）。
  Future<SignInResult> signIn({required String username, required String password}) async {
    final Json json = await _send('POST', '/api/v1/auth/signin', body: <String, Object?>{
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
  Future<String> createPersonalAccessToken({
    required String userId,
    String description = 'Android 客户端',
    int expiresInDays = 0,
  }) async {
    final Json json = await _send(
      'POST',
      '/api/v1/users/$userId/personalAccessTokens',
      body: <String, Object?>{'description': description, 'expiresInDays': expiresInDays},
    );
    final String token = asStringOr(json['token'], '');
    if (token.isEmpty) {
      throw MemosApiException('服务端未返回 PAT（token 字段为空）');
    }
    return token;
  }

  /// `GET /api/v1/instance/profile` —— 用于版本守门。
  Future<InstanceProfile> getProfile() async =>
      InstanceProfile.fromJson(await _send('GET', '/api/v1/instance/profile'));
}

/// [MemosClient.signIn] 的结果。
class SignInResult {
  const SignInResult({required this.user, required this.accessToken});

  final RemoteUser user;
  final String accessToken;
}
