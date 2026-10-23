# Habitica Pomodoro Android

Kotlin + Jetpack Compose 客户端。以 macOS 的可移植业务为基准，不机械复制桌面布局。

> **当前状态（2026-10-23）**：`v1.2.5-android` 已发布，APK 为 `HabiticaPomodoro-Android-1.2.5.apk`（versionCode 5）。下方 2026-10-03 记录属于历史，不代表当前仍未发布或那些续修仍未完成。现有离线回归见 [fixtures/README.md](fixtures/README.md)，跨端最新记录见 [FEATURE_PARITY.md](../HabiticaPomodoro/FEATURE_PARITY.md)。本轮 Android 生产代码未变；暂无 Android 真机，真机验收继续暂缓。

## 已实现的功能

- **计时**：绝对结束时刻；开始、暂停/继续、显式放弃、跳到短休息。暂停不算失败；放弃/跳过不增加番茄或 combo。完成一组后保留满组计数，正确进入长休息，结束后清 combo。
- **休息**：自动/手动开始短长休息，1/5/15/30 分钟自选休息；0–30 分钟休息延长；延长结束可清空或保留 combo，支持超时扣分。休息暂停后恢复仍走休息结束逻辑，不错误记录番茄。短/长休息均发系统通知，可另选发送 Habitica 私信。
- **声音**：十四个自定义 MP3 与 Apple 端一致，结束音/休息音/环境音独立音量。另可选栖时 73 场景随机混音；只打包场景 JSON，音频从公开站流式，需要联网。自定义预听最多 8 秒；专注场景随机/防重/暂停恢复由 VM 持有，服务负责播放和资源释放。使用音频焦点，结束音服务尾部有界，不无限保留前台服务。
- **时间块/植物**：1–24 块、每块 1–12 个番茄；跨午夜时段、目标、块任务完成/删除/标题编辑/预计番茄数（1–12）；不足的数组安全补齐，保留隐藏块配置。按当前实际时段计入自然日进度，完成 🌿、放弃/跳过 🥀、combo 🌳。每日首次达标记录/奖励/休息建议一次，不在超额或恢复时重复奖励；当前块计数重置与清空全部块/植物历史分开并确认。
- **提醒**：系统块前提醒、提前 1–60 分钟、4/6 冲刺提醒；块前提醒在后台经 AlarmManager 调度，重启/时区/系统时间变化后重排，支持跨午夜。无需 exact-alarm 特殊授权；**采用非精确提醒，待机与省电政策可能使提醒晚于设定时间**。提醒需要通知权限，拒绝不崩溃。
- **Task**：Work/MyOwn 最多新增 3 条，Chores 无上限；标题修改、完成/取消、确认删除、分类重命名、昨日只读及未完成任务顺延。标题、分类 tag、专用日期 notes 同步 Habitica；云端只导入带严格有效日期/分类标记的 Top3 todo，按远端 ID 保守合并，不导入普通 todo。
- **失败保护**：未上传/未确认的修改保留并标记待同步，inbound 不覆盖；删除墓碑阻止失败删除被重新导入；丢失创建响应保存原始创建载荷，重试先核对唯一远端匹配，避免盲目重复创建。无法确认的删除/创建需显式重试或人工核对。完成重试先读远端状态，不盲目重复 score。账号/API 地址变化使旧请求失效。
- **Habitica**：Habits +/−、Dailies 完成/取消、角色刷新；默认按 alias 查找/初始化 Pomodoro 与 Pomodoro Combo!，不在认证、网络或服务器失败时误创建；可选自定义 Habit ID。旧 Android JSON 已配置的手动 ID 保留为自定义模式。完成、中断、combo、休息超时及独立块奖励的开关实际调用 API。
- **角色**：职业取 `stats.class`，注册/登录取 `auth.timestamps.created/loggedin` 的 ISO 时间；HP 上限 50、MP 与 EXP 公式同 Swift；EXP 不使用取模造成进度归零；Quests 计数不误标为所有 todo 完成数。
- **统计**：`habitica_pomodoro_histogram.json` 使用 Swift 相同的 `pomodoros/minutes/weekday` 字段。分钟取实际完成阶段的时长快照，改设置不改旧分钟；总数/总小时、日均、近期条形图、逐日/块/植物/任务历史。番茄统计独立确认清理，不删除 Task 或块数据。
- **生命周期**：Activity 和前台服务共用 Application 内的单一引擎；通知携带当前 phase ID，暂停/继续后旧操作失效，已经结束的阶段优先结算。计时快照在进程重建后恢复；服务只渲染通知/播放音频，业务结算不维护第二套状态。

