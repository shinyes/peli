import 'dart:async';
import 'dart:io';
import 'dart:math';

/// 应用内回环媒体流代理 —— 让 WebView 里的 `<video>` 恢复**原生流式播放**。
///
/// ## 为什么需要它
///
/// memos 的附件端点（`/file/...`）只认两种凭据：`Authorization: Bearer`
/// （Access Token / PAT）或服务端签发的 refresh-token cookie（见服务端
/// `fileserver.go` 的 `getCurrentUser` → `authenticator.AuthenticateToUser`）。
/// 而 `<video>` 元素发起的请求**带不上自定义请求头**，WebView 里也没有会话
/// cookie —— 私有附件必然 401。
///
/// 曾经的做法是 JS 里带 Bearer `fetch` 整段下载再换 blob URL：能播，但必须等
/// **整个文件**下载完才出声，且网格里每个视频一进页面就全量下载（`preload`
/// 语义全丢）。服务端其实一直支持流式（LOCAL → `http.ServeFile`、数据库 →
/// `http.ServeContent`、S3 → 透传单段 Range，都原生支持 206/Content-Range），
/// 瓶颈只在"元素请求无法携带凭据"。
///
/// ## 工作原理
///
/// ```
/// <video src="http://127.0.0.1:<port>/mp-<secret>/file/...">
///   → 本代理（补 Authorization 头，透传 Range/条件请求头）
///   → memos 服务端（200/206 + Content-Range + Accept-Ranges）
///   → 字节即到即转交 WebView，Chromium 媒体引擎边下边播、可拖动
/// ```
///
/// JS 侧（`web_app_page.dart` 的 `_AttachmentImagePatcher.script`）负责把
/// `/file/...` 的 src/poster 重写到 [baseUrl]；代理不可用或请求被拦时，
/// 页面脚本自动退回旧的"整段下载 → blob"路径。
///
/// ## 安全边界
///
/// - 只绑定回环地址（`InternetAddress.loopbackIPv4`），外部网络不可达；
/// - 路径必须带每次启动随机生成的 secret 前缀，且只放行 `/file/` 开头的
///   路径 —— 同设备其它应用既猜不到前缀，也无法把代理当成访问服务端其它
///   接口（如 RPC）的跳板；
/// - PAT 只附加到发往用户自己实例（[configure] 指定的 upstream）的请求上；
/// - 服务端对私有附件的 `Cache-Control: private, no-store` 原样透传，明文
///   视频**不会**进 Chromium 的 HTTP 磁盘缓存（与"视频不落盘"的既有约束一致）。
///
/// ## 平台前提（已核实）
///
/// - Chromium 把 `http://127.0.0.1` 视为"潜在可信源"：https 页面加载它
///   **不算混合内容**；
/// - Android 明文流量策略已在 `res/xml/network_security_config.xml` 放行；
/// - 媒体元素会挂 `crossOrigin="anonymous"`（官方 `VideoPoster.tsx` 用
///   canvas 抓首帧，跨源视频不带 CORS 模式会污染 canvas），因此这里回
///   `Access-Control-Allow-*` 头并处理 OPTIONS 预检 —— cors 模式下带
///   `Range` 的请求会先预检。
class MediaStreamProxy {
  /// 创建（尚未启动）的代理。
  MediaStreamProxy();

  HttpServer? _server;
  String _secret = '';
  Uri? _upstream;
  String _token = '';
  final HttpClient _client = HttpClient();

  /// 代理基地址（含随机前缀），如 `http://127.0.0.1:43211/mp-ab12...`。
  ///
  /// 未启动（或启动失败）时为空串 —— JS 侧据此退回整段下载路径。
  String get baseUrl {
    final HttpServer? server = _server;
    if (server == null) return '';
    return 'http://127.0.0.1:${server.port}/$_secret';
  }

