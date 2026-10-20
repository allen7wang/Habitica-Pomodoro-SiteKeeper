// Harness stub: com.habitica.pomodoro.service.{PomodoroTimerService, BlockReminderReceiver}.
// Signatures mirror the real classes for the call sites inside PomodoroViewModel.
package com.habitica.pomodoro.service

import android.content.Context
import com.habitica.pomodoro.data.UserSettings
import com.habitica.pomodoro.engine.PomodoroViewModel

object PomodoroTimerService {
    const val ACTION_START = "com.habitica.pomodoro.START"
    const val ACTION_PAUSE = "com.habitica.pomodoro.PAUSE"
    const val ACTION_RESUME = "com.habitica.pomodoro.RESUME"
    const val ACTION_UPDATE_PAUSED = "com.habitica.pomodoro.UPDATE_PAUSED"
    const val ACTION_STOP = "com.habitica.pomodoro.STOP"

    val calls = mutableListOf<String>()
    /** When false, start() reports failure so the FGS-denied message path can be tested. */
    var startSucceeds = true

    fun reset() { calls.clear(); startSucceeds = true }

    fun start(context: Context, phase: PomodoroViewModel.Phase, endsAt: Long, sessionId: String): Boolean {
        calls += "start:${phase.name}:$sessionId"
        return startSucceeds
    }

    fun updatePaused(context: Context, seconds: Int, id: String) { calls += "updatePaused:$seconds:$id" }
    fun stop(context: Context) { calls += "stop" }
    fun refreshAudio(context: Context) { calls += "refreshAudio" }
    fun endSignal(context: Context, title: String, body: String, sound: String, volume: Double) {
        calls += "endSignal:$title"
    }
    fun alert(context: Context, title: String, body: String, id: Int, silent: Boolean = false) {
        calls += "alert:$title:$id"
    }
}

object BlockReminderReceiver {
    val calls = mutableListOf<String>()
    fun reset() { calls.clear() }
    fun schedule(context: Context, settings: UserSettings) { calls += "schedule" }
}
