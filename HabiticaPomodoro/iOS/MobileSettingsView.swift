import SwiftUI

// MARK: - Mobile Settings View (iOS 原生风格设置页)
struct MobileSettingsView: View {
    @ObservedObject var sm = SettingsManager.shared
    @ObservedObject private var audio = AudioManager.shared
    @ObservedObject private var api = HabiticaAPI.shared
    @State private var connecting = false
    @State private var resetBlockConfirmation = false
    @State private var clearBlockConfirmation = false
    @State private var clearFocusConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // Habitica 账号
                Section("Habitica") {
                    Toggle("连接 Habitica", isOn: $sm.settings.connectHabitica)
                    if sm.settings.connectHabitica {
                        TextField("User ID", text: $sm.settings.uid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("API Token", text: $sm.settings.apiToken)
                        Button(connecting ? "连接中…" : "连接并刷新 Habitica") {
                            connecting = true
                            Task { @MainActor in
                                await PomodoroEngine.shared.initHabiticaTasks()
                                connecting = false
                            }
                        }.disabled(connecting)
                        if let error = api.lastError { Text(error).font(.caption).foregroundColor(.orange) }
                        Text("获取方式：Habitica 网站 → Settings → API")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // 番茄时长
                Section("番茄钟") {
                    StepperRow(label: "番茄时长", value: $sm.settings.pomoDurationMins, range: 1...120, suffix: "分钟")
                    StepperRow(label: "短休息", value: $sm.settings.breakDuration, range: 1...60, suffix: "分钟")
                    StepperRow(label: "休息延长", value: $sm.settings.breakExtention, range: 0...30, suffix: "分钟")
                    StepperRow(label: "长休息", value: $sm.settings.longBreakDuration, range: 1...120, suffix: "分钟")
                    StepperRow(label: "长休息间隔", value: $sm.settings.pomoSetNum, range: 1...12, suffix: "个番茄")
                    Toggle("手动开始休息", isOn: $sm.settings.manualBreak)
                    Toggle("休息延长后重置番茄", isOn: $sm.settings.resetPomoAfterBreak)
                }

                // Habitica 计分
                Section("Habitica 计分") {
                    Toggle("完成番茄 +habit", isOn: $sm.settings.pomoHabitPlus)
                    Toggle("中断番茄 -habit", isOn: $sm.settings.pomoHabitMinus)
                    Toggle("完成番茄组合 +habit", isOn: $sm.settings.pomoSetHabitPlus)
                    Toggle("休息超时 -habit", isOn: $sm.settings.breakExtentionFails)
                    Toggle("使用自定义 Pomodoro Habit", isOn: $sm.settings.customPomodoroTask)
                    if sm.settings.customPomodoroTask {
                        TextField("Pomodoro Habit ID", text: optionalID(\.pomodoroTaskId))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Toggle("使用自定义 Combo Habit", isOn: $sm.settings.customSetTask)
                    if sm.settings.customSetTask {
                        TextField("Combo Habit ID", text: optionalID(\.pomodoroSetTaskId))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Text("不使用自定义 ID 时，连接后自动查找或创建 Pomodoro / Pomodoro Combo! 习惯；组合完成会分别执行开启的番茄奖励与组合奖励。")
                        .font(.caption).foregroundColor(.secondary)
                    Toggle("短休息结束提醒", isOn: $sm.settings.breakExtentionNotify)
                    Toggle("长休息结束提醒", isOn: $sm.settings.longBreakNotify)
                    TextField("自定义 API 服务地址（留空使用默认）", text: $sm.settings.developerServerUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("自定义服务会收到 User ID 和 API Token；请只使用你信任的 HTTPS 地址。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 声音
                Section("声音") {
                    Picker("番茄结束音", selection: $sm.settings.pomoEndSound) {
                        ForEach(AudioManager.allSoundOptions, id: \.self) { name in
                            Text(name.replacingOccurrences(of: ".mp3", with: "")).tag(name)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("音量").font(.caption)
                        Slider(value: $sm.settings.pomoEndSoundVolume, in: 0...1)
                    }
                    Button("预听番茄结束音") { audio.playSound(sm.settings.pomoEndSound, volume: sm.settings.pomoEndSoundVolume) }
                    Picker("休息结束音", selection: $sm.settings.breakEndSound) {
                        ForEach(AudioManager.allSoundOptions, id: \.self) { name in
                            Text(name.replacingOccurrences(of: ".mp3", with: "")).tag(name)
                        }
                    }
                    Slider(value: $sm.settings.breakEndSoundVolume, in: 0...1) {
                        Text("休息音量")
                    }
                    Button("预听休息结束音") { audio.playSound(sm.settings.breakEndSound, volume: sm.settings.breakEndSoundVolume) }
                    Picker("环境音", selection: $sm.settings.ambientSound) {
                        ForEach(AudioManager.allAmbientOptions, id: \.self) { name in
                            Text(name.replacingOccurrences(of: ".mp3", with: "")).tag(name)
                        }
                    }
                    Slider(value: $sm.settings.ambientSoundVolume, in: 0...1) {
                        Text("环境音量")
                    }
                    Button("预听环境音") { audio.playSound(sm.settings.ambientSound, volume: sm.settings.ambientSoundVolume) }
                    Button("停止预听") { audio.stopPreview() }
                    if let error = audio.lastError { Text(error).font(.caption).foregroundColor(.orange) }
                }

                // 时间块
                Section("时间块 (Block Mode)") {
                    Toggle("启用时间块", isOn: $sm.settings.enableBlockMode)
                    if sm.settings.enableBlockMode {
                        StepperRow(label: "块数量", value: $sm.settings.blockCount, range: 1...24, suffix: "块")
                        StepperRow(label: "每块番茄数", value: $sm.settings.blockPomoCount, range: 1...12, suffix: "个")
                        Toggle("完成时间块奖励", isOn: $sm.settings.blockRewardEnabled)
                        Toggle("冲刺提醒", isOn: $sm.settings.blockSprintReminder)
                        Toggle("开始前提醒", isOn: $sm.settings.blockStartReminder)
                        if sm.settings.blockStartReminder {
                            StepperRow(label: "提前提醒", value: $sm.settings.blockReminderMinutes, range: 1...60, suffix: "分钟")
                        }
                        Text("点击番茄页面的时间块可编辑目标、时间及任务。")
                            .font(.caption).foregroundColor(.secondary)
                        Button("重置当前时间块进度", role: .destructive) { resetBlockConfirmation = true }
                        Text("仅清当前块计数；历史达标与植物保留。同一天同一块不会重复奖励。")
                            .font(.caption).foregroundColor(.secondary)
                        Button("清空时间块与植物历史", role: .destructive) { clearBlockConfirmation = true }
                    }
                }

                // 数据
                ICloudSyncSection()
                Section("数据清理") {
                    Button("清空番茄统计", role: .destructive) { clearFocusConfirmation = true }
                    Text("专注统计与块/植物历史分开清理，不删除 Task 或设置。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("重置当前块计数？", isPresented: $resetBlockConfirmation) {
                Button("重置", role: .destructive) { BlockProgressManager.shared.resetCurrentBlockProgress(settings: sm.settings) }
            }
            .confirmationDialog("清空全部时间块与植物历史？", isPresented: $clearBlockConfirmation) {
                Button("清空", role: .destructive) { BlockProgressManager.shared.clearHistory() }
            }
            .confirmationDialog("清空全部番茄统计？", isPresented: $clearFocusConfirmation) {
                Button("清空", role: .destructive) { HistogramManager.shared.clear() }
            }
            .onDisappear { audio.stopPreview() }
            .onChange(of: sm.settings.enableBlockMode) { enabled in
                if enabled && sm.settings.blockStartReminder {
                    BlockNotificationManager.shared.requestPermissionIfNeeded()
                }
            }
            .onChange(of: sm.settings.blockStartReminder) { enabled in
                if enabled && sm.settings.enableBlockMode {
                    BlockNotificationManager.shared.requestPermissionIfNeeded()
                }
            }
        }
    }

    private func optionalID(_ key: WritableKeyPath<UserSettings, String?>) -> Binding<String> {
        Binding(get: { sm.settings[keyPath: key] ?? "" }, set: { sm.settings[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}

// MARK: - iCloud Drive 文件同步
/// 用户一次性授权 iCloud Drive 目录（Files 选择器），App 在其中定位
/// `.habitica-pomodoro`，与 macOS 端读写同一批 JSON 文件。
struct ICloudSyncSection: View {
    @ObservedObject private var grant = ICloudFolderGrant.shared
    @State private var showPicker = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var showRevokeConfirm = false

    var body: some View {
        Section("iCloud Drive 同步") {
            HStack(spacing: 8) {
                Image(systemName: grant.isConnected ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundColor(grant.isConnected ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(grant.isConnected ? "已连接" : "未连接")
                        .font(.subheadline).fontWeight(.medium)
                    Text(grant.statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Button("立即保存全部数据") {
                PomodoroFileChanges.shared.syncFromDiskIfNeeded()
                var failedFiles: [String] = []
                if !SettingsManager.shared.save() { failedFiles.append("habitica_pomodoro_settings.json") }
                if !BlockProgressManager.shared.saveProgress() { failedFiles.append("habitica_pomodoro_block_progress.json") }
                if !BlockProgressManager.shared.saveHistory() { failedFiles.append("habitica_pomodoro_block_history.json") }
                if !BlockProgressManager.shared.saveDailyBlocks() { failedFiles.append("habitica_pomodoro_daily_blocks.json") }
                if !TopThreeManager.shared.save() { failedFiles.append("habitica_pomodoro_top_three.json") }
                if !PlantJournal.shared.save() { failedFiles.append("habitica_pomodoro_plants.json") }
                if !HistogramManager.shared.save() { failedFiles.append("habitica_pomodoro_histogram.json") }
                alertMessage = failedFiles.isEmpty
                    ? "Saved：全部数据已保存到当前数据目录。"
                    : "以下文件未保存：\n" + failedFiles.joined(separator: "\n")
                showAlert = true
            }
            Text("文件级最后写入生效；iCloud 系统负责传送文件，在线 Habitica 不会同步本机专注历史。")
                .font(.caption2).foregroundColor(.secondary)

            if grant.isConnected {
                Button("重新选择文件夹") { showPicker = true }
                Button("断开连接", role: .destructive) { showRevokeConfirm = true }
                    .foregroundColor(.red)
            } else {
                Button("选择 iCloud Drive 文件夹…") { showPicker = true }
            }

            if grant.isConnected, grant.dataFolderURL != nil {
                LabeledContent("数据目录") {
                    Text(grant.dataFolderDescription)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if grant.dataFileCount > 0 {
                    Text("✅ 已找到 \(grant.dataFileCount) 个数据文件，与 Mac 版共用同一份数据。")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("⚠️ 该目录下没有数据文件。请确认 Mac 端已运行过应用，且选择的是 iCloud Drive → Documents（不是其他文件夹）。")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Text("提示：`.habitica-pomodoro` 是隐藏文件夹，Files 里看不到也选不了它——只需选择它的父文件夹（iCloud Drive 或 iCloud Drive/Documents 都可以，App 会自动定位）。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("未连接时数据保存在本机沙盒；已配置 Habitica 时，新建的 Task 仍可上传 todo，但本机历史不会因此与 Mac 文件同步。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        // 文件夹选择器（iOS 14+），asCopy=false 才能拿到可写的 security-scoped URL
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if grant.grant(from: url) {
                    // 写入自检：授权被撤销时 resolve 可能仍成功但实际不可写
                    if grant.verifyWritable() {
                        grant.reloadAllManagers()
                        grant.refreshBookmarkIfNeeded()
                        alertMessage = "已连接 iCloud Drive，数据已从云端加载。"
                    } else {
                        grant.revoke()
                        grant.reloadAllManagers()
                        alertMessage = "该文件夹不可写，请重新选择（或检查 设置 → 隐私 → 文件与文件夹）。"
                    }
                } else {
                    alertMessage = "授权失败，请重试。"
                }
                showAlert = true
            case .failure(let error):
                alertMessage = "选择文件夹失败：\(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("iCloud Drive", isPresented: $showAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("断开后将改用本机沙盒存储，已同步到 iCloud 的文件不会被删除。",
                            isPresented: $showRevokeConfirm, titleVisibility: .visible) {
            Button("断开连接", role: .destructive) {
                grant.revoke()
                grant.reloadAllManagers()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Stepper Row
struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value) \(suffix)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
