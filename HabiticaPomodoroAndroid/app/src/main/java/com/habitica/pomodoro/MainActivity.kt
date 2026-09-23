package com.habitica.pomodoro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.habitica.pomodoro.engine.PomodoroViewModel
import com.habitica.pomodoro.ui.PomoScreen
import com.habitica.pomodoro.ui.RoleScreen
import com.habitica.pomodoro.ui.SettingsScreen
import com.habitica.pomodoro.ui.TaskScreen
import com.habitica.pomodoro.ui.theme.HabiticaPomodoroTheme

class MainActivity : ComponentActivity() {

    private val vm: PomodoroViewModel by viewModels()

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* 拒绝也不阻塞：计时通知仍可显示，仅提醒横幅受限 */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        requestNotificationPermissionIfNeeded()

        setContent {
            HabiticaPomodoroTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    RootTabs(vm)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 回前台按绝对结束时刻重算剩余时间；后台已结束的阶段补触发结束逻辑
        vm.resyncAfterForeground()
    }

    /** Android 13+ 需运行时授权通知；首次启动时请求一次 */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

/** 底部导航：与 iOS 端四 Tab 对齐（Pomo / Task / Role / Settings） */
@Composable
private fun RootTabs(vm: PomodoroViewModel) {
    var selected by remember { mutableIntStateOf(0) }
    val state by vm.state.collectAsStateWithLifecycle()

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selected == 0,
                    onClick = { selected = 0 },
                    icon = { Icon(Icons.Filled.Timer, contentDescription = null) },
                    label = { Text("Pomo") },
                )
                NavigationBarItem(
                    selected = selected == 1,
                    onClick = { selected = 1 },
                    icon = { Icon(Icons.Filled.Star, contentDescription = null) },
                    label = { Text("Task") },
                )
                NavigationBarItem(
                    selected = selected == 2,
                    onClick = { selected = 2 },
                    icon = { Icon(Icons.Filled.Person, contentDescription = null) },
                    label = { Text("Role") },
                )
                NavigationBarItem(
                    selected = selected == 3,
                    onClick = { selected = 3 },
                    icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                    label = { Text("设置") },
                )
            }
        },
    ) { innerPadding ->
        val modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)

        when (selected) {
            0 -> PomoScreen(vm = vm, state = state, modifier = modifier)
            1 -> TaskScreen(vm = vm, state = state, modifier = modifier)
            2 -> RoleScreen(vm = vm, state = state, modifier = modifier)
            3 -> SettingsScreen(vm = vm, state = state, modifier = modifier)
        }
    }
}