## 存储与同步边界

- **Task 使用逻辑日**：第一个时间块起点为日界，默认 04:00；午夜后未到日界仍是前一个任务日。
- **新番茄统计、块进度、植物使用自然日**，与 Swift 参考一致。旧 Android `pomo_count` 只有计数、没有会话时间/分钟；迁移保留原来的键和值，旧分钟标为未知，不按当前设置伪造，也不凭空重新归档日期。
- 本机 JSON 位于应用私有 `files/.habitica-pomodoro/`。设置、番茄/块/植物历史**不经 Habitica 同步，也不访问 iCloud**。Mac/iPhone 已上传且带专用日期 notes 的 Task 可经 Habitica 合并；尚未上传的本地记录不能跨端读取。
- 含 UID/Token 的设置文件、临时原子写文件、活动计时快照排除 Android 云备份和设备换机迁移；换机后重新填写凭据。任务/非敏感历史可备份。新增字段有旧 JSON 默认值，模型/StateFlow 使用不可变快照。
- 自定义 API 地址只接受不含 URL 账号、查询参数和片段的 HTTPS 根地址，应用前明确提示 **UID/Token 会交给该服务器**。不跟随重定向；错误不展示服务器响应原文、Token 或原始网络异常。不表示“HTTPS 就可信”。
- 系统强制停止/杀进程时不能保证实时网络打分或继续音频；重开后校时并恢复。本机完成记录不因网络计分失败删除；非幂等奖励不会自动盲重试。

## 构建

