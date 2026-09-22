import SwiftUI
import Combine

// MARK: - App Tab State (主窗口 Tab 选择状态，供菜单快捷键控制)
class AppTabState: ObservableObject {
    static let shared = AppTabState()

    // 0 = Pomo, 1 = Task, 2 = Habits, 3 = Dailies, 4 = Role
    @Published var selectedTab: Int = 0

    static let tabTitles = ["Pomo", "Task", "Habits", "Dailies", "Role"]
}
