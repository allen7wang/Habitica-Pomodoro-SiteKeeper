import SwiftUI
import Combine

// MARK: - App Tab State (主窗口 Tab 选择状态，供菜单快捷键控制)
class AppTabState: ObservableObject {
    static let shared = AppTabState()

    @Published var selectedTab: Int = 0
}

#if os(macOS)
enum MacAppTab: Int, CaseIterable, Identifiable {
    case focus, tasks, habits, dailies, role, review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .focus: return "专注"
        case .tasks: return "任务"
        case .habits: return "习惯"
        case .dailies: return "每日"
        case .role: return "角色"
        case .review: return "复盘"
        }
    }

    var menuTitle: String {
        switch self {
        case .focus: return "Pomo"
        case .tasks: return "Task"
        case .habits: return "Habits"
        case .dailies: return "Dailies"
        case .role: return "Role"
        case .review: return "专注复盘"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .tasks: return "checklist"
        case .habits: return "sparkles"
        case .dailies: return "calendar"
        case .role: return "person.crop.circle"
        case .review: return "chart.bar.xaxis"
        }
    }
}
#endif
