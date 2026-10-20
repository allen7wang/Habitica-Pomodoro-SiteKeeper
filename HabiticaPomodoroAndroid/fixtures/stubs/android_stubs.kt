// Harness stub: minimal Android platform surface used by the compiled
// production set (LocalStore + PomodoroViewModel). No real Android runtime.
package android.content

import java.io.File

abstract class Context {
    /** Real Android exposes getFilesDir(); Kotlin synthetic property at the call site. */
    abstract val filesDir: File

    private val prefs = mutableMapOf<String, SharedPreferences>()

    open fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        prefs.getOrPut(name) { SharedPreferences() }
}

class SharedPreferences {
    private val values = mutableMapOf<String, String?>()

    fun getString(key: String, defValue: String?): String? =
        if (values.containsKey(key)) values[key] else defValue

    fun edit(): Editor = Editor()

    inner class Editor {
        fun putString(key: String, value: String?): Editor = apply { values[key] = value }
        fun apply() {}
        fun commit(): Boolean { return true }
    }
}
