import SwiftUI

// MARK: - Mobile Pomo View (番茄钟主页，触屏优化)
struct MobilePomoView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var blockManager = BlockProgressManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject private var api = HabiticaAPI.shared
    @State private var refreshingHabitica = false
    @State private var confirmAbandon = false
    @State private var previewHistory = false
    @State private var previewBlock: Int?

    private var settings: UserSettings { settingsManager.settings }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // 番茄圆圈（点击切换启动/暂停）
                ZStack {
                    Circle()
                        .fill(tomatoColor)
                        .frame(width: 210, height: 210)
                        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)

                    VStack(spacing: 4) {
                        Text(engine.timerString)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        if settings.enableBlockMode {
                            Text(blockProgressText)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text("\(engine.pomoSetCounter)/\(settings.pomoSetNum)")
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .onTapGesture { engine.togglePomodoro() }
                .padding(.top, 12)

                Text(phaseHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 今日统计
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Today: \(engine.todayPomodoros) pomodoros")
                        .font(.subheadline)
                }

                // 控制按钮（大点击区）
                HStack(spacing: 14) {
                    controlButton(
                        systemImage: engine.isFrozen ? "play.fill" : "pause.fill",
                        label: engine.isFrozen ? "继续" : "暂停",
                        color: .blue,
                        disabled: !(engine.isRunning || engine.isFrozen)
                    ) {
                        engine.isFrozen ? engine.unfreeze() : engine.freeze()
                    }

                    controlButton(
                        systemImage: "forward.fill",
                        label: "跳到休息",
                        color: .orange,
                        disabled: engine.phase != .pomodoro
                    ) {
                        engine.skipToBreak()
                    }

                    controlButton(
                        systemImage: "xmark.circle.fill",
                        label: engine.phase == .pomodoro ? "放弃" : "结束",
                        color: .red,
                        disabled: !(engine.phase == .pomodoro || engine.phase == .breakTime || engine.phase == .breakExtension)
                    ) {
                        if engine.phase == .pomodoro {
                            confirmAbandon = true
                        } else {
                            engine.reset()
                        }
                    }
                }
                .padding(.horizontal, 16)

                if engine.phase == .idle && !engine.isRunning {
                    Menu {
                        ForEach([1, 5, 15, 30], id: \.self) { minutes in
                            Button("\(minutes) 分钟") { engine.takeBreak(duration: minutes) }
                        }
                    } label: { Label("自选休息", systemImage: "cup.and.saucer") }
                }

                // 时间块进度（开启 Block Mode 时）
                if settings.enableBlockMode {
                    Divider().padding(.horizontal, 24)
                    MobileBlockTimelineView()
                    MobileBlockProgressView()
                }

                NavigationLink {
                    MobileHistoryView()
                } label: {
                    Label("专注统计与历史", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)

                // Habitica 状态
                if settings.connectHabitica {
                    Divider().padding(.horizontal, 24)
                    HStack(spacing: 18) {
                        Label(String(format: "%.1f", engine.habiticaMonies), systemImage: "dollarsign.circle.fill")
                            .foregroundColor(.yellow)
                        Label(String(format: "%.0f", engine.habiticaExp), systemImage: "star.fill")
                            .foregroundColor(.purple)
                        Label(String(format: "%.0f", engine.habiticaHp), systemImage: "heart.fill")
                            .foregroundColor(.red)
                        Button {
                            refreshingHabitica = true
                            Task { @MainActor in
                                await engine.refreshHabitica()
                                refreshingHabitica = false
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(refreshingHabitica)
                    }
                    .font(.subheadline)
                    if let error = api.lastError { Text(error).font(.caption).foregroundColor(.orange).padding(.horizontal, 20) }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.surfaceBackground)
        .navigationTitle("Pomo")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("放弃当前番茄？未完成不计数，并中断组合。", isPresented: $confirmAbandon) {
            Button("放弃", role: .destructive) { engine.pomodoroInterrupted(breakStreak: true) }
        }
        .onAppear {
            blockManager.updateBlockIndexFromTime(settings: settings)
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-previewHistory") { previewHistory = true }
            if let i = args.firstIndex(of: "-previewBlock"), i + 1 < args.count, let block = Int(args[i + 1]), block >= 0, block < settings.blockCount { previewBlock = block }
            #endif
        }
        .navigationDestination(isPresented: $previewHistory) { MobileHistoryView() }
        .sheet(isPresented: Binding(get: { previewBlock != nil }, set: { if !$0 { previewBlock = nil } })) {
            if let index = previewBlock { NavigationStack { MobileBlockEditorView(blockIndex: index) } }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            blockManager.updateBlockIndexFromTime(settings: settings)
            engine.loadTodayCount()
        }
    }

    // MARK: - 子组件

    private func controlButton(systemImage: String, label: String, color: Color,
                               disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(disabled ? Color.gray.opacity(0.45) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(disabled ? 0.05 : 0.1))
            )
        }
        .disabled(disabled)
    }

    private var tomatoColor: Color {
        switch engine.tomatoState {
        case .wait:      return Color(red: 0.55, green: 0.81, blue: 0.95)
        case .progress:  return Color.green
        case .freeze:    return Color(red: 0.70, green: 0.78, blue: 0.86)
        case .breakTime: return Color(red: 0.42, green: 0.58, blue: 0.84)
        case .win:       return Color.green
        case .warning:   return Color.red
        }
    }

    private var phaseHint: String {
        if engine.isFrozen { return "已暂停 · 点击圆圈继续" }
        switch engine.phase {
        case .pomodoro:       return "专注中 · 点击圆圈暂停"
        case .breakTime:      return "休息中"
        case .breakExtension: return "休息延长中"
        case .manualBreak:    return "完成！点击圆圈开始休息"
        case .idle:           return "点击圆圈开始番茄"
        }
    }

    private var blockProgressText: String {
        let bp = blockManager.blockProgress
        let (completed, total) = blockManager.getCurrentBlockCompletion(settings: settings)
        // 进行中时展示"正在做的第几个"，与 macOS menubar 行为一致
        let display = (engine.isRunning && engine.phase == .pomodoro)
            ? min(completed + 1, total) : completed
        return "B\(bp.currentBlockIndex + 1): \(display)/\(total)"
    }
}

// MARK: - Mobile Block Progress (时间块进度，紧凑列表)
struct MobileBlockProgressView: View {
    @ObservedObject var blockManager = BlockProgressManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var plantJournal = PlantJournal.shared
    @State private var selectedBlock: Int?

    private var settings: UserSettings { settingsManager.settings }

    var body: some View {
        let progress = blockManager.getTodayBlockProgress(settings: settings)
        let currentIdx = blockManager.blockProgress.currentBlockIndex

        return VStack(alignment: .leading, spacing: 8) {
            Text("Time Blocks")
                .font(.headline)

            ForEach(0..<settings.blockCount, id: \.self) { i in
                let isCurrent = (i == currentIdx)
                Button {
                    selectedBlock = i
                } label: {
                VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("B\(i + 1)")
                        .font(.caption.monospaced())
                        .frame(width: 26, alignment: .leading)
                        .foregroundColor(isCurrent ? .white : .secondary)

                    Text(timeRange(i))
                        .font(.caption2.monospaced())
                        .foregroundColor(isCurrent ? .white.opacity(0.85) : .secondary)

                    Text(goal(i))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(isCurrent ? .white : .primary)

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(isCurrent ? .white : .secondary)
                }

                    // 种植槽与 Mac 共用 PlantJournal：完成/放弃/空槽，末尾为 combo 树。
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let attempts = plantJournal.plants(blockIndex: i, completed: pomoCount(progress, i))
                        let visible = Array(attempts.suffix(settings.blockPomoCount))
                        ForEach(0..<settings.blockPomoCount, id: \.self) { d in
                            if d < visible.count {
                                Text(visible[d] == .shrub ? "🌿" : "🥀")
                                    .accessibilityLabel(visible[d] == .shrub ? "灌木" : "枯萎")
                            } else {
                                Circle().strokeBorder(isCurrent ? Color.white.opacity(0.7) : Color.secondary.opacity(0.4), lineWidth: 1)
                                    .frame(width: 7, height: 7)
                                    .frame(width: 14, height: 16)
                                    .accessibilityLabel("空种植位")
                            }
                        }
                        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1, height: 12)
                        let trees = plantJournal.treeCount(blockIndex: i)
                        if trees > 0 {
                            Text("🌳" + (trees > 1 ? "×\(trees)" : ""))
                                .accessibilityLabel("种树 \(trees) 棵")
                        } else {
                            Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                                .frame(width: 7, height: 7).frame(width: 14, height: 16)
                                .accessibilityLabel("空 combo 位")
                        }
                    }
                    .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isCurrent ? Color.orange : Color.gray.opacity(0.08))
                )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: Binding(
            get: { selectedBlock != nil },
            set: { if !$0 { selectedBlock = nil } }
        )) {
            if let index = selectedBlock {
                NavigationStack { MobileBlockEditorView(blockIndex: index) }
            }
        }
    }

    private func pomoCount(_ progress: [Int], _ i: Int) -> Int {
        i < progress.count ? progress[i] : 0
    }

    private func timeRange(_ i: Int) -> String {
        guard i < settings.blockTimeRanges.count else { return "" }
        return settings.blockTimeRanges[i].displayString
    }

    private func goal(_ i: Int) -> String {
        guard i < settings.blockGoals.count else { return "" }
        return settings.blockGoals[i]
    }
}
