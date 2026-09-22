import SwiftUI

// MARK: - Mobile Pomo View (番茄钟主页，触屏优化)
struct MobilePomoView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var blockManager = BlockProgressManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

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
                        label: "跳过休息",
                        color: .orange,
                        disabled: !(engine.phase == .pomodoro && !engine.isFrozen)
                    ) {
                        engine.skipToBreak()
                    }

                    controlButton(
                        systemImage: "xmark.circle.fill",
                        label: "结束",
                        color: .red,
                        disabled: !(engine.phase == .breakTime || engine.phase == .breakExtension)
                    ) {
                        engine.reset()
                    }
                }
                .padding(.horizontal, 16)

                // 时间块进度（开启 Block Mode 时）
                if settings.enableBlockMode {
                    Divider().padding(.horizontal, 24)
                    MobileBlockProgressView()
                }

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
                            Task { await engine.refreshHabitica() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.surfaceBackground)
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
        case .manualBreak:    return "完成！点击开始下一个番茄"
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

    private var settings: UserSettings { settingsManager.settings }

    var body: some View {
        blockManager.updateBlockIndexFromTime(settings: settings)
        let progress = blockManager.getTodayBlockProgress(settings: settings)
        let currentIdx = blockManager.blockProgress.currentBlockIndex

        return VStack(alignment: .leading, spacing: 8) {
            Text("Time Blocks")
                .font(.headline)

            ForEach(0..<settings.blockCount, id: \.self) { i in
                let isCurrent = (i == currentIdx)
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

                    // 番茄圆点
                    HStack(spacing: 3) {
                        ForEach(0..<settings.blockPomoCount, id: \.self) { d in
                            Circle()
                                .fill(d < pomoCount(progress, i) ? Color.green : (isCurrent ? Color.white.opacity(0.35) : Color.gray.opacity(0.3)))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isCurrent ? Color.orange : Color.gray.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
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
