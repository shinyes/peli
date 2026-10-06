package peli.lcyk.cc

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import java.io.File

/// 分享内容的落地与转交。
///
/// 抽成共用工具是因为现在有**两个**入口会碰到分享 Intent：
/// - [ShareReceiverActivity]：不可见跳板，趁对方给的 URI 授权还有效时把文件复制下来；
/// - [MainActivity]：真正消费分享的地方，同时负责"缺媒体权限"时的申请与重试。
internal object ShareFiles {
    private const val TAG = "MemosShare"

    /// 缓存文件名前缀。既是"这是分享进来的文件"的标记，也是转发时的可信校验条件。
    private const val PREFIX = "shared_"

    private const val EXTRA_PATHS = "peli.share.paths"
    private const val EXTRA_NAMES = "peli.share.names"
    private const val EXTRA_MIME_TYPES = "peli.share.mimeTypes"

    /// 复制失败时转交的"待重试 URI"（**以字符串形式**，见 [writeRetryUris]）。
    private const val EXTRA_RETRY_URIS = "peli.share.retryUris"

    /// 一个已经复制到应用私有缓存的分享文件。
    data class Copied(val path: String, val name: String, val mimeType: String)

    /// 是否是本应用支持的分享动作（`ACTION_SEND` / `ACTION_SEND_MULTIPLE`）。
    fun isShareAction(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE

    /// 取出分享携带的 URI：`ACTION_SEND` 是单张，`ACTION_SEND_MULTIPLE` 是多张。
    fun streamUris(intent: Intent): List<Uri> {
        val uris: List<Uri?> = when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                listOf(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            }
            else -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            }
        }
        return uris.filterNotNull()
    }

    /// 逐个复制到应用缓存目录；读不出来的跳过。返回空列表表示一个都没成功
    /// （多半是缺媒体权限，由调用方决定是否去申请）。
    fun copyAll(context: Context, intent: Intent, uris: List<Uri>): List<Copied> =
        uris.mapNotNull { uri -> copyToCache(context, intent.type, uri) }

    private fun copyToCache(context: Context, mimeType: String?, uri: Uri): Copied? {
        return try {
            val name = displayName(context, uri)
            val target = File(context.cacheDir, "$PREFIX${System.currentTimeMillis()}_$name")
            context.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            Copied(target.absolutePath, name, mimeType ?: "image/*")
        } catch (error: Exception) {
            Log.w(TAG, "[share] copy failed for $uri: $error")
            null
        }
    }

    /// 取原始文件名（保留扩展名，网页据此判断类型）。
    private fun displayName(context: Context, uri: Uri): String {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                val name = cursor.getString(index)
                if (!name.isNullOrBlank()) return name
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "shared_image"
    }

    /// 打包成交给 Dart 的载荷（键名与 Dart 侧 `_acceptShare` 一致）。
    fun payload(copied: List<Copied>): Map<String, Any?> = mapOf(
        "paths" to copied.map { it.path },
        "names" to copied.map { it.name },
        "mimeTypes" to copied.map { it.mimeType },
    )

    /// 把载荷写进转发 Intent（跳板 → 主界面）。
    fun writePayload(intent: Intent, payload: Map<String, Any?>) {
        intent.putStringArrayListExtra(EXTRA_PATHS, ArrayList(payload["paths"] as List<String>))
        intent.putStringArrayListExtra(EXTRA_NAMES, ArrayList(payload["names"] as List<String>))
        intent.putStringArrayListExtra(
            EXTRA_MIME_TYPES,
            ArrayList(payload["mimeTypes"] as List<String>),
        )
    }

    /// 读回跳板转发的载荷；不是转发来的（或全不可信）返回 null。
    ///
    /// **必须校验**：这些 extras 走的是 exported 组件，任何应用都能伪造。不校验的话，
    /// 别的应用可以让我们把任意私有文件当成"分享内容"读出并上传到服务端 ——
    /// 因此只接受本应用缓存目录下、带 [PREFIX] 前缀、且确实存在的文件。
    fun readPayload(context: Context, intent: Intent): Map<String, Any?>? {
        val paths = intent.getStringArrayListExtra(EXTRA_PATHS) ?: return null
        if (paths.isEmpty()) return null
        val names = intent.getStringArrayListExtra(EXTRA_NAMES).orEmpty()
        val mimeTypes = intent.getStringArrayListExtra(EXTRA_MIME_TYPES).orEmpty()

        val trusted = paths.filter { isTrustedPath(context, it) }
        if (trusted.size != paths.size) {
            Log.w(TAG, "[share] rejected ${paths.size - trusted.size} untrusted path(s)")
        }
        if (trusted.isEmpty()) return null

        return mapOf(
            "paths" to trusted,
            "names" to trusted.mapIndexed { index, path -> names.getOrNull(index) ?: File(path).name },
            "mimeTypes" to trusted.mapIndexed { index, _ -> mimeTypes.getOrNull(index) ?: "image/*" },
        )
    }

    /// 只信任"本应用缓存目录里、[PREFIX] 前缀的真实文件"。
    private fun isTrustedPath(context: Context, path: String): Boolean {
        val file = File(path)
        return file.isFile && file.parentFile == context.cacheDir && file.name.startsWith(PREFIX)
    }

    /// 记下"复制失败、待主界面重试"的 URI。
    ///
    /// 为什么用**字符串**而不是 `EXTRA_STREAM` + `FLAG_GRANT_READ_URI_PERMISSION`：
    /// 后者会让系统在校验"能否把该 URI 的授权继续传递下去"时，发现我们并不持有可转授的
    /// 权限，直接抛 `SecurityException` 把进程打崩（已在真机上复现：
    /// `UriGrantsManagerService.checkGrantUriPermissionFromIntentUnlocked`）。
    /// 字符串 extra 不参与任何授权传递，主界面拿到后再自行申请媒体权限重试。
    fun writeRetryUris(intent: Intent, uris: List<Uri>) {
        intent.putStringArrayListExtra(EXTRA_RETRY_URIS, ArrayList(uris.map { it.toString() }))
    }

    /// 读回待重试的 URI；没有则返回空列表。
    fun readRetryUris(intent: Intent): List<Uri> =
        intent.getStringArrayListExtra(EXTRA_RETRY_URIS).orEmpty().mapNotNull { raw ->
            runCatching { Uri.parse(raw) }.getOrNull()
        }
}
