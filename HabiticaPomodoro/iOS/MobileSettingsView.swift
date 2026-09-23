import SwiftUI

// MARK: - Mobile Settings View (iOS 原生风格设置页)
struct MobileSettingsView: View {
    @ObservedObject var sm = SettingsManager.shared

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
                        Text("获取方式：Habitica 网站 → Settings → API")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // 番茄时长
                Section("番茄钟") {
                    StepperRow(label: "番茄时长", value: $sm.settings.pomoDurationMins, range: 1...120, suffix: "分钟")
                    StepperRow(label: "短休息", value: $sm.settings.breakDuration, range: 1...60, suffix: "分钟")
                    StepperRow(label: "长休息", value: $sm.settings.longBreakDuration, range: 1...120, suffix: "分钟")
                    StepperRow(label: "长休息间隔", value: $sm.settings.pomoSetNum, range: 1...12, suffix: "个番茄")
                    Toggle("手动开始休息", isOn: $sm.settings.manualBreak)
                }

                // Habitica 计分
                Section("Habitica 计分") {
                    Toggle("完成番茄 +habit", isOn: $sm.settings.pomoHabitPlus)
                    Toggle("中断番茄 -habit", isOn: $sm.settings.pomoHabitMinus)
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
                }

                // 时间块
                Section("时间块 (Block Mode)") {
                    Toggle("启用时间块", isOn: $sm.settings.enableBlockMode)
                    if sm.settings.enableBlockMode {
                        StepperRow(label: "块数量", value: $sm.settings.blockCount, range: 1...24, suffix: "块")
                        StepperRow(label: "每块番茄数", value: $sm.settings.blockPomoCount, range: 1...12, suffix: "个")
                    }
                }

                // 数据
                ICloudSyncSection()

                Section {
                    Button("保存并退出") {
                        sm.save()
                    }
                }
            }
            .navigationTitle("Settings")
        }
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

            if grant.isConnected {
                Button("重新选择文件夹") { showPicker = true }
                Button("断开连接", role: .destructive) { showRevokeConfirm = true }
                    .foregroundColor(.red)
            } else {
                Button("选择 iCloud Drive 文件夹…") { showPicker = true }
            }

            if grant.isConnected, let dir = grant.dataFolderURL {
                LabeledContent("数据目录") {
                    Text(dir.lastPathComponent)
                        .font(.caption).foregroundColor(.secondary)
                }
                Text("数据文件与 Mac 版共用同一个 iCloud Drive 文件夹。首次请在 Files 中选择 iCloud Drive → Documents（`.` 开头的文件夹在 Files 中不可见，App 会自动在其中定位 .habitica-pomodoro）。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("未连接时数据保存在本机沙盒，任务仍可通过 Habitica 云端同步。")
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
