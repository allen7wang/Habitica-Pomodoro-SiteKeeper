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
                Section("数据") {
                    LabeledContent("存储位置", value: "本机沙盒")
                    Text("iOS 数据存于应用沙盒内，任务通过 Habitica 云端同步；与 Mac 版的本地文件不互通。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

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
