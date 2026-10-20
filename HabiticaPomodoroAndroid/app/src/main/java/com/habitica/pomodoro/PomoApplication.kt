package com.habitica.pomodoro

import android.app.Application
import com.habitica.pomodoro.data.QishiLibrary
import com.habitica.pomodoro.engine.PomodoroViewModel
import org.json.JSONObject

/** One process-wide owner: Activity recreation and service deadlines use the same phase ID. */
class PomoApplication : Application() {
    val engine: PomodoroViewModel by lazy {
        PomodoroViewModel(this).also { vm ->
            // 栖时场景库：随包 assets 里只有 JSON（音频从公开站点流式）；读取失败按空库处理，
            // 由 VM 在专注开始时提示"场景库不可用"。
            vm.qishiLibraryLoader = {
                runCatching {
                    assets.open(QishiLibrary.ASSET_PATH).bufferedReader().use { QishiLibrary.parse(JSONObject(it.readText())) }
                }.getOrDefault(emptyList())
            }
        }
    }
}
