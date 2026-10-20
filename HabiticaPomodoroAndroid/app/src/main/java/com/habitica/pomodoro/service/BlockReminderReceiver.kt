package com.habitica.pomodoro.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.habitica.pomodoro.data.LocalStore
import com.habitica.pomodoro.data.UserSettings
import java.util.Calendar

/** Inexact alarms need no special access. Device idle/battery policy may delay them. */
class BlockReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val settings = LocalStore(context).loadSettings()
        if (intent.action == ACTION_REMINDER && settings.enableBlockMode && settings.blockStartReminder) {
            val i = intent.getIntExtra("block", -1)
            val range = settings.blockTimeRanges.getOrNull(i)
            // Date/settings changes invalidate old reminders instead of emitting obsolete alerts.
            if (i in 0 until settings.blockCount && range != null && intent.getStringExtra("signature") == signature(settings, i)) {
                PomodoroTimerService.alert(context, "时间块 B${i + 1} 即将开始", "${settings.blockReminderMinutes} 分钟后 · ${range.displayString}" +
                    settings.blockGoals.getOrNull(i).orEmpty().takeIf { it.isNotBlank() }?.let { "\n目标：$it" }.orEmpty(), 2000 + i)
            }
        }
        schedule(context, settings)
    }
    companion object {
        private const val ACTION_REMINDER = "com.habitica.pomodoro.BLOCK_REMINDER"
        private fun signature(s: UserSettings, i: Int) = "${s.blockTimeRanges.getOrNull(i)}|${s.blockReminderMinutes}|${s.blockGoals.getOrNull(i)}"
        fun schedule(context: Context, settings: UserSettings) {
            val manager = context.getSystemService(AlarmManager::class.java)
            for (i in 0 until 24) {
                val intent = Intent(context, BlockReminderReceiver::class.java).setAction(ACTION_REMINDER)
                    .putExtra("block", i).putExtra("signature", signature(settings, i))
                val pending = PendingIntent.getBroadcast(context, 2000 + i, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                manager.cancel(pending)
                if (!settings.enableBlockMode || !settings.blockStartReminder || i >= settings.blockCount) continue
                val range = settings.blockTimeRanges.getOrNull(i) ?: continue
                val minute = (range.startMinutes - settings.blockReminderMinutes).mod(1440)
                val time = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, minute / 60); set(Calendar.MINUTE, minute % 60); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
                }
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time.timeInMillis, pending)
            }
        }
    }
}
