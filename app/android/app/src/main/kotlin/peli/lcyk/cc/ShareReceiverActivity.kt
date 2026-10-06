package peli.lcyk.cc

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

/// 分享入口：**不可见跳板**。
///
/// ## 为什么不能让主界面直接当分享目标
///
/// 分享方（MIUI 图库等）启动目标 Activity 时**不带 `FLAG_ACTIVITY_NEW_TASK`**，而
/// `launchMode` 的"独占任务"语义只在"任务启动"路径上生效 —— 于是被启动的 Activity
/// 会被并进**分享方自己的任务**。主界面若被这样并进去，用户会在最近任务里看到第二个
/// 「Peli」（图标还是分享方的），并且同时存在两个主界面实例。
///
/// 这个 flag 在发送方手里，应用侧改不了；能做的是**自己再转发一次**（带 `NEW_TASK`）。
///
/// ## 这个跳板做了什么
///
/// 1. 趁对方的 URI 授权还有效，把分享内容复制到应用私有缓存 —— 纯 Kotlin，
///    **不创建窗口、不创建 Flutter 引擎**，所以既无闪烁也无浪费；
/// 2. 用 `NEW_TASK` 拉起 [MainActivity]：已有实例走 `onNewIntent`（任务被带到前台），
///    没有实例则冷启动到本应用自己的任务；
/// 3. 立即 `finish()`，把对方的任务恢复成"只有它自己"，最近任务里不会留下多余条目。
///
/// 复制失败（例如缺 `READ_MEDIA_IMAGES`）时**不在这里申请权限** —— 跳板马上结束，
/// 弹不出对话框；此时把原始 Intent 一并转发，由 [MainActivity] 走它原有的
/// "申请权限 → 重试"流程，任务归属同样是正确的。
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val source = intent
        val uris = ShareFiles.streamUris(source)
        val copied = ShareFiles.copyAll(this, source, uris)
        Log.i(TAG, "[share] trampoline: ${uris.size} uri(s) -> cached ${copied.size}")

        // 保留原始 action/type/EXTRA_STREAM：复制失败时的兜底路径要靠它。
        val forward = Intent(source).apply {
            setClass(this@ShareReceiverActivity, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (copied.isNotEmpty()) {
            ShareFiles.writePayload(forward, ShareFiles.payload(copied))
        }
        startActivity(forward)
        finish()
    }

    private companion object {
        const val TAG = "MemosShare"
    }
}