依赖 JDK 21 与 SDK 35：

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
bash build_android.sh debug
bash build_android.sh lint
```

构建脚本用 wrapper 8.11.1，保留完整输出和真实失败退出码。缓存和生成产物在 `${HERMES_SCRATCH:-$HOME/.hermes/cache/scratch}`，避免 iCloud 把 Gradle 缓存/生成资源复制成带空格的冲突文件。Debug 不读取 release 凭据。

- Debug APK：`~/.hermes/cache/scratch/pomo-parity-build/app/outputs/apk/debug/app-debug.apk`
- Lint 报告：`~/.hermes/cache/scratch/pomo-parity-build/app/reports/lint-results-debug.html`
- 直接在非 iCloud 工作区执行 `./gradlew assembleDebug` 仍使用默认 `app/build`；也可用 `-PpomoBuildRoot=/absolute/scratch/build` 指定隔离输出。

仅对你明确选择的模拟器/测试设备安装，避免不带 `-s` 操作真实设备：

```bash
adb -s emulator-5562 install -r ~/.hermes/cache/scratch/pomo-parity-build/app/outputs/apk/debug/app-debug.apk
adb -s emulator-5562 shell am start -n com.habitica.pomodoro/.MainActivity
```

## 离线回归与 CI

在 JDK 21 环境从仓库根运行 `python3 HabiticaPomodoroAndroid/fixtures/run.py --work /path/to/non-cloud-scratch`。已有缓存时可加 `--no-download`，仅复用工具链、不下载依赖。套件编译真实模型/VM，API/Android 服务为明确的离线替身；Compose UI、真实 MediaPlayer、音频焦点、后台与账号在线流程不在这些断言内。

CI 的 Android job 使用 JDK 21，明确安装 SDK 35 的 platform-tools、platform 与 build-tools，先跑回归再构建 APK。本轮 workflow 尚未推送，远端运行是否通过仍需后续确认。

## 历史验证记录（2026-10-03，非当前结论）

下列保留当时结果及待修项；后续 D1、写失败提示、隔离清理及错误状态续修和 v1.2.4 发布详见上方最新记录入口，不把历史“未通过”当作当前结论。

- 最新 `assembleDebug lintDebug`：在十四音效与三项定向修复落盘后实际 **BUILD SUCCESSFUL**；lint **0 errors / 9 warnings / 2 information**，未用 baseline 掩盖问题。保留 SDK XML 版本提示，不将其隐去。
- scratch 隔离检查最终 **35/35 通过**（原 24 项＋新增 11 项）：包含生产引擎/模型/合并类、从源码提取的 Today 与 UID 回调，新增覆盖多 UUID 创建歧义、moved 归档保护/配额、UID 草稿与 owner 迁移。Android/Compose/API plumbing 使用明确的内存 fixtures，不是模拟器界面或线上 Habitica 结果；未新增仓库测试框架。真实 API 类的 UID 门禁、字面 header、HTTPS/重定向配置、无凭据 JSON 检查亦通过，HTTP 请求为 0。
- 三项前轮缺陷已修：重试仅唯一原 UUID 可认领结果；Today 与修改入口保护 moved 档案；UID 草稿严格校验后显式应用，非法/空白保留原配置。**最终独立终审仍未通过**：已绑定同一远端 ID 的多个本地 UUID 可以在 retry 路径互相覆盖；未确认创建结果在远端改名后可绕过本地删除 marker 重新导入。用户已批准额外一轮定向修复，正在执行 RED/GREEN 隔离复现与修复。35 项离线自验并未覆盖这两项边界，不能替代修后审查批准。
- 最终 APK 的十四个 MP3 已全部打包并校验，与 Mac/iOS 原始音频逐一 SHA-256 一致；APK CRC 校验通过，未发现运行数据文件被打包。
- 已创建全新无账号 AVD `pomo_parity_20261003`，未操作原有 AVD/真实设备；多次启动失败，日志报 **磁盘空间不足**。主机只剩约 1–2 GB；Android Emulator 官方说明启动需要至少 5 GB 空闲。因此 **尚未完成安装、UI 截图、后台音频/计时的模拟器验证**，不能把构建通过称为全部验收通过。
- 早期遇到 iCloud 的 Gradle executionHistory 损坏、源码暂时 dataless 和生成 XML 冲突副本；最终通过隔离构建产物/缓存恢复编译，不更改其他平台源码。

## 人工验收清单（待运行/真机）

- [ ] 空白安装启动，拒绝/允许通知均不崩溃；Settings → 改时长即时重组 UI。
- [ ] 1 分钟专注：暂停/继续不加番茄或枯萎，完成后分钟 +1；进行中改时长仍按启动快照记录分钟。
- [ ] combo=1 自动/手动长休息；长休息暂停/继续不能增加番茄；结束清 combo。
- [ ] combo>1 短休息后进入延长；延长 0/1 分钟分别检查，reset 开关保留/清 combo；在线验证超时扣分一次。
- [ ] 显式放弃记枯萎并清 combo；跳到短休息记枯萎但不加番茄、不扣分；自选 1/5/15/30 分钟能结束。
- [ ] 环境音循环、调音量、更换/None、暂停/恢复/放弃；两种结束音和预听真实可听；退出设置停止预听；结束时服务最终释放。
- [ ] 通知暂停/继续/放弃与 UI 同步；旧通知 phase ID 操作不影响新阶段；锁屏和返回前台不重复结算。
- [ ] 块数 8→24→1→24，范围不足不越界；跨午夜定位；修改标题/预计番茄数、完成/删除块任务。
- [ ] 块前系统提醒/跨午夜提醒；开启/关闭后重新排程；4/6 冲刺一天一次；首次达标建议/奖励一次，超过目标不再奖励。
- [ ] 重置当前块使当天该块计数同步归零，保留植物/达标账本；独立确认清空块历史/番茄统计，不误删 Task。
- [ ] Task 标题修改、完成/取消、删除；离线修改和删除不被云刷新覆盖；昨日只读/顺延；分类改名同步 tag 与 dated notes。
- [ ] 使用专用 Habitica 测试账号：默认 Habit 初始化、自定义 ID、所有计分分支、私信、Habits/Dailies、角色、远端已完成 todos 导入和账号切换。
- [ ] 检查普通 todo、无效日期/未知分类不导入；重复拉取无重复；创建响应丢失/删除失败后的保护与显式重试。
- [ ] 检查旧 count-only 数据分钟显示未知；改变当前时长不改旧分钟；历史图表/均值/自然日与任务逻辑日分别正确。
- [ ] 自定义 API HTTP/含账号/含 query 地址被拒绝；可信 HTTPS 地址要二次确认；重定向不发送凭据；备份与换机不带 Token。

官方行为参考：Android Developers 的 Schedule alarms、Manage audio focus、Foreground service types、Emulator troubleshooting 文档。系统通知/音频/后台与真实 Habitica 在线功能仍须人工验证；不引入收费同步方案。
