package peli.lcyk.cc

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.util.Log
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 主 Activity：全面屏适配 + 接收系统分享。
///
/// ## 接收分享
///
/// 用户在相册里点「分享 → Memos」时走 `ACTION_SEND`。这条路的**关键价值**是：
/// MIUI/HyperOS 的分享面板会按用户设置**把 HEIC 转成 JPEG 再交出来**
/// （这正是 `<input type="file">` 那条路做不到的 —— 文件选择器不经过分享面板）。
///
/// 由于 manifest 里是 `launchMode="singleTop"`，分享可能发生在两种时机：
/// - App 没运行 → `onCreate` 里的 `intent`
/// - App 已在运行 → `onNewIntent`
///
/// 两条路都把文件**复制到应用缓存目录**再交给 Dart。为什么要复制：
/// 分享 URI 的读权限只对本次 Intent 生命周期有效，稍后再读可能已失效；
/// 而且复制后拿到的是真实文件路径，后续上传不必再依赖 URI 授权。
///
/// **必须声明并申请媒体权限**（`READ_MEDIA_IMAGES` / Android 13 起细分）：
/// 缺权限时 `contentResolver.openInputStream()` 会抛异常，表现为"分享进来了
/// 但文件是空的" —— 不报错、极难排查。见 [requestMediaPermissionIfNeeded]。
class MainActivity : FlutterActivity() {
    override fun onPostResume() {
        super.onPostResume()
        applyEdgeToEdge()
    }

    private fun applyEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // 允许内容延伸进刘海/挖孔区域；Flutter 的 SafeArea 保证内容不被遮挡。
            // 主题里已声明 windowLayoutInDisplayCutoutMode=shortEdges，这里再兜一层，
            // 因为部分 OEM（MIUI/HyperOS）在运行期会重置该属性。
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    // 关于截图：**不设置 FLAG_SECURE**，允许用户在应用内截图。
    //
    // 曾有版本设了它（禁截屏、最近任务预览变空白）。已按要求移除，理由也站得住：
    // FLAG_SECURE 对**存储安全没有贡献** —— 它只影响屏幕捕获与任务切换预览，
    // 不改变磁盘上的任何字节。真正的保护在别处：
    //   - 令牌只在内存（localStorage 覆写，永不落盘）
    //   - 图片缓存为 AES-GCM 密文，密钥由 Keystore 保护
    //   - 进入后台清理 HTTP 明文缓存
    //
    // 代价（如实记录）：截图与「最近任务」预览会包含明文正文与图片，
    // 那是用户主动发起的操作，不属于"本地数据被静默提取"。

    // ---------------------------------------------------------------------------
    // 分享接收
    // ---------------------------------------------------------------------------

    private var shareChannel: MethodChannel? = null

    /// 冷启动时收到的分享（Dart 侧就绪后主动来取）。
    private var initialShare: Map<String, Any?>? = null

    /// 因缺媒体权限而暂时读不出的分享 URI；拿到权限后重试。
    private var pendingShareUris: List<Uri>? = null

    /// 是否已经申请过权限（用户拒绝后不再反复打扰）。
    private var permissionRequested = false

    /// 权限请求码。
    private val mediaPermissionRequestCode = 1001

