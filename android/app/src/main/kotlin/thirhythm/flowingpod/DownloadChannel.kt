package thirhythm.flowingpod

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.HashMap

/**
 * Starts background downloads and manages the notification permission their
 * progress display needs.
 */
class DownloadChannel(private val activity: Activity) {
    private var notificationResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestNotificationAccess" -> requestNotificationAccess(result)
            "enqueueDownload" -> enqueueDownload(call, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val pending = notificationResult ?: return
        notificationResult = null
        pending.success(hasNotificationAccess())
    }

    private fun hasNotificationAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestNotificationAccess(result: MethodChannel.Result) {
        if (hasNotificationAccess()) {
            result.success(true)
            return
        }
        if (notificationResult != null) {
            result.error("busy", "Another notification permission request is running", null)
            return
        }
        notificationResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    private fun enqueueDownload(call: MethodCall, result: MethodChannel.Result) {
        val urls = (call.argument<Any>("urls") as? List<*>)
            ?.mapNotNull { (it as? String)?.takeIf { value -> value.isNotBlank() } }
            .orEmpty()
        val headers = HashMap<String, String>()
        (call.argument<Any>("headers") as? Map<*, *>)?.forEach { (key, value) ->
            if (key is String && value is String) headers[key] = value
        }
        val filePath = call.argument<String>("filePath")?.takeIf { it.isNotBlank() }
        val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: "音乐下载"
        val subtitle = call.argument<String>("subtitle").orEmpty()

        if (urls.isEmpty() || filePath == null) {
            result.error("invalid_args", "缺少下载地址或保存位置", null)
            return
        }

        val destination = File(filePath)
        val parent = destination.parentFile
        if (parent == null || (!parent.exists() && !parent.mkdirs())) {
            result.error("io", "无法创建下载文件夹", null)
            return
        }

        val intent = Intent(activity, DownloadForegroundService::class.java).apply {
            putStringArrayListExtra(DownloadForegroundService.EXTRA_URLS, ArrayList(urls))
            putExtra(DownloadForegroundService.EXTRA_HEADERS, headers)
            putExtra(DownloadForegroundService.EXTRA_PATH, destination.absolutePath)
            putExtra(DownloadForegroundService.EXTRA_TITLE, title)
            putExtra(DownloadForegroundService.EXTRA_SUBTITLE, subtitle)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("service", error.message, null)
        }
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 5212
    }
}
