import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Main App
@main
struct HabiticaPomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a menu-bar style window via AppDelegate.
        // SwiftUI Settings scene for the settings window.
        Settings {
            SettingsView()
        }
        .commands {
            // Pomodoro 菜单: ⌘⇧P 启动/暂停
            CommandMenu("Pomodoro") {
                Button("Start/Pause Pomodoro") {
                    PomodoroEngine.shared.togglePomodoro()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            // View 菜单: ⌘1-5 切换 Tab
            CommandMenu("Go") {
                ForEach(Array(AppTabState.tabTitles.enumerated()), id: \.offset) { index, title in
                    Button(title) {
                        AppTabState.shared.selectedTab = index
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.ensureTimerWindowVisible()
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
        }
    }
}

// MARK: - App Delegate (status bar + window management)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var timerWindow: NSWindow?
    var settingsWindow: NSWindow?
    var badgeTimer: Timer?
    var badgeDisplayMode: BadgeDisplayMode = .timer

    enum BadgeDisplayMode {
        case timer
        case count
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Setup status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // Start with icon
            if let icon = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Pomodoro") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "🍅"
            }
            button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            button.action = #selector(toggleTimerWindow)
            button.target = self
        }

        // Register for badge update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBadgeUpdate),
            name: .badgeUpdate,
            object: nil
        )

        // Start habitica sync
        Task { await PomodoroEngine.shared.initHabiticaTasks() }
        PomodoroEngine.shared.loadTodayCount()
        PomodoroFileChanges.shared.startMonitoring()

        // Setup global hotkey via Carbon (Alt+Shift+P)
        HotKeyManager.shared.register()

        // Start badge alternating display
        startBadgeAlternating()

        // Start block notification timer
        BlockNotificationManager.shared.startReminderTimer(settings: SettingsManager.shared.settings)

        // Start with timer window visible
        showTimerWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PomodoroFileChanges.shared.syncFromDiskIfNeeded()
        PomodoroEngine.shared.resyncAfterForeground()
        BlockNotificationManager.shared.startReminderTimer(settings: SettingsManager.shared.settings)
    }

    // 供快捷键使用：确保主窗口可见
    func ensureTimerWindowVisible() {
        if timerWindow?.isVisible != true {
            showTimerWindow()
        } else {
            timerWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func handleBadgeUpdate() {
        updateBadge()
    }

    @objc func toggleTimerWindow() {
        if timerWindow?.isVisible == true {
            timerWindow?.orderOut(nil)
        } else {
            showTimerWindow()
        }
    }

    func showTimerWindow() {
        if timerWindow == nil {
            let contentView = TimerView()
            let hostingController = NSHostingController(rootView: contentView)
            timerWindow = NSWindow(contentViewController: hostingController)
            timerWindow?.title = "Habitica Pomodoro"
            timerWindow?.styleMask = [.titled, .closable, .miniaturizable]
            timerWindow?.setFrameAutosaveName("TimerWindowV7")
            timerWindow?.setContentSize(NSSize(width: 470, height: 820))
        }
        timerWindow?.center()
        timerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Alternate badge display between timer and count
    private func startBadgeAlternating() {
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.badgeDisplayMode = self.badgeDisplayMode == .timer ? .count : .timer
            self.updateBadge()
        }
    }

    // Update badge text and color
    private func updateBadge() {
        guard let button = statusItem?.button else { return }

        let engine = PomodoroEngine.shared

        if !engine.isRunning {
            // Show icon when not running
            if let icon = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Pomodoro") {
                icon.isTemplate = true
                button.image = icon
            } else {
                // Fallback: use text
                button.title = "🍅"
                button.image = nil
            }
            return
        }

        // Clear icon when running, show text
        button.image = nil

        let settings = SettingsManager.shared.settings

        if badgeDisplayMode == .timer {
            // Show countdown
            button.title = engine.timerString
        } else {
            // Show progress based on mode
            if settings.enableBlockMode {
                // Block mode: show current block progress (based on time)
                BlockProgressManager.shared.updateBlockIndexFromTime(settings: settings)
                let (completed, total) = BlockProgressManager.shared.getCurrentBlockCompletion(settings: settings)
                let bp = BlockProgressManager.shared.blockProgress
                // 番茄进行中时，展示"正在进行的第几个"（completed + 1）
                let inProgress = engine.isRunning && engine.phase == .pomodoro
                let display = min(inProgress ? completed + 1 : completed, total)
                button.title = "B\(bp.currentBlockIndex + 1):\(display)/\(total)"
            } else {
                // Regular mode: show pomo set progress
                button.title = "\(engine.pomoSetCounter)/\(engine.settings.pomoSetNum)"
            }
        }

        // Set color based on phase
        switch engine.phase {
        case .pomodoro:
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [.foregroundColor: NSColor.systemGreen]
            )
        case .breakTime:
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [.foregroundColor: NSColor.systemBlue]
            )
        case .breakExtension:
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        default:
            button.attributedTitle = NSAttributedString(string: button.title)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Timer View (main window)
struct TimerView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var blockManager = BlockProgressManager.shared
    @ObservedObject var tabState = AppTabState.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showAbandonConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab 切换: Pomo / Task / Habits / Dailies / Profile (⌘1-5 快捷键)
            Picker("", selection: $tabState.selectedTab) {
                Text("Pomo").tag(0)
                Text("Task").tag(1)
                Text("Habits").tag(2)
                Text("Dailies").tag(3)
                Text("Role").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)

            switch tabState.selectedTab {
            case 0: pomoTab
            case 1: taskTab
            case 2: HabiticaHabitsView()
            case 3: HabiticaDailiesView()
            default: HabiticaProfileView()
            }
        }
        .frame(width: 470, height: 820)
        .background(Color(NSColor.windowBackgroundColor))
        .confirmationDialog("放弃当前番茄？时间块中的植物将记为枯萎。",
                            isPresented: $showAbandonConfirm, titleVisibility: .visible) {
            Button("放弃番茄", role: .destructive) {
                engine.pomodoroInterrupted(breakStreak: true)
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Pomo Tab（番茄钟相关）
    var pomoTab: some View {
        ScrollView {
        VStack(spacing: 12) {
            // Tomato / status circle
            ZStack {
                Circle()
                    .fill(tomatoColor)
                    .frame(width: 110, height: 110)
                    .shadow(radius: 4)

                VStack {
                    Text(engine.timerString)
                        .font(.system(.title, design: .monospaced).bold())
                        .foregroundColor(.white)

                    if engine.settings.enableBlockMode {
                        // Block mode: show current block progress (based on time)
                        CurrentBlockProgressView()
                            .environmentObject(engine)
                    } else {
                        // Regular mode progress
                        Text("\(engine.pomoSetCounter)/\(engine.settings.pomoSetNum)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .onTapGesture { engine.togglePomodoro() }
            .padding(.top, 12)

            // Today count
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("Today: \(engine.todayPomodoros) pomodoros")
                    .font(.subheadline)
            }

            // Block mode: show all blocks with progress circles
            if engine.settings.enableBlockMode {
                BlockTimeBlockView()
                    .environmentObject(engine)
                
                Divider()
                
                // 方案B: 可视化时间轴
                BlockTimelineView()
                    .frame(height: 216)
            }

            // Action buttons row
            HStack(spacing: 12) {
                if engine.phase == .pomodoro {
                    Button(action: { engine.skipToBreak() }) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help("Skip to break")
                }

                if engine.isRunning || engine.isFrozen {
                    Button(action: {
                        engine.isFrozen ? engine.unfreeze() : engine.freeze()
                    }) {
                        Image(systemName: engine.isFrozen ? "play.fill" : "pause.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(engine.isFrozen ? "Resume" : "Pause")
                }

                if engine.phase == .pomodoro {
                    Button(action: { showAbandonConfirm = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Abandon pomodoro")
                } else if engine.phase == .breakTime || engine.phase == .breakExtension {
                    Button(action: { engine.reset() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("End session")
                }
            }
            .frame(height: 24)

            // Habitica stats
            if engine.settings.connectHabitica {
                Divider()
                HStack(spacing: 16) {
                    Label("\(String(format: "%.1f", engine.habiticaMonies))", systemImage: "dollarsign.circle.fill")
                        .foregroundColor(.yellow)
                    Label("\(String(format: "%.0f", engine.habiticaExp))", systemImage: "star.fill")
                        .foregroundColor(.purple)
                    Label("\(String(format: "%.0f", engine.habiticaHp))", systemImage: "heart.fill")
                        .foregroundColor(.red)
                    Button(action: {
                        Task { await engine.refreshHabitica() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
                .font(.subheadline)
            }

            // Quick settings link
            HStack(spacing: 12) {
                Button("Settings") {
                    showSettings()
                }
                Button("History") {
                    showHistoryWindow()
                }
                Menu("休息") {
                    ForEach([1, 5, 15, 30], id: \.self) { minutes in
                        Button("\(minutes) 分钟") { engine.takeBreak(duration: minutes) }
                    }
                }
                .disabled(engine.phase != .idle || engine.isRunning || engine.isFrozen)
            }
            .font(.subheadline)

            Spacer()
        }
        .padding(24)
        }
    }

    // MARK: - Task Tab（最重要的三件事）
    var taskTab: some View {
        TopThreeView()
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
    }

    var tomatoColor: Color {
        switch engine.tomatoState {
        case .wait:      return Color(red: 0.55, green: 0.81, blue: 0.95)
        case .progress:  return Color.green
        case .freeze:    return Color(red: 0.70, green: 0.78, blue: 0.86)
        case .breakTime: return Color(red: 0.42, green: 0.58, blue: 0.84)
        case .win:      return Color.green
        case .warning:   return Color.red
        }
    }

    func showSettings() {
        if let settingsWindow = NSApp.windows.first(where: { $0.title == "Settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 550, height: 650))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func showHistoryWindow() {
        if let histWindow = NSApp.windows.first(where: { $0.title == "Pomodoro History" }) {
            histWindow.makeKeyAndOrderFront(nil)
        } else {
            let hostingController = NSHostingController(rootView: HistoryView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Pomodoro History"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 520))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var sm = SettingsManager.shared
    @ObservedObject var am = AudioManager.shared
    @ObservedObject private var blockManager = BlockProgressManager.shared
    @State private var showResetBlockConfirm = false
    @State private var showClearBlocksConfirm = false

    var body: some View {
        TabView {
            timerSettingsTab.tabItem { Label("Timer", systemImage: "timer") }
            blockSettingsTab.tabItem { Label("Blocks", systemImage: "square.grid.3x3") }
            habiticaSettingsTab.tabItem { Label("Habitica", systemImage: "link") }
            dataSettingsTab.tabItem { Label("Data", systemImage: "doc") }
        }
        .frame(width: 530, height: 630)
        .onDisappear { am.stopPreview() }
        .confirmationDialog("重置当前块的完成数？历史种植记录保留。",
                            isPresented: $showResetBlockConfirm, titleVisibility: .visible) {
            Button("重置当前块", role: .destructive) {
                blockManager.resetCurrentBlockProgress(settings: sm.settings)
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("清空全部时间块及植物历史？此操作不可撤销。",
                            isPresented: $showClearBlocksConfirm, titleVisibility: .visible) {
            Button("清空时间块历史", role: .destructive) { blockManager.clearHistory() }
            Button("取消", role: .cancel) {}
        }
    }

    var timerSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    Text("Pomodoro Settings").font(.headline)
                    stepperRow("Pomodoro duration", value: $sm.settings.pomoDurationMins, range: 1...120, suffix: "min")
                    stepperRow("Short break", value: $sm.settings.breakDuration, range: 1...60, suffix: "min")
                    stepperRow("Break extension", value: $sm.settings.breakExtention, range: 0...30, suffix: "min")
                    stepperRow("Long break", value: $sm.settings.longBreakDuration, range: 1...120, suffix: "min")
                    stepperRow("Long break after", value: $sm.settings.pomoSetNum, range: 1...12, suffix: "pomodoros")
                }
                Divider()
                Group {
                    Toggle("Start breaks manually", isOn: $sm.settings.manualBreak)
                    Toggle("Reset timer after break extension", isOn: $sm.settings.resetPomoAfterBreak)
                }
                Divider()
                Group {
                    Text("Sounds").font(.headline)
                    pickerRow("Pomodoro end sound", selection: $sm.settings.pomoEndSound, options: AudioManager.allSoundOptions)
                    sliderRow("Volume", value: $sm.settings.pomoEndSoundVolume)
                    pickerRow("Break end sound", selection: $sm.settings.breakEndSound, options: AudioManager.allSoundOptions)
                    sliderRow("Volume", value: $sm.settings.breakEndSoundVolume)
                    HStack {
                        Text("Ambient source")
                        Spacer()
                        Picker("", selection: $sm.settings.ambientSource) {
                            Text("Custom").tag("custom")
                            Text("Qishi Random").tag("qishi")
                        }
                        .frame(width: 140)
                    }
                    if sm.settings.ambientSource == "qishi" {
                        Text("每个番茄随机播放一个栖时场景混音（共 \(QishiSceneStore.presets.count) 个场景，暂停恢复自动延续，不与上个番茄重复）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        sliderRow("Volume", value: $sm.settings.ambientSoundVolume)
                        HStack {
                            Button("试听随机场景") {
                                if let preset = QishiSceneStore.randomPreset(excluding: nil) {
                                    am.playQishiScene(preset, volume: sm.settings.ambientSoundVolume)
                                }
                            }
                            Button("停止试听") { am.stopQishi() }
                        }
                    } else {
                        pickerRow("Ambient sound", selection: $sm.settings.ambientSound, options: AudioManager.allAmbientOptions)
                        sliderRow("Volume", value: $sm.settings.ambientSoundVolume)
                    }
                }
                Divider()
                Text("HotKey: ⌥⌘P (Option+Command+P)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    var blockSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    Toggle("Enable Block Mode", isOn: $sm.settings.enableBlockMode)

                    if sm.settings.enableBlockMode {
                        Divider()

                        Text("Block Settings").font(.headline)
                        stepperRow("Blocks per day", value: $sm.settings.blockCount, range: 1...24, suffix: "blocks")
                        stepperRow("Pomodoros per block", value: $sm.settings.blockPomoCount, range: 1...12, suffix: "pomodoros")
                        Toggle("Reward when block complete", isOn: $sm.settings.blockRewardEnabled)
                        Toggle("Sprint reminder", isOn: $sm.settings.blockSprintReminder)
                        Toggle("Remind before block starts", isOn: $sm.settings.blockStartReminder)
                        if sm.settings.blockStartReminder {
                            stepperRow("Reminder lead time", value: $sm.settings.blockReminderMinutes,
                                       range: 1...60, suffix: "min")
                        }

                        Divider()

                        Text("Block Time Ranges & Goals").font(.headline)
                        Text("Set time range and goal for each block").font(.caption).foregroundColor(.secondary)

                        ForEach(0..<sm.settings.blockCount, id: \.self) { index in
                            let blockIndex = index

                            VStack(alignment: .leading, spacing: 8) {
                                // Block header
                                Text("Block \(index + 1)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                // Time range inputs
                                HStack(spacing: 8) {
                                    Text("Time:")
                                        .font(.caption)
                                    Picker("Start Hour", selection: Binding(
                                        get: { blockIndex < sm.settings.blockTimeRanges.count ? sm.settings.blockTimeRanges[blockIndex].startHour : 4 },
                                        set: { newValue in
                                            while sm.settings.blockTimeRanges.count <= blockIndex {
                                                sm.settings.blockTimeRanges.append(BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0))
                                            }
                                            sm.settings.blockTimeRanges[blockIndex].startHour = newValue
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d:00", hour)).tag(hour)
                                        }
                                    }

                                    Picker("Start Minute", selection: Binding(
                                        get: { blockIndex < sm.settings.blockTimeRanges.count ? sm.settings.blockTimeRanges[blockIndex].startMinute : 0 },
                                        set: { newValue in
                                            while sm.settings.blockTimeRanges.count <= blockIndex {
                                                sm.settings.blockTimeRanges.append(BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0))
                                            }
                                            sm.settings.blockTimeRanges[blockIndex].startMinute = newValue
                                        }
                                    )) {
                                        ForEach(0..<60, id: \.self) { minute in
                                            Text(String(format: ":%02d", minute)).tag(minute)
                                        }
                                    }

                                    Text("-")
                                        .foregroundColor(.secondary)

                                    Picker("End Hour", selection: Binding(
                                        get: { blockIndex < sm.settings.blockTimeRanges.count ? sm.settings.blockTimeRanges[blockIndex].endHour : 7 },
                                        set: { newValue in
                                            while sm.settings.blockTimeRanges.count <= blockIndex {
                                                sm.settings.blockTimeRanges.append(BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0))
                                            }
                                            sm.settings.blockTimeRanges[blockIndex].endHour = newValue
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d:00", hour)).tag(hour)
                                        }
                                    }

                                    Picker("End Minute", selection: Binding(
                                        get: { blockIndex < sm.settings.blockTimeRanges.count ? sm.settings.blockTimeRanges[blockIndex].endMinute : 0 },
                                        set: { newValue in
                                            while sm.settings.blockTimeRanges.count <= blockIndex {
                                                sm.settings.blockTimeRanges.append(BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0))
                                            }
                                            sm.settings.blockTimeRanges[blockIndex].endMinute = newValue
                                        }
                                    )) {
                                        ForEach(0..<60, id: \.self) { minute in
                                            Text(String(format: ":%02d", minute)).tag(minute)
                                        }
                                    }
                                }
                                .font(.caption)

                                // Goal input
                                let goalText: Binding<String> = Binding(
                                    get: {
                                        if blockIndex < sm.settings.blockGoals.count {
                                            return sm.settings.blockGoals[blockIndex]
                                        }
                                        return ""
                                    },
                                    set: { newValue in
                                        if blockIndex < sm.settings.blockGoals.count {
                                            sm.settings.blockGoals[blockIndex] = newValue
                                        } else {
                                            sm.settings.blockGoals.append(newValue)
                                        }
                                    }
                                )
                                TextField("Optional goal", text: goalText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.vertical, 4)
                        }

                        Divider()

                        Button("Reset Block Progress") { showResetBlockConfirm = true }
                        .foregroundColor(.orange)

                        Button("Clear Block History") { showClearBlocksConfirm = true }
                        .foregroundColor(.red)
                    }
                }
            }
            .padding()
        }
    }

    var habiticaSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Connect to Habitica", isOn: $sm.settings.connectHabitica)
                if sm.settings.connectHabitica {
                    Group {
                        Text("Habitica User ID:")
                        TextField("User ID", text: $sm.settings.uid)
                            .textFieldStyle(.roundedBorder)
                        Text("Habitica API Token:")
                        SecureField("API Token", text: $sm.settings.apiToken)
                            .textFieldStyle(.roundedBorder)
                        Link("Get credentials at habitica.com/user/settings/api",
                             destination: URL(string: "https://habitica.com/user/settings/api")!)
                            .font(.caption)
                    }
                    Divider()
                    Text("Pomodoro Habit").font(.headline)
                    Toggle("+ habit when pomodoro done", isOn: $sm.settings.pomoHabitPlus)
                    Toggle("- habit if stopped early", isOn: $sm.settings.pomoHabitMinus)
                    Toggle("- habit if break extension over", isOn: $sm.settings.breakExtentionFails)
                    Toggle("Use custom Pomodoro Habit ID", isOn: $sm.settings.customPomodoroTask)
                    if sm.settings.customPomodoroTask {
                        TextField("Pomodoro Habit ID", text: Binding(
                            get: { sm.settings.pomodoroTaskId ?? "" },
                            set: { sm.settings.pomodoroTaskId = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    Divider()
                    Text("Pomodoro Combo Habit").font(.headline)
                    Toggle("+ habit for set complete", isOn: $sm.settings.pomoSetHabitPlus)
                    Toggle("Use custom Combo Habit ID", isOn: $sm.settings.customSetTask)
                    if sm.settings.customSetTask {
                        TextField("Combo Habit ID", text: Binding(
                            get: { sm.settings.pomodoroSetTaskId ?? "" },
                            set: { sm.settings.pomodoroSetTaskId = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    Divider()
                    Text("Notifications").font(.headline)
                    Toggle("Mobile notification - short break over", isOn: $sm.settings.breakExtentionNotify)
                    Toggle("Mobile notification - long break over", isOn: $sm.settings.longBreakNotify)
                    Divider()
                    Text("Developer Server URL (leave empty for default):")
                    TextField("https://habitica.com/api/v3/", text: $sm.settings.developerServerUrl)
                        .textFieldStyle(.roundedBorder)
                    Text("自定义服务会收到 User ID 和 API Token；只使用你信任的 HTTPS 地址。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    var dataSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data Storage").font(.headline)
                
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved to Documents/.habitica-pomodoro")
                            .font(.body)
                        Text(PomodoroDataDir.url.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                    
                    Button("Save Now") {
                        syncAllData()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text("隐藏文件夹，随 Documents 由 iCloud Drive 自动同步")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Block History").font(.headline)
                Text("Days: \(BlockProgressManager.shared.blockHistory.count)")
                
                let sortedDates = BlockProgressManager.shared.blockHistory.keys.sorted().reversed()
                ForEach(Array(sortedDates.prefix(5)), id: \.self) { date in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let entries = BlockProgressManager.shared.blockHistory[date] {
                            Text("Entries: \(entries.count)")
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                if BlockProgressManager.shared.blockHistory.count > 5 {
                    Text("... and \(BlockProgressManager.shared.blockHistory.count - 5) more days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
    
    private func syncAllData() {
        PomodoroFileChanges.shared.syncFromDiskIfNeeded()
        var failedFiles: [String] = []
        if !SettingsManager.shared.save() { failedFiles.append("habitica_pomodoro_settings.json") }
        if !BlockProgressManager.shared.saveProgress() { failedFiles.append("habitica_pomodoro_block_progress.json") }
        if !BlockProgressManager.shared.saveHistory() { failedFiles.append("habitica_pomodoro_block_history.json") }
        if !BlockProgressManager.shared.saveDailyBlocks() { failedFiles.append("habitica_pomodoro_daily_blocks.json") }
        if !TopThreeManager.shared.save() { failedFiles.append("habitica_pomodoro_top_three.json") }
        if !HistogramManager.shared.save() { failedFiles.append("habitica_pomodoro_histogram.json") }
        if !PlantJournal.shared.save() { failedFiles.append("habitica_pomodoro_plants.json") }
        
        let alert = NSAlert()
        if failedFiles.isEmpty {
            alert.messageText = "Saved"
            alert.informativeText = "All data saved to \(PomodoroDataDir.url.path)"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Save Failed"
            alert.informativeText = "The following files were not saved:\n" + failedFiles.joined(separator: "\n")
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value.wrappedValue) \(suffix)", value: value, in: range)
        }
    }

    func pickerRow(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0.replacingOccurrences(of: ".mp3", with: "")) }
            }
            .frame(width: 140)
            Button {
                let volume: Double
                if label == "Pomodoro end sound" { volume = sm.settings.pomoEndSoundVolume }
                else if label == "Break end sound" { volume = sm.settings.breakEndSoundVolume }
                else { volume = sm.settings.ambientSoundVolume }
                am.playSound(selection.wrappedValue, volume: volume)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue == "None")
            .help("Preview sound")
        }
    }

    func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: 0...1)
                .frame(width: 200)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption)
                .frame(width: 35)
        }
    }
}

// MARK: - Current Block Progress View (当前块进度视图)
struct CurrentBlockProgressView: View {
    @EnvironmentObject var engine: PomodoroEngine

    var body: some View {
        CurrentBlockProgressViewContent()
    }
}

private struct CurrentBlockProgressViewContent: View {
    @EnvironmentObject var engine: PomodoroEngine
    @ObservedObject var blockManager = BlockProgressManager.shared

    var body: some View {
        blockManager.updateBlockIndexFromTime(settings: engine.settings)
        let bp = blockManager.blockProgress
        let (completed, total) = blockManager.getCurrentBlockCompletion(settings: engine.settings)

        return VStack(spacing: 2) {
            Text("B\(bp.currentBlockIndex + 1): \(completed)/\(total)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Block Time Block View (块进度视图)
struct BlockTimeBlockView: View {
    @EnvironmentObject var engine: PomodoroEngine
    @ObservedObject var blockManager = BlockProgressManager.shared

    var body: some View {
        BlockTimeBlockViewContent()
    }
}

private struct BlockTimeBlockViewContent: View {
    @EnvironmentObject var engine: PomodoroEngine
    @ObservedObject var blockManager = BlockProgressManager.shared
    @ObservedObject var plantJournal = PlantJournal.shared

    var body: some View {
        let progress = blockManager.getTodayBlockProgress(settings: engine.settings)
        let totalPomoPerBlock = engine.settings.blockPomoCount

        VStack(spacing: 6) {
            ForEach(0..<engine.settings.blockCount, id: \.self) { blockIndex in
                HStack(spacing: 8) {
                    // Block index label
                    Text("B\(blockIndex + 1)")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundColor(.primary)
                        .frame(width: 25, alignment: .leading)

                    // Show time range if available
                    if blockIndex < engine.settings.blockTimeRanges.count {
                        Text(engine.settings.blockTimeRanges[blockIndex].displayString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // Show block goal if available
                    if blockIndex < engine.settings.blockGoals.count {
                        let goal = engine.settings.blockGoals[blockIndex]
                        if !goal.isEmpty {
                            Text(goal)
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    
                    Spacer()

                    // 同一排种植槽：空圆点 / 灌木 / 枯萎；末尾独立的 combo 树。
                    HStack(spacing: 2) {
                        let completed = blockIndex < progress.count ? progress[blockIndex] : 0
                        let attempts = plantJournal.plants(blockIndex: blockIndex, completed: completed)
                        let visible = Array(attempts.suffix(totalPomoPerBlock))
                        ForEach(0..<totalPomoPerBlock, id: \.self) { pomoIndex in
                            PlantMarkerView(outcome: pomoIndex < visible.count ? visible[pomoIndex] : nil)
                        }
                        .help("完成 \(attempts.filter { $0 == .shrub }.count) · 放弃 \(attempts.filter { $0 == .wilted }.count)")

                        Rectangle().fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 10)
                            .padding(.horizontal, 2)
                        let trees = plantJournal.treeCount(blockIndex: blockIndex)
                        PlantMarkerView(treeCount: trees)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
    }
}

// 与原小圆点共用一行；固定尺寸，不撑大时间块布局。
private struct PlantMarkerView: View {
    var outcome: PlantOutcome? = nil
    var treeCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            if treeCount > 0 {
                Text("🌳")
                    .font(.system(size: 11))
                    .help("完成 \(treeCount) 个 combo")
                if treeCount > 1 {
                    Text("×\(treeCount)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            } else if let outcome = outcome {
                Text(outcome == .shrub ? "🌿" : "🥀")
                    .font(.system(size: 11))
                    .help(outcome == .shrub ? "完成 Pomo：灌木" : "中途放弃：枯萎")
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .help("尚未种植")
            }
        }
        .frame(minWidth: 12, minHeight: 14)
        .accessibilityLabel(treeCount > 0 ? "种树 \(treeCount) 棵" :
            outcome == .shrub ? "灌木" : outcome == .wilted ? "枯萎" : "空种植位")
    }
}

// MARK: - History View
struct HistoryView: View {
    @ObservedObject var hm = HistogramManager.shared
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Pomodoro History").font(.title2)

            // Today summary
            HStack(spacing: 40) {
                VStack {
                    Text("\(hm.getToday()?.pomodoros ?? 0)")
                        .font(.system(size: 36, weight: .bold))
                    Text("Today").font(.caption)
                }
                VStack {
                    Text(String(format: "%.1f", Double(hm.getToday()?.minutes ?? 0) / 60.0))
                        .font(.system(size: 36, weight: .bold))
                    Text("Hours Today").font(.caption)
                }
            }

            Divider()

            // Totals
            HStack(spacing: 30) {
                VStack {
                    Text("\(hm.totalPomodoros)")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Total Pomodoros").font(.caption)
                }
                VStack {
                    Text(String(format: "%.1f", hm.totalHours))
                        .font(.system(size: 28, weight: .semibold))
                    Text("Total Hours").font(.caption)
                }
                VStack {
                    Text(String(format: "%.1f", hm.avgPomodoros))
                        .font(.system(size: 28, weight: .semibold))
                    Text("Daily Avg").font(.caption)
                }
            }

            Divider()

            // Bar chart
            ScrollView {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(lastN(14), id: \.0) { (date, day) in
                        VStack {
                            Text("\(day.pomodoros)")
                                .font(.caption2)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: 24, height: barHeight(day.pomodoros))
                            Text(String(date.suffix(5)))
                                .font(.caption2)
                                .rotationEffect(.degrees(45))
                        }
                    }
                }
                .frame(height: 200)
                .padding()
            }

            HStack {
                Button("Clear History") { showClearConfirm = true }
                .foregroundColor(.red)
            }
        }
        .padding(24)
        .confirmationDialog("清空番茄统计？时间块和种植历史不会被删除。",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空番茄统计", role: .destructive) {
                hm.clear()
                PomodoroEngine.shared.loadTodayCount()
            }
            Button("取消", role: .cancel) {}
        }
    }

    func lastN(_ n: Int) -> [(String, DayHistogram)] {
        Array(hm.sortedEntries.suffix(n))
    }

    func barHeight(_ value: Int) -> CGFloat {
        let maxVal = max(1, hm.sortedEntries.map { $0.day.pomodoros }.max() ?? 1)
        return CGFloat(value) / CGFloat(maxVal) * 150
    }
}
