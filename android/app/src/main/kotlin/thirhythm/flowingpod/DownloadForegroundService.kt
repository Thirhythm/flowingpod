package thirhythm.flowingpod

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Background audio downloads with a progress notification.
 *
 * The service owns the transfer, so it keeps running while the app is in the
 * background or its UI is closed. Requests are handled one at a time, which
 * keeps the single foreground notification meaningful.
 */
class DownloadForegroundService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val queue = ArrayDeque<DownloadTask>()
    private val handler = Handler(Looper.getMainLooper())
    private val notificationIds = AtomicInteger(1000)
    private var active: DownloadTask? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let { queue.add(DownloadTask.from(it, notificationIds.incrementAndGet())) }
        startNextIfIdle()
        // Redeliver the queued download if the process is recycled mid-transfer.
        return START_REDELIVER_INTENT
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startNextIfIdle() {
        val task: DownloadTask
        synchronized(this) {
            if (active != null) return
            task = synchronized(queue) { queue.pollFirst() } ?: run {
                stopSelf()
                return
            }
            active = task
        }
        startForeground(task.notificationId, progressNotification(task, 0, -1))
        executor.execute { runTask(task) }
    }

    private fun runTask(task: DownloadTask) {
        val temporary = File(task.destination.path + ".part")
        var failure: String? = null
        var completed = false
        for (url in task.urls) {
            try {
                transfer(url, task, temporary)
                completed = true
                break
            } catch (error: Exception) {
                failure = error.message ?: error.javaClass.simpleName
            }
            temporary.delete()
        }

        if (completed) {
            finish(task, completionNotification(task))
        } else {
            temporary.delete()
            finish(task, failureNotification(task, failure))
        }
    }

    private fun transfer(url: String, task: DownloadTask, temporary: File) {
        var connection: HttpURLConnection? = null
        try {
            connection = open(url, task.headers)
            val code = connection.responseCode
            if (code !in 200..299) throw IOException("HTTP $code")
            val total = connection.contentLength.toLong()
            FileOutputStream(temporary).use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var received = 0L
                    var lastUpdate = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        received += read
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastUpdate >= 400) {
                            notify(
                                task.notificationId,
                                progressNotification(task, received, total),
                            )
                            lastUpdate = now
                        }
                    }
                }
            }
            if (temporary.length() <= 0) throw IOException("下载内容为空")

            task.destination.parentFile?.mkdirs()
            if (task.destination.exists() && !task.destination.delete()) {
                throw IOException("无法覆盖已有文件")
            }
            if (!temporary.renameTo(task.destination)) {
                temporary.copyTo(task.destination, overwrite = true)
            }
            temporary.delete()
        } finally {
            connection?.disconnect()
        }
    }

    /** Opens [url] and follows redirects, including protocol changes. */
    private fun open(url: String, headers: Map<String, String>): HttpURLConnection {
        var current = URL(url)
        repeat(MAX_REDIRECTS) {
            val connection = (current.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                instanceFollowRedirects = false
                for ((name, value) in headers) setRequestProperty(name, value)
            }
            val code = connection.responseCode
            if (code == HttpURLConnection.HTTP_MOVED_PERM ||
                code == HttpURLConnection.HTTP_MOVED_TEMP ||
                code == HttpURLConnection.HTTP_SEE_OTHER ||
                code == HTTP_TEMP_REDIRECT ||
                code == HTTP_PERMANENT_REDIRECT
            ) {
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank()) throw IOException("重定向缺少地址")
                current = try {
                    current.toURI().resolve(location).toURL()
                } catch (error: Exception) {
                    throw IOException("无法解析下载地址", error)
                }
            } else {
                return connection
            }
        }
        throw IOException("重定向次数过多")
    }

    private fun finish(task: DownloadTask, notification: Notification) {
        handler.post {
            notificationManager().notify(task.notificationId, notification)
            synchronized(this) { active = null }
            val hasNext = synchronized(queue) { queue.isNotEmpty() }
            if (hasNext) {
                startNextIfIdle()
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_DETACH)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(false)
                }
                stopSelf()
            }
        }
    }

    private fun notify(id: Int, notification: Notification) {
        notificationManager().notify(id, notification)
    }

    private fun progressNotification(
        task: DownloadTask,
        received: Long,
        total: Long,
    ): Notification {
        val known = total > 0
        val percent = if (known) ((received * 100) / total).toInt().coerceIn(0, 100) else 0
        val detail = if (known) {
            "正在下载 · $percent% · ${megabytes(received)} / ${megabytes(total)}"
        } else {
            "正在下载 · 已下载 ${megabytes(received)}"
        }
        return baseBuilder(task)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(task.title)
            .setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(detail))
            .setProgress(100, percent, !known)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun completionNotification(task: DownloadTask): Notification =
        baseBuilder(task)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(task.title)
            .setContentText("下载完成 · ${task.destination.name}")
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .build()

    private fun failureNotification(task: DownloadTask, reason: String?): Notification {
        val detail = "下载失败${if (reason.isNullOrBlank()) "" else "：$reason"}"
        return baseBuilder(task)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(task.title)
            .setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(detail))
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .build()
    }

    private fun baseBuilder(task: DownloadTask): Notification.Builder {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(
                Notification.FOREGROUND_SERVICE_IMMEDIATE,
            )
        }
        return builder
            .setContentIntent(openAppIntent())
            .setSubText(task.subtitle.takeIf { it.isNotBlank() })
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "音乐下载",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示音乐下载进度"
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun megabytes(bytes: Long): String =
        String.format(Locale.ROOT, "%.1f MB", bytes / (1024.0 * 1024.0))

    companion object {
        private const val CHANNEL_ID = "thirhythm.flowingpod.downloads"
        private const val MAX_REDIRECTS = 5
        private const val HTTP_TEMP_REDIRECT = 307
        private const val HTTP_PERMANENT_REDIRECT = 308

        const val EXTRA_URLS = "urls"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_PATH = "path"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
    }
}

private class DownloadTask(
    val urls: List<String>,
    val headers: Map<String, String>,
    val destination: File,
    val title: String,
    val subtitle: String,
    val notificationId: Int,
) {
    companion object {
        fun from(intent: Intent, notificationId: Int): DownloadTask {
            @Suppress("DEPRECATION")
            val rawHeaders = intent.getSerializableExtra(
                DownloadForegroundService.EXTRA_HEADERS,
            ) as? Map<*, *>
            val headers = mutableMapOf<String, String>()
            rawHeaders?.forEach { (key, value) ->
                if (key is String && value is String) headers[key] = value
            }
            return DownloadTask(
                urls = intent.getStringArrayListExtra(
                    DownloadForegroundService.EXTRA_URLS,
                ).orEmpty(),
                headers = headers,
                destination = File(
                    intent.getStringExtra(DownloadForegroundService.EXTRA_PATH).orEmpty(),
                ),
                title = intent.getStringExtra(
                    DownloadForegroundService.EXTRA_TITLE,
                ).orEmpty(),
                subtitle = intent.getStringExtra(
                    DownloadForegroundService.EXTRA_SUBTITLE,
                ).orEmpty(),
                notificationId = notificationId,
            )
        }
    }
}