    /// 通用权限请求（定位 / 麦克风）：请求码 → 等待中的 Dart 回执。
    ///
    /// 用 Map 而不是单个变量：虽然实际同一时刻只会有一个挂起请求（新请求会先
    /// 让旧的失败返回），但按请求码存放能让 [onRequestPermissionsResult] 的
    /// 匹配逻辑保持简单、可扩展。
    private val pendingPermissionRequests =
        mutableMapOf<Int, MethodChannel.Result>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 分享内容有两条来源：
        // 1. [ShareReceiverActivity]（不可见跳板）转发来的 extras —— 文件已经复制到
        //    私有缓存，且主界面始终在自己的任务里被复用，这是正常路径；
        // 2. 直接从原始 Intent 提取 —— 跳板复制失败（缺媒体权限）时的兜底，
        //    以及 adb / 直接指定组件启动的调试路径。
        initialShare = ShareFiles.readPayload(this, intent) ?: extractShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        val payload = initialShare
                        initialShare = null   // 只消费一次，避免每次热启动重复注入
                        result.success(payload)
                    }
                    // 把文件路径转成 content:// URI。
                    //
                    // 为什么必须这么做：WebView 的文件选择结果要交给**沙箱渲染进程**
                    // 读取，而 `file://` 在现代 WebView 上默认不可跨进程访问
                    //（`setAllowFileAccess` 对 targetSdk 30+ 默认 false）。
                    // 表现出来就是"路径已返回、文件存在且可读，但页面毫无变化"。
                    // `content://` 是 Android 为跨进程文件访问设计的正规机制。
                    "toContentUris" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        val uris = paths.mapNotNull { path -> toContentUri(path) }
                        Log.i(
                            TAG,
                            "[webview-file] toContentUris in=${paths.size} out=${uris.size} $uris",
                        )
                        result.success(uris)
                    }
                    // 通用运行时权限请求（定位 / 麦克风）。
                    //
                    // 为什么需要：网页发出的 `getUserMedia` 与 `geolocation` 在 WebView 里
                    // 有**内外两道**关卡 —— 外层是这里申请的系统权限，内层是
                    // WebChromeClient 的放行回调。缺任何一道都会静默失败：
                    // 用户看不到任何提示，网页只拿到一个没有说明的错误。
                    //
                    // 为什么做成通用接口而不是为每种权限写一个方法：权限会随功能增加，
                    // 每加一种都改协议不划算。返回 Map 让 Dart 侧能区分
                    // "用户拒绝" 与 "还没请求（结果未归）"。
                    "requestPermissions" -> {
                        val permissions = call.argument<List<String>>("permissions") ?: emptyList()
                        val code = call.argument<Int>("requestCode") ?: PERMISSION_REQUEST_CODE
                        if (permissions.isEmpty()) {
                            result.success(emptyMap<String, Boolean>())
                            return@setMethodCallHandler
                        }
                        val missing = permissions.filter {
                            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                        }
                        if (missing.isEmpty()) {
                            result.success(permissions.associateWith { true })
                            return@setMethodCallHandler
                        }
                        // 同一时刻只允许一个挂起请求：重复调用会让前一个永久等不到结果。
                        pendingPermissionRequests.values.forEach { it.success(false) }
                        pendingPermissionRequests.clear()
                        pendingPermissionRequests[code] = result
                        Log.i(TAG, "[perm] requesting $missing (code=$code)")
                        requestPermissions(missing.toTypedArray(), code)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /// 把一个文件路径转成 `content://` URI，供 WebView 渲染进程读取。
    ///
    /// 用的是**本应用自己注册的** FileProvider
    /// （`AndroidManifest.xml` 里 authority = `${applicationId}.webview.fileprovider`，
    /// 路径范围见 `res/xml/webview_file_paths.xml`：`<cache-path path="webview_uploads/"/>`）。
    ///
    /// ⚠️ 文件必须位于 `getCacheDir()/webview_uploads/` —— `<cache-path>` 对应
    /// `getCacheDir()`，**不包括** `getCodeCacheDir()`（`code_cache`）。
    /// 放错目录时 `getUriForFile` 会抛 `IllegalArgumentException`。
    ///
    /// 失败返回 null（调用方跳过该文件），不抛异常 —— 单个文件失败不该让整次选择失败。
    private fun toContentUri(path: String): String? {
        return try {
            val source = File(path)
            if (!source.exists()) {
                Log.w(TAG, "[webview-file] source missing: $path")
                return null
            }
            val provider = FileProvider.getUriForFile(
                this,
                packageName + WEBVIEW_PROVIDER_SUFFIX,
                source,
            )
            // 显式授出读权限，覆盖 WebView 需要跨进程读取的场景。
            try {
                grantUriPermission(
                    packageName,
                    provider,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (error: Exception) {
                Log.w(TAG, "[webview-file] grantUriPermission failed: $error")
            }
            provider.toString()
        } catch (error: Exception) {
            Log.w(TAG, "[webview-file] toContentUri failed for $path: $error")
            null
        }
    }


    /// App 已在运行时收到新的分享。
    ///
    /// 正常路径是 [ShareReceiverActivity] 用 `NEW_TASK` 把 Intent 送到已有实例上
    /// （任务被带到前台，不会新建任务、也不会被并进分享方的任务）。
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = ShareFiles.readPayload(this, intent) ?: extractShare(intent) ?: run {
            // 读不出来时 extractShare 已经记下 URI 并去申请权限，
            // 拿到权限后会通过 [retryPendingShareAfterPermission] 补给 Dart。

            return
        }

        deliverShare(payload)
    }

    /// 把分享内容交给 Dart 侧。
    ///
    /// Dart 可能还没准备好（例如页面正在重建）：先存起来，等它 `getInitialShare` 时再给。
    private fun deliverShare(payload: Map<String, Any?>) {
        val count = (payload["paths"] as? List<*>)?.size ?: 0
        Log.i(TAG, "[share] deliver $count file(s) to Dart (channel=${shareChannel != null})")
        if (shareChannel == null) {
            initialShare = payload
        } else {
            shareChannel?.invokeMethod("onShared", payload)
        }
    }

    /// 从**原始**分享 Intent 里提取内容（跳板复制失败或直接启动时的兜底路径）。
    ///
    /// 支持 `ACTION_SEND`（单张）与 `ACTION_SEND_MULTIPLE`（多张）。
    ///
    /// 读不到时会**申请媒体权限并重试**，见 [retryPendingShareAfterPermission]。
    private fun extractShare(intent: Intent?): Map<String, Any?>? {
        if (!ShareFiles.isShareAction(intent)) return null
        val source = intent ?: return null

        val uris = ShareFiles.streamUris(source)
        if (uris.isEmpty()) return null

        val copied = ShareFiles.copyAll(this, source, uris)
        Log.i(TAG, "[share] extractShare: ${uris.size} uri(s) -> cached ${copied.size}")

        // 一张都没读出来：大概率是缺媒体权限（Android 13+ 的 READ_MEDIA_IMAGES）。
        // 记下 URI 去申请权限，拿到后重试。
        if (copied.isEmpty()) {
            pendingShareUris = uris
            requestMediaPermissionIfNeeded()
            return null
        }

        pendingShareUris = null
        return ShareFiles.payload(copied)
    }

    /// 缺少媒体权限时申请一次。
    ///
    /// 背景：分享 Intent 只给一个 `content://` URI，真正读字节时受媒体权限管控。
    /// 缺权限时 `openInputStream` 抛异常 —— 表现为"分享进来了但文件是空的"。
    /// Android 13 起权限细分为 `READ_MEDIA_IMAGES`，更早版本用 `READ_EXTERNAL_STORAGE`。
    private fun requestMediaPermissionIfNeeded() {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_IMAGES
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            // 有权限却仍读不出：说明不是权限问题（例如 URI 已失效），不再重试。

            return
        }
        if (permissionRequested) return   // 用户已拒绝过，不再打扰
        permissionRequested = true
        Log.i(TAG, "[share] requesting $permission to read shared image")
        // 用传统 API 而不是 registerForActivityResult：FlutterActivity 自己接管了
        // activity-result 的分发，注册进去的 launcher 收不到回调。
        requestPermissions(arrayOf(permission), mediaPermissionRequestCode)
    }

    /// 权限结果回调（传统 API，配合 [requestMediaPermissionIfNeeded] 与通用请求）。
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        // 通用请求（定位 / 麦克风）：把逐项结果回给 Dart
        val pending = pendingPermissionRequests.remove(requestCode)
        if (pending != null) {
            val outcome = mutableMapOf<String, Boolean>()
            for (i in permissions.indices) {
                outcome[permissions[i]] =
                    i < grantResults.size && grantResults[i] == PackageManager.PERMISSION_GRANTED
            }
            Log.i(TAG, "[perm] result code=$requestCode $outcome")
            pending.success(outcome)
            return
        }

        if (requestCode != mediaPermissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        Log.i(TAG, "[share] media permission granted=$granted")
        if (granted) retryPendingShareAfterPermission()
    }

    /// 权限结果回来后重试读取，并把结果补给 Dart 侧。
    private fun retryPendingShareAfterPermission() {
        val uris = pendingShareUris ?: return
        val copied = ShareFiles.copyAll(this, intent, uris)
        Log.i(TAG, "[share] retry after permission -> cached ${copied.size}")
        if (copied.isEmpty()) return
        pendingShareUris = null
        deliverShare(ShareFiles.payload(copied))
    }

    private companion object {
        const val SHARE_CHANNEL = "app.memos/share"
        const val TAG = "MemosShare"

        /// 本应用自己注册的 FileProvider authority 后缀
        /// （manifest 里声明为 `${applicationId}.webview.fileprovider`，
        /// 运行时拼上实际包名）。
        const val WEBVIEW_PROVIDER_SUFFIX = ".webview.fileprovider"

        /// 通用权限请求的默认请求码（Dart 可显式指定以区分调用方）。
        const val PERMISSION_REQUEST_CODE = 2001
    }
}
