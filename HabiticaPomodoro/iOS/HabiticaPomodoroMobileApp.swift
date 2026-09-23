import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - iOS App Entry
@main
struct HabiticaPomodoroMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

// MARK: - App Delegate (通知权限 + 音频会话 + 前台重同步)
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 必须最先执行：解析 iCloud Drive 文件夹授权 bookmark，
        // 保证之后任何 Manager 首次初始化时 PomodoroDataDir.url 已指向 iCloud 目录
        _ = ICloudFolderGrant.shared
        // DEBUG 构建支持 -grantFolder <path> 启动参数授权（自动化验证用）
        ICloudFolderGrant.shared.handleLaunchArguments()

        // 通知 delegate（前台也展示横幅）；权限在首次启动番茄时再请求（懒加载，避免启动即弹窗）
        UNUserNotificationCenter.current().delegate = self

        // 音频会话：允许与静音开关共存（响铃模式仍出声），后台可播放环境音
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        // 初始化 Habitica 任务与今日计数
        Task { await PomodoroEngine.shared.initHabiticaTasks() }
        PomodoroEngine.shared.loadTodayCount()

        // 回前台重同步：计时器校正 + 检测 iCloud 是否同步来了 Mac 端的新数据
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            PomodoroEngine.shared.resyncAfterForeground()
            PomodoroEngine.shared.loadTodayCount()
            ICloudFolderGrant.shared.syncFromCloudIfNeeded()
        }
        return true
    }

    // 应用在前台时也弹通知横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Root Tab View (底部标签栏)
struct RootTabView: View {
    @StateObject private var tabState = AppTabState.shared

    var body: some View {
        TabView(selection: $tabState.selectedTab) {
            MobilePomoView()
                .tabItem { Label("Pomo", systemImage: "timer") }
                .tag(0)

            TopThreeView()
                .tabItem { Label("Task", systemImage: "star.fill") }
                .tag(1)

            HabiticaProfileView()
                .tabItem { Label("Role", systemImage: "person.crop.circle") }
                .tag(4)

            MobileSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(9)
        }
    }
}
