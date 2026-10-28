import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:memos_api/memos_api.dart';
import 'package:test/test.dart';

/// 客户端只保留「登录 → 换 PAT → 版本守门 → 校验凭据」这条链路，测试也只覆盖它。
void main() {
  group('InstanceProfile 版本守门', () {
    test('0.31.0 及以上通过，其余拒绝', () {
      expect(const InstanceProfile(version: '0.31.0').isSupported, isTrue);
      expect(const InstanceProfile(version: '0.31.1').isSupported, isTrue);
      expect(const InstanceProfile(version: '1.0.0').isSupported, isTrue);
      expect(const InstanceProfile(version: '26.09').isSupported, isTrue, reason: '日历版本');
      expect(const InstanceProfile(version: '26.10.0-rc.2').isSupported, isTrue,
          reason: '26.10 的发布候选版');
      expect(const InstanceProfile(version: '0.30.0').isSupported, isFalse);
      expect(const InstanceProfile(version: 'dev').isSupported, isFalse);
    });

    test('从 JSON 解析（字段缺失不抛异常）', () {
      expect(InstanceProfile.fromJson(const <String, Object?>{'version': '0.31.0'}).version, '0.31.0');
      expect(InstanceProfile.fromJson(const <String, Object?>{}).version, '');
      expect(InstanceProfile.fromJson(const <String, Object?>{}).isSupported, isFalse);
    });
  });

  group('MemosClient 路由（26.10 去掉了 /api/v1 段）', () {
    test('baseUrl 归一化（去掉 /api/v1、/api 与尾斜杠）', () {
      expect(
        MemosClient(baseUrl: Uri.parse('https://a.example.com/api/v1')).baseUrl.toString(),
        'https://a.example.com',
      );
      expect(
        MemosClient(baseUrl: Uri.parse('https://a.example.com/api')).baseUrl.toString(),
        'https://a.example.com',
      );
      expect(
        MemosClient(baseUrl: Uri.parse('https://a.example.com/')).baseUrl.toString(),
        'https://a.example.com',
      );
      expect(
        MemosClient(baseUrl: Uri.parse('https://a.example.com/memos/')).baseUrl.toString(),
        'https://a.example.com/memos',
      );
    });

    test('signIn 提交 passwordCredentials 并解析令牌与用户', () async {
      late http.BaseRequest captured;
      late String body;
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        captured = request;
        body = payload;
        return _json(<String, Object?>{
          'user': <String, Object?>{'name': 'users/1', 'username': 'steven', 'displayName': 'Steven'},
          'accessToken': 'short-lived-token',
        });
      });

      final SignInResult session = await client.signIn(username: 'steven', password: 'pw');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/auth/signin');
      expect(
        jsonDecode(body),
        <String, Object?>{
          'passwordCredentials': <String, Object?>{'username': 'steven', 'password': 'pw'},
        },
      );
      expect(session.accessToken, 'short-lived-token');
      expect(session.user.id, '1');
      expect(session.user.username, 'steven');
      expect(session.user.displayName, 'Steven');
    });

    test('createPersonalAccessToken 用 users/{id} 资源名并回传 token', () async {
      late http.BaseRequest captured;
      late String body;
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        captured = request;
        body = payload;
        return _json(<String, Object?>{'token': 'memos_pat_abc'});
      });

      final String token = await client.createPersonalAccessToken(userId: '1');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/users/1/personalAccessTokens');
      // expiresInDays=0 表示永不过期。
      expect(jsonDecode(body), <String, Object?>{'description': 'Android 客户端', 'expiresInDays': 0});
      expect(token, 'memos_pat_abc');
    });

    test('服务端没回 token 时抛异常（避免把空串当凭据存下来）', () async {
      final MemosClient client = _client(
        (http.BaseRequest request, String payload) => _json(const <String, Object?>{}),
      );
      await expectLater(
        client.createPersonalAccessToken(userId: '1'),
        throwsA(isA<MemosApiException>()),
      );
    });

    test('getProfile 请求实例信息', () async {
      late http.BaseRequest captured;
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        captured = request;
        return _json(<String, Object?>{'version': '26.10.0-rc.2'});
      });

      final InstanceProfile profile = await client.getProfile();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/instance/profile');
      expect(profile.isSupported, isTrue);
    });

    test('getCurrentUser 走 /api/auth/me 并解析用户', () async {
      late http.BaseRequest captured;
      final MemosClient client = MemosClient(
        baseUrl: Uri.parse('https://a.example.com'),
        accessToken: 'memos_pat_abc',
        httpClient: _RecordingClient(
          responder: (http.BaseRequest request, String body) {
            captured = request;
            return _json(<String, Object?>{
              'user': <String, Object?>{'name': 'users/steven', 'username': 'steven'},
            });
          },
        ),
      );

      final RemoteUser user = await client.getCurrentUser();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/auth/me');
      expect(captured.headers['Authorization'], 'Bearer memos_pat_abc');
      expect(user.id, 'steven');
    });

    test('老服务端：/api 下没有路由时退回 /api/v1，且之后固定用旧前缀', () async {
      final List<String> paths = <String>[];
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        paths.add(request.url.path);
        // 0.31.x 只有 /api/v1/*：新前缀一律 404。
        if (request.url.path.startsWith('/api/') && !request.url.path.startsWith('/api/v1/')) {
          return http.Response('404 page not found', 404);
        }
        return _json(<String, Object?>{'version': '0.31.0'});
      });

      final InstanceProfile profile = await client.getProfile();
      expect(profile.version, '0.31.0');
      expect(paths, <String>['/api/instance/profile', '/api/v1/instance/profile']);
      expect(client.apiPrefix, MemosClient.legacyApiPrefix);

      // 第二次请求不再探测。
      await client.getProfile();
      expect(paths.last, '/api/v1/instance/profile');
      expect(paths.length, 3);
    });

    test('26.10 的 410 Gone 同样触发回退（防御性）', () async {
      final List<String> paths = <String>[];
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        paths.add(request.url.path);
        if (request.url.path.startsWith('/api/') && !request.url.path.startsWith('/api/v1/')) {
          return http.Response(
            jsonEncode(<String, Object?>{'code': 12, 'message': 'unimplemented'}),
            410,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return _json(<String, Object?>{'version': '0.31.0'});
      });

      await client.getProfile();
      expect(paths.last, '/api/v1/instance/profile');
    });

    test('401 不触发前缀回退（否则密码错误会被误判成老服务端）', () async {
      final List<String> paths = <String>[];
      final MemosClient client = _client((http.BaseRequest request, String payload) {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode(<String, Object?>{'code': 16, 'message': 'authentication required'}),
          401,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });

      await expectLater(
        client.signIn(username: 'a', password: 'b'),
        throwsA(isA<MemosApiException>()),
      );
      expect(paths, <String>['/api/auth/signin']);
    });

    test('带令牌时附上 Authorization 头', () async {
      late http.BaseRequest captured;
      final MemosClient client = MemosClient(
        baseUrl: Uri.parse('https://a.example.com'),
        accessToken: 'memos_pat_abc',
        httpClient: _RecordingClient(
          onRequest: (http.BaseRequest request, String body) => captured = request,
          responder: (http.BaseRequest request, String body) =>
              _json(const <String, Object?>{'version': '0.31.0'}),
        ),
      );

      await client.getProfile();

      expect(captured.headers['Authorization'], 'Bearer memos_pat_abc');
    });

    test('错误响应解析为 MemosApiException（含状态码与 Connect code）', () async {
      final MemosClient client = MemosClient(
        baseUrl: Uri.parse('https://a.example.com'),
        httpClient: _RecordingClient(
          responder: (http.BaseRequest request, String body) => http.Response(
            jsonEncode(<String, Object?>{'code': 16, 'message': 'authentication required'}),
            401,
            headers: const <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      await expectLater(
        client.signIn(username: 'a', password: 'b'),
        throwsA(
          isA<MemosApiException>()
              .having((MemosApiException e) => e.statusCode, 'statusCode', 401)
              .having((MemosApiException e) => e.code, 'code', 16)
              .having((MemosApiException e) => e.message, 'message', 'authentication required')
              .having((MemosApiException e) => e.isUnauthenticated, 'isUnauthenticated', isTrue),
        ),
      );
    });

    test('网络故障包装成可读消息（登录页据此提示"地址不可达"）', () async {
      final MemosClient client = MemosClient(
        baseUrl: Uri.parse('https://a.example.com'),
        httpClient: _RecordingClient(
          responder: (http.BaseRequest request, String body) => throw const SocketFailure(),
        ),
      );

      await expectLater(
        client.signIn(username: 'a', password: 'b'),
        throwsA(
          isA<MemosApiException>()
              .having((MemosApiException e) => e.message, 'message', contains('网络请求失败'))
              .having((MemosApiException e) => e.statusCode, 'statusCode', isNull)
              .having((MemosApiException e) => e.isUnauthenticated, 'isUnauthenticated', isFalse),
        ),
      );
    });
  });
}

/// 构造一个「总是返回固定响应」的客户端，并把请求与请求体记进回调。
MemosClient _client(http.Response Function(http.BaseRequest request, String body) responder) =>
    MemosClient(
      baseUrl: Uri.parse('https://a.example.com'),
      httpClient: _RecordingClient(responder: responder),
    );

http.Response _json(Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );

/// 模拟底层连接失败。
class SocketFailure implements Exception {
  const SocketFailure();

  @override
  String toString() => 'SocketException: failed to connect';
}

/// 最小化的假 HTTP 客户端：记录请求，响应由回调决定。
class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.responder, this.onRequest});

  final http.Response Function(http.BaseRequest request, String body) responder;
  final void Function(http.BaseRequest request, String body)? onRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String body = request is http.Request ? request.body : '';
    onRequest?.call(request, body);
    final http.Response response = responder(request, body);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
