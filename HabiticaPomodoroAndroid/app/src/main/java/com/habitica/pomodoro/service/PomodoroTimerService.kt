package com.habitica.pomodoro.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.habitica.pomodoro.MainActivity
import com.habitica.pomodoro.PomoApplication
import com.habitica.pomodoro.R
import com.habitica.pomodoro.engine.PomodoroViewModel.Phase

/** Rendering/audio only. Business deadlines enter the application's single engine. */
class PomodoroTimerService : Service() {
    private val engine get() = (application as PomoApplication).engine
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var audio: PomoAudio
    private var phase = Phase.IDLE
    private var endsAt = 0L
    private var pausedRemaining = 0
    private var sessionId = ""
    private var generation = 0
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopping = false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate(); current = this; createChannels(this)
        audio = PomoAudio(this)
        audio.onEffectFinished = { if (stopping && !audio.effectPlaying) stopEverything() }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_SESSION).orEmpty()
                if (!engine.isCurrentTimer(id)) { if (sessionId.isEmpty()) stopSelf(); return START_NOT_STICKY }
                stopping = false
                sessionId = id
                phase = runCatching { Phase.valueOf(intent.getStringExtra("phase").orEmpty()) }.getOrDefault(Phase.IDLE)
                endsAt = intent.getLongExtra("ends_at", 0); pausedRemaining = 0
                // Foreground first: Android 15 requires top app/FGS before requesting audio focus.
                startForeground(NOTIF_ID, notification())
                acquireWakeLock(); refreshAudio(); startTicker()
            }
            ACTION_UPDATE_PAUSED -> {
                val id = intent.getStringExtra(EXTRA_SESSION).orEmpty()
                if (!engine.isCurrentTimer(id)) return START_NOT_STICKY
                sessionId = id; generation++; endsAt = 0
                pausedRemaining = intent.getIntExtra("remaining", 0)
                releaseWakeLock(); audio.stopAmbient()
                try { NotificationManagerCompat.from(this).notify(NOTIF_ID, notification()) } catch (_: SecurityException) { /* Notifications denied; timer continues. */ }
            }
            ACTION_STOP -> {
                if (engine.state.value.isRunning) return START_NOT_STICKY // A queued old stop cannot cancel a new phase.
                stopping = true; generation++; endsAt = 0; pausedRemaining = 0; audio.stopAmbient(); releaseWakeLock()
                if (!audio.effectPlaying) stopEverything()
                else handler.postDelayed({ if (stopping) stopEverything() }, 15000) // Bounded tail, never an orphan FGS.
            }
        }
        return START_NOT_STICKY
    }
    fun refreshAudio() {
        val s = engine.state.value
        if (!stopping && s.isRunning && s.phase == Phase.POMODORO) audio.ambient(s.settings.ambientSound, s.settings.ambientSoundVolume)
        else audio.stopAmbient()
    }
    private fun startTicker() {
        val epoch = ++generation
        fun tick() {
            if (epoch != generation || endsAt <= 0) return
            if (System.currentTimeMillis() >= endsAt) {
                audio.stopAmbient()
                engine.onServiceDeadline(sessionId)
            } else {
                try { NotificationManagerCompat.from(this).notify(NOTIF_ID, notification()) } catch (_: SecurityException) { /* Notifications denied; timer continues. */ }
                handler.postDelayed({ tick() }, 1000)
            }
        }
        handler.post { tick() }
    }
    private fun notification(): Notification {
        val remaining = if (endsAt > 0) ((endsAt - System.currentTimeMillis() + 999) / 1000).toInt().coerceAtLeast(0) else pausedRemaining
        val title = when (phase) {
            Phase.POMODORO -> "专注中"; Phase.BREAK -> "短休息"; Phase.LONG_BREAK -> "长休息"
            Phase.BREAK_EXTENSION -> "休息延长"; else -> "番茄钟"
        }
        val running = endsAt > 0
        return NotificationCompat.Builder(this, CHANNEL_TIMER).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title).setContentText("${if (running) "" else "已暂停 · "}${"%02d:%02d".format(java.util.Locale.US, remaining / 60, remaining % 60)}")
            .setOngoing(true).setSilent(true).setOnlyAlertOnce(true).setContentIntent(contentIntent(this))
            .addAction(0, if (running) "暂停" else "继续", actionIntent(if (running) ACTION_PAUSE else ACTION_RESUME, 1))
            .addAction(0, "放弃/重置", actionIntent(ACTION_STOP, 2)).build()
    }
    private fun actionIntent(action: String, code: Int) = PendingIntent.getActivity(this, code,
        Intent(this, MainActivity::class.java).apply {
            this.action = action; data = Uri.parse("pomo://timer/$sessionId/$action")
            putExtra(EXTRA_SESSION, sessionId); flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun acquireWakeLock() {
        // A continuous focus -> break -> grace chain needs a fresh bounded timeout for each deadline.
        releaseWakeLock()
        val timeout = (endsAt - System.currentTimeMillis() + 60_000L).coerceIn(1_000L, 125 * 60 * 1000L)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "habitica:pomodoro-timer").apply {
            setReferenceCounted(false); acquire(timeout)
        }
    }
    private fun releaseWakeLock() { if (wakeLock?.isHeld == true) wakeLock?.release(); wakeLock = null }
    private fun stopEverything() { generation++; handler.removeCallbacksAndMessages(null); releaseWakeLock(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    override fun onDestroy() {
        current = null; generation++; handler.removeCallbacksAndMessages(null); audio.onEffectFinished = null; audio.stopAll(); releaseWakeLock(); super.onDestroy()
    }
    companion object {
        private var current: PomodoroTimerService? = null
        private const val CHANNEL_TIMER = "pomo_timer"
        private const val CHANNEL_ALERT = "pomo_alert"
        private const val NOTIF_ID = 1001
        const val ACTION_START = "com.habitica.pomodoro.START"
        const val ACTION_PAUSE = "com.habitica.pomodoro.PAUSE"
        const val ACTION_RESUME = "com.habitica.pomodoro.RESUME"
        const val ACTION_UPDATE_PAUSED = "com.habitica.pomodoro.UPDATE_PAUSED"
        const val ACTION_STOP = "com.habitica.pomodoro.STOP"
        const val EXTRA_SESSION = "timer_session"
        fun start(context: Context, phase: Phase, endsAt: Long, sessionId: String): Boolean = try {
            context.startForegroundService(Intent(context, PomodoroTimerService::class.java).setAction(ACTION_START)
                .putExtra("phase", phase.name).putExtra("ends_at", endsAt).putExtra(EXTRA_SESSION, sessionId))
            true
        } catch (_: IllegalStateException) { false } catch (_: SecurityException) { false }
        fun updatePaused(context: Context, seconds: Int, id: String) {
            // The service might be gone after process restoration; pause must not launch an unbound service.
            current?.let { context.startService(Intent(context, PomodoroTimerService::class.java).setAction(ACTION_UPDATE_PAUSED)
                .putExtra("remaining", seconds).putExtra(EXTRA_SESSION, id)) }
        }
        fun stop(context: Context) { current?.let { context.startService(Intent(context, PomodoroTimerService::class.java).setAction(ACTION_STOP)) } }
        fun refreshAudio(context: Context) { current?.refreshAudio() }
        fun endSignal(context: Context, title: String, body: String, sound: String, volume: Double) {
            alert(context, title, body, 1002, sound != "None")
            current?.let { it.audio.stopAmbient(); it.audio.effect(sound, volume) }
        }
        private fun contentIntent(context: Context) = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun alert(context: Context, title: String, body: String, id: Int, silent: Boolean = false) {
            createChannels(context)
            val n = NotificationCompat.Builder(context, CHANNEL_ALERT).setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH).setAutoCancel(true).setSilent(silent).setContentIntent(contentIntent(context)).build()
            try { NotificationManagerCompat.from(context).notify(id, n) } catch (_: SecurityException) { /* No permission: do not crash a receiver. */ }
        }
        private fun createChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL_TIMER, "计时进度", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ALERT, "阶段与时间块提醒", NotificationManager.IMPORTANCE_HIGH))
        }
    }
}
