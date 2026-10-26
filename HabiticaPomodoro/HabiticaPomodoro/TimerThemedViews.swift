import SwiftUI

// MARK: - Theme-driven Mac layouts (three switchable visual directions)

extension TimerView {

    var theme: AppTheme { AppTheme(style: styleStore.style, dark: colorScheme == .dark) }

    var sideSettings: UserSettings { settingsManager.settings }

    // MARK: Shared header / navigation

    var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    func headerBar(showsTitle: Bool = true) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if showsTitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text("专注好这一刻。")
                        .font(.system(size: styleStore.style == .studio ? 19 : 20, weight: .medium))
                        .foregroundColor(theme.ink)
                    Text(dateLine)
                        .font(.system(size: 11))
                        .foregroundColor(theme.muted)
                }
            }
            Spacer(minLength: 0)
            paletteMenu
            headerIcon("clock.arrow.circlepath") { showHistoryWindow() }
            headerIcon("gearshape") { showSettings() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    var paletteMenu: some View {
        Menu {
            ForEach(AppUIStyle.allCases) { style in
                Button {
                    styleStore.style = style
                } label: {
                    if style == styleStore.style {
                        Label("\(style.title) · \(style.tagline)", systemImage: "checkmark")
                    } else {
                        Text("\(style.title) · \(style.tagline)")
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.muted)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换界面风格")
    }

    func headerIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.muted)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var navTitles: [String] { ["专注", "任务", "习惯", "每日", "角色"] }
    var navSymbols: [String] { ["timer", "checklist", "sparkles", "calendar", "person.crop.circle"] }

    var mintNav: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Button { tabState.selectedTab = index } label: {
                    Text(navTitles[index])
                        .font(.system(size: 11, weight: tabState.selectedTab == index ? .semibold : .regular))
                        .foregroundColor(tabState.selectedTab == index ? theme.accent : theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tabState.selectedTab == index ? theme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.subtle)
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    var bottomNav: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                Button { tabState.selectedTab = index } label: {
                    VStack(spacing: 4) {
                        Image(systemName: navSymbols[index]).font(.system(size: 14))
                        Text(navTitles[index]).font(.system(size: 9))
                    }
                    .foregroundColor(tabState.selectedTab == index ? theme.accent : theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.accent)
                Text("专注")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.ink)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            ForEach(0..<5, id: \.self) { index in
                Button { tabState.selectedTab = index } label: {
                    HStack(spacing: 9) {
                        Image(systemName: navSymbols[index]).font(.system(size: 13))
                        Text(navTitles[index]).font(.system(size: 12, weight: tabState.selectedTab == index ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(tabState.selectedTab == index ? theme.accent : theme.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tabState.selectedTab == index ? theme.accentSoft : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 12)
        .frame(width: 150)
        .background(theme.subtle)
    }

    // MARK: Layouts

    @ViewBuilder var mintLayout: some View {
        VStack(spacing: 0) {
            headerBar()
            mintNav
            if tabState.selectedTab == 0 {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        focusHeading
                        focusCore(ringSize: 210)
                        statsLine
                        blockCard
                        tasksCard
                        soundRow
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
                }
            } else {
                themedTabContent
            }
        }
    }

    @ViewBuilder var gardenLayout: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        Spacer(minLength: 0)
                        paletteMenu
                        headerIcon("clock.arrow.circlepath") { showHistoryWindow() }
                        headerIcon("gearshape") { showSettings() }
                    }
                    .padding(.top, 12)

                    if tabState.selectedTab == 0 {
                        VStack(spacing: 5) {
                            Text("留一刻，给自己。")
                                .font(.system(size: 23, weight: .regular))
                                .foregroundColor(theme.ink)
                            Text(dateLine)
                                .font(.system(size: 11))
                                .foregroundColor(theme.muted)
                        }
                        .padding(.top, 4)

                        phaseMenu
                        RingTimer(progress: engine.phaseProgress,
                                  text: timerDisplay,
                                  caption: timerCaption,
                                  theme: theme,
                                  size: 228)
                        controlsRow(fullWidth: true)
                        Text("今天已完成 \(engine.todayPomodoros) 次专注")
                            .font(.system(size: 11))
                            .foregroundColor(theme.muted)
                        blockCard
                        tasksCard
                        soundRow
                    } else {
                        themedTabContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            bottomNav
        }
    }

    @ViewBuilder var studioLayout: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                headerBar()
                if tabState.selectedTab == 0 {
                    ScrollView(showsIndicators: false) {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 14) {
                                phaseMenu
                                RingTimer(progress: engine.phaseProgress,
                                          text: timerDisplay,
                                          caption: timerCaption,
                                          theme: theme,
                                          size: 205)
                                controlsRow(fullWidth: true)
                                statsLine
                                habiticaStrip
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 14) {
                                blockCard
                                tasksCard
                                soundRow
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                    }
                } else {
                    themedTabContent
                }
            }
        }
    }

    @ViewBuilder var themedTabContent: some View {
        switch tabState.selectedTab {
        case 1:
            TopThreeView()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)
        case 2:
            HabiticaHabitsView().padding(.horizontal, 18).padding(.top, 8)
        case 3:
            HabiticaDailiesView().padding(.horizontal, 18).padding(.top, 8)
        default:
            HabiticaProfileView().padding(.horizontal, 18).padding(.top, 8)
        }
    }

    // MARK: Focus composition

    var focusHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("你的专注")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundColor(theme.muted)
                Text("把重要的事，先做好。")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(theme.ink)
            }
            Spacer(minLength: 0)
            phaseMenu
        }
    }

    var timerDisplay: String {
        if engine.phase == .idle && engine.timerString == "00:00" {
            return String(format: "%02d:00", sideSettings.pomoDurationMins)
        }
        return engine.timerString
    }

    var timerCaption: String {
        if engine.isFrozen { return "已暂停 · 随时继续" }
        switch engine.phase {
        case .pomodoro: return "专注中 · 让时间慢慢发生"
        case .breakTime, .breakExtension, .manualBreak: return "休息中 · 放松一下"
        default: return "准备开始第 \(engine.pomoSetCounter + 1) 次专注"
        }
    }

    var phaseLabel: String {
        switch engine.phase {
        case .pomodoro: return engine.isRunning ? "专注" : "专注已暂停"
        case .breakTime, .breakExtension, .manualBreak: return "休息"
        default: return "专注"
        }
    }

    var phaseMenu: some View {
        Menu {
            Button(engine.isRunning ? "暂停" : "开始 / 继续") { engine.togglePomodoro() }
            Divider()
            ForEach([1, 5, 15, 30], id: \.self) { minutes in
                Button("休息 \(minutes) 分钟") { engine.takeBreak(duration: minutes) }
            }
            .disabled(engine.phase != .idle || engine.isRunning || engine.isFrozen)
        } label: {
            HStack(spacing: 5) {
                Circle().fill(theme.accent).frame(width: 5, height: 5)
                Text(phaseLabel).font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundColor(theme.accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule().fill(theme.accentSoft)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换阶段或开始休息")
    }

    func focusCore(ringSize: CGFloat) -> some View {
        VStack(spacing: 12) {
            RingTimer(progress: engine.phaseProgress,
                      text: timerDisplay,
                      caption: timerCaption,
                      theme: theme,
                      size: ringSize)
            controlsRow(fullWidth: true)
        }
        .frame(maxWidth: .infinity)
    }

    func controlsRow(fullWidth: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                engine.togglePomodoro()
            } label: {
                Label(primaryTitle, systemImage: primarySymbol)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PrimaryActionStyle(theme: theme))

            Button {
                resetTapped()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 38)
            }
            .buttonStyle(QuietButtonStyle(theme: theme))
            .help(engine.phase == .pomodoro ? "放弃本次番茄" : "结束当前阶段")

            if engine.phase == .pomodoro {
                Button {
                    engine.skipToBreak()
                } label: {
                    Image(systemName: "forward.end")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 38)
                }
                .buttonStyle(QuietButtonStyle(theme: theme))
                .help("跳到休息")
            }
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    var primaryTitle: String {
        if engine.isFrozen { return "继续专注" }
        if engine.isRunning && engine.phase == .pomodoro { return "暂停专注" }
        if engine.isRunning && (engine.phase == .breakTime || engine.phase == .breakExtension || engine.phase == .manualBreak) {
            return "暂停休息"
        }
        return "开始专注"
    }

    var primarySymbol: String {
        (engine.isRunning || engine.isFrozen) ? "pause.fill" : "play.fill"
    }

    func resetTapped() {
        if engine.phase == .pomodoro {
            showAbandonConfirm = true
        } else {
            engine.reset()
        }
    }

    var statsLine: some View {
        HStack(spacing: 10) {
            Label("\(engine.todayPomodoros) 次", systemImage: "checkmark.circle")
            Text("·").foregroundColor(theme.line)
            Text("\(engine.todayPomodoros * sideSettings.pomoDurationMins) 分钟")
            Text("·").foregroundColor(theme.line)
            Text("第 \(engine.pomoSetCounter + 1) / \(sideSettings.pomoSetNum) 个")
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(theme.muted)
    }

    @ViewBuilder var habiticaStrip: some View {
        if sideSettings.connectHabitica {
            HStack(spacing: 12) {
                Label(String(format: "%.1f", engine.habiticaMonies), systemImage: "circle.fill")
                    .foregroundColor(theme.muted)
                Label(String(format: "%.0f", engine.habiticaExp), systemImage: "star.fill")
                    .foregroundColor(theme.muted)
                Label(String(format: "%.0f", engine.habiticaHp), systemImage: "heart.fill")
                    .foregroundColor(theme.muted)
                Button {
                    Task { await engine.refreshHabitica() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.muted)
            }
            .font(.system(size: 10))
        }
    }

    // MARK: Cards

    struct FocusTaskRow: Identifiable {
        let id: UUID
        let title: String
        let category: String
        let isCompleted: Bool
    }

    var todaysFocusTasks: [FocusTaskRow] {
        let key = topThree.todayKey(settings: sideSettings)
        guard let day = topThree.store.history[key] else { return [] }
        var rows: [FocusTaskRow] = []
        for (index, group) in day.taskGroups.enumerated() {
            for task in group where !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(FocusTaskRow(id: task.id,
                                         title: task.title,
                                         category: topThree.categoryName(index: index),
                                         isCompleted: task.isCompleted))
            }
        }
        return Array(rows.prefix(4))
    }

    var blockCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("当前时间块")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer(minLength: 0)
                Button("查看全部") { showBlocksSheet = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
            }

            if sideSettings.enableBlockMode {
                let index = min(max(0, blockManager.blockProgress.currentBlockIndex),
                                max(0, sideSettings.blockCount - 1))
                let pair = blockManager.getCurrentBlockCompletion(settings: sideSettings)
                HStack(spacing: 11) {
                    Text("B\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.accentSoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(blockGoal(index) ?? "第 \(index + 1) 个时间块")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.ink)
                            .lineLimit(1)
                        Text(blockTimeText(index) ?? "未设置时间范围")
                            .font(.system(size: 9))
                            .foregroundColor(theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text("\(pair.completed) / \(pair.total)")
                        .font(.system(size: 11))
                        .foregroundColor(theme.muted)
                        .monospacedDigit()
                }
            } else {
                Text("时间块模式未启用，可在设置中开启。")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
            }
        }
        .themeCard(theme)
    }

    func blockGoal(_ index: Int) -> String? {
        guard sideSettings.blockGoals.indices.contains(index) else { return nil }
        let value = sideSettings.blockGoals[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func blockTimeText(_ index: Int) -> String? {
        guard sideSettings.blockTimeRanges.indices.contains(index) else { return nil }
        let range = sideSettings.blockTimeRanges[index]
        return String(format: "%02d:%02d – %02d:%02d",
                      range.startHour, range.startMinute, range.endHour, range.endMinute)
    }

    var tasksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日要事")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer(minLength: 0)
                Button("全部任务") { tabState.selectedTab = 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
            }

            if todaysFocusTasks.isEmpty {
                Text("还没有添加今天最重要的三件事。")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
                    .padding(.vertical, 2)
            } else {
                ForEach(todaysFocusTasks) { row in
                    Button { tabState.selectedTab = 1 } label: {
                        HStack(spacing: 8) {
                            Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(row.isCompleted ? theme.accent : theme.line)
                            Text(row.title)
                                .font(.system(size: 11))
                                .foregroundColor(row.isCompleted ? theme.muted : theme.ink)
                                .strikethrough(row.isCompleted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(row.category)
                                .font(.system(size: 9))
                                .foregroundColor(theme.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .themeCard(theme)
    }

    var soundRow: some View {
        Button { showSettings() } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 13))
                    .foregroundColor(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.subtle))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ambientLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.ink)
                    Text("跟随专注 · 在设置中更换")
                        .font(.system(size: 9))
                        .foregroundColor(theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(theme.muted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var ambientLabel: String {
        if sideSettings.ambientSource == "qishi" {
            return "栖时 · 随机场景"
        }
        let name = sideSettings.ambientSound
        return name.isEmpty ? "无背景音" : "自定义 · \(name)"
    }

    var blocksSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("今天的时间块")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer()
                Button("完成") { showBlocksSheet = false }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    BlockTimeBlockView().environmentObject(engine)
                    BlockTimelineView().frame(height: 216)
                }
                .padding(20)
            }
        }
        .frame(width: 470, height: 640)
        .background(theme.background)
    }
}
