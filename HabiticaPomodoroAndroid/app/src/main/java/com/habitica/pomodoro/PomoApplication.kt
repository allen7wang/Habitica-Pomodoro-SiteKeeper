package com.habitica.pomodoro

import android.app.Application
import com.habitica.pomodoro.engine.PomodoroViewModel

/** One process-wide owner: Activity recreation and service deadlines use the same phase ID. */
class PomoApplication : Application() {
    val engine: PomodoroViewModel by lazy { PomodoroViewModel(this) }
}