  /// 绑定回环地址上的随机端口。重复调用无副作用。
  Future<void> start() async {
    if (_server != null) return;
    final Random random = Random.secure();
    final StringBuffer secret = StringBuffer('mp-');
    for (int i = 0; i < 32; i++) {
      secret.write(random.nextInt(16).toRadixString(16));
    }
    _secret = secret.toString();
    // 媒体流可能长时间挂着慢速连接，放宽默认 15s 的空闲超时。
    _client.idleTimeout = const Duration(seconds: 60);
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      (HttpRequest request) => unawaited(_handle(request)),
      onError: (Object error) {
        // ignore: avoid_print
        print('[media-proxy] listener error: $error');
      },
    );
  }

  /// 设置转发目标与凭据（账号切换/令牌变化时重复调用即可）。
  void configure({required Uri upstream, required String token}) {
    _upstream = upstream;
    _token = token;
  }

  /// 关闭监听与所有连接。可在 `dispose` 里直接调用（不等待）。
  void stop() {
    _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  /// 需要转发给上游的请求头（Range 语义与条件请求）。
  static const List<String> _forwardRequestHeaders = <String>[
    HttpHeaders.rangeHeader,
    HttpHeaders.ifRangeHeader,
    HttpHeaders.ifModifiedSinceHeader,
    HttpHeaders.ifNoneMatchHeader,
  ];

  /// 需要回传给 WebView 的响应头。
  ///
  /// 媒体引擎依赖 `Content-Range`/`Accept-Ranges` 决定能否拖动进度条；
  /// `Cache-Control` 透传服务端的 `private, no-store`，明文视频不进磁盘缓存。
  static const List<String> _copyResponseHeaders = <String>[
    HttpHeaders.contentTypeHeader,
    HttpHeaders.contentRangeHeader,
    HttpHeaders.acceptRangesHeader,
    HttpHeaders.cacheControlHeader,
    HttpHeaders.lastModifiedHeader,
    HttpHeaders.etagHeader,
    'content-disposition', // HttpHeaders 没有对应常量
  ];

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse out = request.response;
    try {
      final Uri? upstream = _upstream;
      final String prefix = '/$_secret/file/';
      // 守卫：必须带随机前缀，且只代理 /file/ 路径（防开放转发）。
      if (upstream == null || _token.isEmpty || !request.uri.path.startsWith(prefix)) {
        out.statusCode = HttpStatus.forbidden;
        await out.close();
        return;
      }

      _setCorsHeaders(out, request);

      if (request.method == 'OPTIONS') {
        // CORS 预检（crossOrigin 模式下带 Range 的请求会先走这里）。
        out.statusCode = HttpStatus.noContent;
        out.headers.set('access-control-allow-methods', 'GET, HEAD, OPTIONS');
        out.headers.set(
          'access-control-allow-headers',
          request.headers.value('access-control-request-headers') ?? '*',
        );
        out.headers.set('access-control-max-age', '86400');
        await out.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        out.statusCode = HttpStatus.methodNotAllowed;
        await out.close();
        return;
      }

      final Uri target = _resolveTarget(upstream, prefix, request.uri);
      final HttpClientRequest forward = await _client.openUrl(request.method, target);
      forward.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      for (final String name in _forwardRequestHeaders) {
        final String? value = request.headers.value(name);
        if (value != null) forward.headers.set(name, value);
      }
      final HttpClientResponse response = await forward.close();

      out.statusCode = response.statusCode;
      // 媒体流必须即到即转：攒满缓冲区再发会直接拖慢首帧。
      out.bufferOutput = false;
      if (response.contentLength >= 0) {
        out.contentLength = response.contentLength;
      }
      for (final String name in _copyResponseHeaders) {
        final String? value = response.headers.value(name);
        if (value != null) out.headers.set(name, value);
      }

      if (request.method == 'HEAD') {
        // 排空上游（HEAD 响应本就没有体），让连接归还连接池。
        unawaited(response.drain<void>().catchError((Object _) {}));
        await out.close();
        return;
      }

      try {
        await out.addStream(response);
      } catch (_) {
        // WebView 中途断开是**正常行为**：Chromium 媒体引擎读完元数据/moov
        // 就会掐掉连接，随后按 Range 重新发起请求；拖动进度条同理。
      }
      await out.close();
    } catch (error) {
      // ignore: avoid_print
      print('[media-proxy] ${request.method} ${request.uri.path} failed: $error');
      try {
        out.statusCode = HttpStatus.badGateway;
        await out.close();
      } catch (_) {
        // 响应已开始或连接已断：无事可做。
      }
    }
  }

  /// 把代理路径还原成上游地址（保留查询串与百分号编码）。
  Uri _resolveTarget(Uri upstream, String prefix, Uri requestUri) {
    String basePath = upstream.path;
    if (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    // prefix 形如 `/mp-<secret>/file/`；取其后的剩余部分，重新冠上 `/file/`，
    // 得到上游认得的原始路径。
    final String subPath = '/file/${requestUri.path.substring(prefix.length)}';
    Uri target = upstream.replace(path: '$basePath$subPath');
    if (requestUri.hasQuery) {
      target = target.replace(query: requestUri.query);
    }
    return target;
  }

  void _setCorsHeaders(HttpResponse out, HttpRequest request) {
    final String? origin = request.headers.value('origin');
    out.headers.set('access-control-allow-origin', origin ?? '*');
    if (origin != null) {
      out.headers.set('vary', 'Origin');
    }
    // 媒体引擎/canvas 需要读到这些跨源响应头。
    out.headers.set(
      'access-control-expose-headers',
      'Content-Length, Content-Range, Accept-Ranges, Content-Type',
    );
  }
}
