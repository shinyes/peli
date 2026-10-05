import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:peli/features/web/media_proxy.dart';

/// 验证回环媒体代理的转发语义：鉴权头注入、Range/206 透传、CORS、路径守卫。
///
/// 假上游模仿 memos 的 `/file/...` 端点（`fileserver.go`）：
/// - 只认 `Authorization: Bearer`；
/// - LOCAL/DB 存储经 `http.ServeFile`/`http.ServeContent` 原生支持单段 Range；
/// - 私有附件回 `Cache-Control: private, no-store`。
void main() {
  const String token = 'memos_pat_test';
  final Uint8List payload = Uint8List.fromList(
    List<int>.generate(4096, (int i) => (i * 31 + 7) % 256),
  );

  late HttpServer origin;
  late MediaStreamProxy proxy;
  late List<String> authHeaders;
  late List<String> seenTargets;

  Future<void> handleOrigin(HttpRequest request) async {
    authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
    seenTargets.add('${request.method} ${request.uri}');
    final HttpResponse out = request.response;
    // 支持带子路径部署（configure 时 upstream 含 basePath）。
    final String path = request.uri.path;
    if (path != '/file/a/video.mp4' && path != '/sub/file/a/video.mp4') {
      out.statusCode = HttpStatus.notFound;
      await out.close();
      return;
    }
    out.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
    out.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    out.headers.set(HttpHeaders.cacheControlHeader, 'private, no-store');
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (request.method == 'HEAD') {
      out.statusCode = HttpStatus.ok;
      out.contentLength = payload.length;
      await out.close();
      return;
    }
    if (range != null) {
      final RegExpMatch? match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      final int start = int.tryParse(match?.group(1) ?? '') ?? 0;
      final int end = int.tryParse(match?.group(2) ?? '') ?? payload.length - 1;
      out.statusCode = HttpStatus.partialContent;
      out.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${payload.length}',
      );
      out.contentLength = end - start + 1;
      out.add(payload.sublist(start, end + 1));
    } else {
      out.statusCode = HttpStatus.ok;
      out.contentLength = payload.length;
      out.add(payload);
    }
    await out.close();
  }

  setUp(() async {
    authHeaders = <String>[];
    seenTargets = <String>[];
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((HttpRequest request) => unawaited(handleOrigin(request)));
    proxy = MediaStreamProxy();
    await proxy.start();
    proxy.configure(
      upstream: Uri.parse('http://127.0.0.1:${origin.port}'),
      token: token,
    );
  });

  tearDown(() async {
    proxy.stop();
    await origin.close(force: true);
  });

  /// 经代理访问的完整 URL（[suffix] 拼在随机前缀之后）。
  Uri proxied([String suffix = '/file/a/video.mp4']) =>
      Uri.parse('${proxy.baseUrl}$suffix');

  int proxyPort() => int.parse(proxy.baseUrl.split(':')[2].split('/').first);

  Future<Uint8List> readBody(HttpClientResponse response) async {
    final BytesBuilder builder = BytesBuilder(copy: true);
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  group('转发语义', () {
    test('GET 注入 Bearer 头并原样回传字节与关键响应头', () async {
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.getUrl(proxied())).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.contentTypeHeader), 'video/mp4');
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        'private, no-store',
      );
      expect(await readBody(response), payload);
      expect(authHeaders.single, 'Bearer $token');
      client.close();
    });

    test('Range 请求透传为 206 + Content-Range + 精确切片', () async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(proxied());
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/${payload.length}',
      );
      expect(response.contentLength, 100);
      expect(await readBody(response), payload.sublist(100, 200));
      client.close();
    });

    test('开放区间的 Range（Chromium 首个媒体请求的形态）也能透传', () async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(proxied());
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-${payload.length - 1}/${payload.length}',
      );
      expect(await readBody(response), payload);
      client.close();
    });

    test('查询串保留（motion/thumbnail/share_token 选择器）', () async {
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.getUrl(proxied('/file/a/video.mp4?motion=true'))).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(seenTargets.single, contains('motion=true'));
      await readBody(response);
      client.close();
    });

    test('upstream 带子路径时正确拼接', () async {
      proxy.configure(
        upstream: Uri.parse('http://127.0.0.1:${origin.port}/sub'),
        token: token,
      );
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.getUrl(proxied())).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(seenTargets.single, contains('/sub/file/a/video.mp4'));
      expect(await readBody(response), payload);
      client.close();
    });

    test('HEAD 返回头与长度、不带体', () async {
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.openUrl('HEAD', proxied())).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, payload.length);
      expect(await readBody(response), isEmpty);
      client.close();
    });
  });

  group('守卫', () {
    test('缺少随机前缀 → 403，且不打到上游', () async {
      final HttpClient client = HttpClient();
      final Uri uri = Uri.parse('http://127.0.0.1:${proxyPort()}/file/a/video.mp4');
      final HttpClientResponse response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, HttpStatus.forbidden);
      expect(authHeaders, isEmpty);
      client.close();
    });

    test('带前缀但非 /file/ 路径 → 403（防开放转发到 RPC 等端点）', () async {
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.getUrl(proxied('/api/v1/memos'))).close();
      expect(response.statusCode, HttpStatus.forbidden);
      expect(authHeaders, isEmpty);
      client.close();
    });

    test('上游不可达 → 502，代理本身存活', () async {
      await origin.close(force: true);
      final HttpClient client = HttpClient();
      final HttpClientResponse response =
          await (await client.getUrl(proxied())).close();
      expect(response.statusCode, HttpStatus.badGateway);
      client.close();
    });
  });

  group('CORS（crossOrigin=anonymous 的媒体元素）', () {
    test('OPTIONS 预检 → 204 + Allow-* 头', () async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request =
          await client.openUrl('OPTIONS', proxied());
      request.headers.set('Origin', 'https://memos.example.com');
      request.headers.set('Access-Control-Request-Method', 'GET');
      request.headers.set('Access-Control-Request-Headers', 'range');
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, HttpStatus.noContent);
      expect(
        response.headers.value('access-control-allow-origin'),
        'https://memos.example.com',
      );
      expect(response.headers.value('access-control-allow-headers'), 'range');
      expect(
        response.headers.value('access-control-allow-methods'),
        contains('GET'),
      );
      await readBody(response);
      client.close();
    });

    test('带 Origin 的 GET → 回显 ACAO + expose 头', () async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(proxied());
      request.headers.set('Origin', 'https://memos.example.com');
      final HttpClientResponse response = await request.close();
      expect(
        response.headers.value('access-control-allow-origin'),
        'https://memos.example.com',
      );
      expect(
        response.headers.value('access-control-expose-headers'),
        contains('Content-Range'),
      );
      expect(await readBody(response), payload);
      client.close();
    });
  });

  group('流式与断开', () {
    test('客户端中途断开（Chromium 读完 moov 就掐连接）后代理仍能服务后续请求', () async {
      final HttpClient client = HttpClient();
      final HttpClientResponse first =
          await (await client.getUrl(proxied())).close();
      expect(first.statusCode, HttpStatus.ok);
      final Completer<void> gotFirstChunk = Completer<void>();
      void arrive() {
        if (!gotFirstChunk.isCompleted) gotFirstChunk.complete();
      }

      final StreamSubscription<List<int>> subscription = first.listen(
        (List<int> _) => arrive(),
        onError: (Object _) => arrive(),
        onDone: arrive,
      );
      await gotFirstChunk.future;
      await subscription.cancel();

      // 断开后立刻再来一次完整请求（模拟按 Range 重连）。
      final HttpClientResponse second =
          await (await client.getUrl(proxied())).close();
      expect(second.statusCode, HttpStatus.ok);
      expect(await readBody(second), payload);
      client.close();
    });
  });
}
