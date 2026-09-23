package com.habitica.pomodoro.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.habitica.pomodoro.MainActivity
import com.habitica.pomodoro.R
import com.habitica.pomodoro.engine.PomodoroViewModel.Phase

/**
 * 计时前台服务。
 *
 * 为什么需要：Android 8+ 会冻结后台进程，纯 ViewModel 协程无法保证计时准确，
 * 进程被杀后用户也毫无感知。前台服务 + 常驻通知让计时可见可控，
 * 并在阶段结束时发提醒通知（对应 iOS 端预排本地通知的做法）。
 *
 * 计时基于**绝对结束时刻**（phaseEndsAt）而非循环递减，
 * 因此即使通知刷新线程被系统短暂限制，显示的剩余时间依然正确。
 *
 * 通知栏的暂停/继续/结束按钮通过 PendingIntent.getService 直接回到本服务，
 * 不额外引入 BroadcastReceiver，避免双重注册与转发歧义。
 */
class PomodoroTimerService : Service() {

    private var phase: Phase = Phase.IDLE
    private var phaseEndsAt: Long = 0L
    private var pausedRemainingSeconds: Int = 0
    private var wakeLock: PowerManager.WakeLock? = null

    @Volatile
    private var tickerRunning = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                phase = runCatching {
                    Phase.valueOf(intent.getStringExtra(EXTRA_PHASE) ?: Phase.POMODORO.name)
                }.getOrDefault(Phase.POMODORO)
                phaseEndsAt = intent.getLongExtra(EXTRA_ENDS_AT, 0L)
                pausedRemainingSeconds = 0
                acquireWakeLock()
                startForeground(NOTIF_ID, buildNotification())
                startTicker()
            }
            ACTION_PAUSE -> {
                pausedRemainingSeconds = remainingNow()
                phaseEndsAt = 0L
                releaseWakeLock()
                updateNotification()
            }
            ACTION_RESUME -> {
                if (pausedRemainingSeconds > 0) {
                    phaseEndsAt = System.currentTimeMillis() + pausedRemainingSeconds * 1000L
                    acquireWakeLock()
                    startTicker()
                    updateNotification()
                }
            }
            ACTION_UPDATE_PAUSED -> {
                pausedRemainingSeconds = intent.getIntExtra(EXTRA_REMAINING, pausedRemainingSeconds)
                phaseEndsAt = 0L
                releaseWakeLock()
                updateNotification()
            }
            ACTION_STOP -> stopEverything()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    // MARK: - 计时

    private fun remainingNow(): Int {
        if (phaseEndsAt <= 0L) return pausedRemainingSeconds
        return ((phaseEndsAt - System.currentTimeMillis()) / 1000L).toInt().coerceAtLeast(0)
    }

    /** 每秒刷新通知；到 0 时发阶段结束提醒。同一时刻只允许一个刷新线程 */
    private fun startTicker() {
        if (tickerRunning) return
        tickerRunning = true
        Thread {
            try {
                while (phaseEndsAt > 0L) {
                    val remaining = remainingNow()
                    updateNotification()
                    if (remaining <= 0) {
                        notifyPhaseEnd()
                        break
                    }
                    Thread.sleep(1000)
                }
            } catch (_: InterruptedException) {
                // 服务被销毁，正常退出
            } finally {
                tickerRunning = false
            }
        }.apply { isDaemon = true; name = "pomo-ticker"; start() }
    }

    private fun notifyPhaseEnd() {
        val title = when (phase) {
            Phase.POMODORO -> "番茄结束 🍅"
            Phase.BREAK -> "休息结束"
            Phase.LONG_BREAK -> "长休息结束"
            else -> "计时结束"
        }
        val body = when (phase) {
            Phase.POMODORO -> "该休息一下了，点开应用开始休息"
            else -> "回到专注，开始下一个番茄吧"
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentIntent())
            .build()
        runCatching { NotificationManagerCompat.from(this).notify(ALERT_NOTIF_ID, notif) }
        stopEverything()
    }

    private fun stopEverything() {
        phaseEndsAt = 0L
        pausedRemainingSeconds = 0
        releaseWakeLock()
        runCatching {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    // MARK: - 通知

    private fun buildNotification(): Notification {
        val remaining = remainingNow()
        val running = phaseEndsAt > 0L
        val title = phaseTitle()
        val text = if (running) "$title · ${format(remaining)}" else "$title · 已暂停 ${format(remaining)}"

        return NotificationCompat.Builder(this, CHANNEL_TIMER)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent())
            .addAction(
                0,
                if (running) "暂停" else "继续",
                serviceIntent(if (running) ACTION_PAUSE else ACTION_RESUME, requestCode = 1),
            )
            .addAction(0, "结束", serviceIntent(ACTION_STOP, requestCode = 2))
            .build()
    }

    private fun phaseTitle(): String = when (phase) {
        Phase.POMODORO -> "专注中"
        Phase.BREAK -> "休息中"
        Phase.LONG_BREAK -> "长休息中"
        else -> "番茄钟"
    }

    private fun updateNotification() {
        if (phaseEndsAt <= 0L && pausedRemainingSeconds <= 0) return
        runCatching { NotificationManagerCompat.from(this).notify(NOTIF_ID, buildNotification()) }
    }

    private fun format(totalSeconds: Int): String {
        val m = totalSeconds / 60
        val s = totalSeconds % 60
        return String.format(java.util.Locale.US, "%02d:%02d", m, s)
    }

    private fun contentIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            this, requestCode,
            Intent(this, PomodoroTimerService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    // MARK: - 通知渠道

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_TIMER, "计时进度", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "常驻显示剩余时间"; setShowBadge(false) },
            )
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ALERT, "阶段结束提醒", NotificationManager.IMPORTANCE_HIGH)
                    .apply { description = "番茄/休息结束时提醒" },
            )
        }
    }

    // MARK: - WakeLock（锁屏后计时不被冻结）

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        runCatching {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "habitica:pomodoro-timer")
                .apply { setReferenceCounted(false); acquire(MAX_WAKELOCK_MS) }
        }
    }

    private fun releaseWakeLock() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
        wakeLock = null
    }

    companion object {
        private const val CHANNEL_TIMER = "pomo_timer"
        private const val CHANNEL_ALERT = "pomo_alert"
        private const val NOTIF_ID = 1001
        private const val ALERT_NOTIF_ID = 1002

        // WakeLock 上限 2 小时，防止异常情况下长期持有
        private const val MAX_WAKELOCK_MS = 2 * 60 * 60 * 1000L

        const val ACTION_START = "com.habitica.pomodoro.START"
        const val ACTION_PAUSE = "com.habitica.pomodoro.PAUSE"
        const val ACTION_RESUME = "com.habitica.pomodoro.RESUME"
        const val ACTION_UPDATE_PAUSED = "com.habitica.pomodoro.UPDATE_PAUSED"
        const val ACTION_STOP = "com.habitica.pomodoro.STOP"

        private const val EXTRA_PHASE = "phase"
        private const val EXTRA_ENDS_AT = "ends_at"
        private const val EXTRA_REMAINING = "remaining"

        /** 番茄计分用的 Habitica habit id（ViewModel 初始化时填入） */
        @Volatile
        var habitTaskId: String? = null

        fun start(context: Context, phase: Phase, endsAt: Long) {
            context.startForegroundService(
                Intent(context, PomodoroTimerService::class.java).apply {
                    action = ACTION_START
                    putExtra(EXTRA_PHASE, phase.name)
                    putExtra(EXTRA_ENDS_AT, endsAt)
                },
            )
        }

        fun updatePaused(context: Context, remainingSeconds: Int) {
            runCatching {
                context.startService(
                    Intent(context, PomodoroTimerService::class.java).apply {
                        action = ACTION_UPDATE_PAUSED
                        putExtra(EXTRA_REMAINING, remainingSeconds)
                    },
                )
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, PomodoroTimerService::class.java).setAction(ACTION_STOP),
                )
            }
        }
    }
}
