import SwiftUI
import UserNotifications

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
            button.image = nil // Hide icon, show text only
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

        // Setup global hotkey via Carbon (Alt+Shift+P)
        HotKeyManager.shared.register()

        // Start badge alternating display
        startBadgeAlternating()

        // Start with timer window visible
        showTimerWindow()
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
            timerWindow?.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            timerWindow?.setFrameAutosaveName("TimerWindow")
            timerWindow?.setContentSize(NSSize(width: 360, height: 420))
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
            button.title = ""
            return
        }

        if badgeDisplayMode == .timer {
            // Show countdown
            button.title = engine.timerString
        } else {
            // Show completed/total count
            let count = "\(engine.pomoSetCounter)/\(engine.settings.pomoSetNum)"
            button.title = count
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

    var body: some View {
        VStack(spacing: 16) {
            // Tomato / status circle
            ZStack {
                Circle()
                    .fill(tomatoColor)
                    .frame(width: 120, height: 120)
                    .shadow(radius: 4)

                VStack {
                    Text(engine.timerString)
                        .font(.system(.title, design: .monospaced).bold())
                        .foregroundColor(.white)
                    Text("\(engine.pomoSetCounter)/\(engine.settings.pomoSetNum)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .onTapGesture { engine.activate() }

            // Today count
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("Today: \(engine.todayPomodoros) pomodoros")
                    .font(.subheadline)
            }

            // Action buttons row
            HStack(spacing: 12) {
                if engine.settings.showSkipToBreakOpt && (engine.phase == .pomodoro) && !engine.isFrozen {
                    Button(action: { engine.skipToBreak() }) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help("Skip to break")
                }

                Button(action: {
                    engine.isFrozen ? engine.unfreeze() : engine.freeze()
                }) {
                    Image(systemName: engine.isFrozen ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(engine.isFrozen ? "Resume" : "Freeze")
                .opacity((engine.settings.showFreezeOpt && engine.phase == .pomodoro) ? 1 : 0)

                if engine.phase == .breakTime || engine.phase == .breakExtension {
                    Button(action: { engine.reset() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("End session")
                }
            }
            .frame(height: 28)

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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("History") {
                    showHistoryWindow()
                }
            }
            .font(.subheadline)

            Spacer()
        }
        .padding(24)
        .frame(width: 360, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

    var body: some View {
        TabView {
            timerSettingsTab.tabItem { Label("Timer", systemImage: "timer") }
            habiticaSettingsTab.tabItem { Label("Habitica", systemImage: "link") }
        }
        .frame(width: 420, height: 560)
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
                    Toggle("Show skip-to-break button", isOn: $sm.settings.showSkipToBreakOpt)
                    Toggle("Show freeze button", isOn: $sm.settings.showFreezeOpt)
                }
                Divider()
                Group {
                    Text("Sounds").font(.headline)
                    pickerRow("Pomodoro end sound", selection: $sm.settings.pomoEndSound, options: AudioManager.allSoundOptions)
                    sliderRow("Volume", value: $sm.settings.pomoEndSoundVolume)
                    pickerRow("Break end sound", selection: $sm.settings.breakEndSound, options: AudioManager.allSoundOptions)
                    sliderRow("Volume", value: $sm.settings.breakEndSoundVolume)
                    pickerRow("Ambient sound", selection: $sm.settings.ambientSound, options: AudioManager.allAmbientOptions)
                    sliderRow("Volume", value: $sm.settings.ambientSoundVolume)
                }
                Divider()
                Text("HotKey: ⌥⇧P (Alt+Shift+P)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    Divider()
                    Text("Pomodoro Combo Habit").font(.headline)
                    Toggle("+ habit for set complete", isOn: $sm.settings.pomoSetHabitPlus)
                    Divider()
                    Text("Notifications").font(.headline)
                    Toggle("Mobile notification - short break over", isOn: $sm.settings.breakExtentionNotify)
                    Toggle("Mobile notification - long break over", isOn: $sm.settings.longBreakNotify)
                    Divider()
                    Text("Developer Server URL (leave empty for default):")
                    TextField("https://habitica.com/api/v3/", text: $sm.settings.developerServerUrl)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        }
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

// extension for optional bool settings - always shown in native app
extension UserSettings {
    var showSkipToBreakOpt: Bool {
        get { true }
        set { /* always visible in native */ }
    }
    var showFreezeOpt: Bool {
        get { true }
        set { /* always visible in native */ }
    }
}

// MARK: - History View
struct HistoryView: View {
    @ObservedObject var hm = HistogramManager.shared

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
                Button("Clear History") {
                    hm.clear()
                }
                .foregroundColor(.red)
            }
        }
        .padding(24)
    }

    func lastN(_ n: Int) -> [(String, DayHistogram)] {
        Array(hm.sortedEntries.suffix(n))
    }

    func barHeight(_ value: Int) -> CGFloat {
        let maxVal = max(1, hm.sortedEntries.map { $0.day.pomodoros }.max() ?? 1)
        return CGFloat(value) / CGFloat(maxVal) * 150
    }
}
