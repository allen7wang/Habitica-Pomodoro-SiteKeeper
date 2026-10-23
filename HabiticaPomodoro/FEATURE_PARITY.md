# 桌面与移动端功能对齐验收清单

> macOS、iOS、Android 的业务功能与记录规则对齐，不要求机械复制桌面布局。三端 v1.2.5 已于 2026-10-23 发布，纳入 2026-10-22 的防卡顿、Apple 音频、回归与 CI 优化；界面视觉尚未改造，`sketches/fresh-ui/` 仅为设计预览。本文同时保留历次记录，旧日期的“尚未发布/待修”不代表现状，也**不是所有人工项已通过的声明**。不含手表端。

## 当前状态索引（2026-10-23）

| 状态 | 范围与边界 |
|---|---|
| 已公开 | Mac `v1.2.5`、iOS `v1.2.5-ios` 未签名 IPA、Android `v1.2.5-android` APK；包含 2026-10-22 防卡顿、Apple 音频与前台补记修复 |
| 已安装 Mac | 2026-10-22 防卡顿热修 1.2.4/build 8；v1.2.5 尚未替换本机安装 |
| 工作区 | 后台七文件重载、防覆盖、Apple 专注/试听资源隔离、离线回归、CI 依赖修正已随 v1.2.5 发布；界面视觉改造尚未开始 |
| 待验收 | 长时间日常使用、真实音频/锁屏后台、Habitica 在线及账号切换、iCloud 跨设备系统传送；Android 无设备暂缓真机 |
| 回归入口 | [Apple fixtures](fixtures/README.md)、[Android fixtures](../HabiticaPomodoroAndroid/fixtures/README.md)；离线绿不等于设备或线上绿 |

## 共同业务功能

| 模块 | 对齐标准 |
|---|---|
| 番茄计时 | 启动、暂停、继续、显式放弃、跳到休息；暂停不计失败，放弃/跳过不算完成，也不增加 combo；阶段沿用启动时的业务配置，跨日恢复按原期限归档且不自动创造新专注 |
| 休息 | 短休息、长休息、手动/自动开始；1/5/15/30 分钟自选休息仅限空闲且保留已有 combo；延长为 0 不按超时处理；暂停休息再继续不能错误完成一个番茄 |
| 时长设置 | 番茄 1–120 分钟、短休息 1–60 分钟、长休息 1–120 分钟、延长 0–30 分钟、combo 1–12 个 |
| 时间块 | 1–24 块，每块 1–12 个番茄；分钟 0–59、午夜端点、跨午夜时段，起止相等按全天；目标、块任务、标题修改、完成/确认删除及预计番茄数；当前块定位 |
| 时间块奖励 | 达标仅记录/奖励一次，不因超过目标或重复恢复而重复计分；支持开始前提醒、冲刺提醒、提前分钟配置和休息建议 |
| 种植 | 完成一个 Pomo 种灌木，放弃/跳过记枯萎；combo 另种树，空槽保留；与每日块进度分文件存储 |
| Task | Work/MyOwn 各最多新增 3 条，Chores 无上限；新增、修改标题、完成/取消、确认删除、分类改名、昨日只读及未完成任务顺延 |
| Task 云同步 | 创建/编辑/完成/删除对应 Habitica todo，分类对应 tag；仅导入严格应用日期/分类备注，远端 ID 合并保留 UUID；顺延更新日期，离线分类改名可重试；账号归属隔离 pending/映射/删除队列，回切不重复；创建响应不明先核对，不盲目重复 POST |
| Habitica | Habits 的 +/−、Dailies 完成/取消、Role 信息及刷新；请求期间阻止重复操作，旧账号响应不得污染当前账号 |
| Habitica 选项 | 普通番茄与 combo 两种完成奖励各按自身开关独立执行；中断与真实延长超时各按自身开关计分；默认或自定义 Habit ID；短休息提醒不依赖是否延长；阶段换账号不向新账号错误计分；自定义 API 需 HTTPS 校验、凭据信任提示及禁止携凭据跟随重定向 |
| 声音 | 番茄结束音、休息结束音、环境音分别选择和调音量；只提供真实打包的资源；预听、暂停/结束时停止环境音 |
| 统计 | 保存每次完成时的实际专注分钟，不用当前设置反算旧记录；今日、总数/总时长、日均、近期图表、块及植物历史 |
| 重置与清理 | 重置当前块同时清当前及当天块计数；与清空全部块/植物历史区分；番茄统计单独清理，不意外删 Task；破坏性操作需确认 |
| 旧数据兼容 | 新设置缺字段时使用默认值，不因为解码失败覆盖旧数据；保留本机离线任务、旧历史和已有植物文件 |

## 日界与存储

- **Task** 使用逻辑日：第一个时间块起点为日界，默认 04:00。午夜后但未到日界仍属于前一任务日。
- **番茄统计、时间块与植物** 保留现有自然日（`yyyy-MM-dd`）规则。不得为统一文案而重新归档已有记录。
- Mac/iPhone 继续使用用户授权的同一 iCloud Drive 父目录和 JSON 文件；不引入需要付费开发者账号的同步方案。
- Android 的设置、专注/块/植物历史存本机；Habitica 只承担其已有的任务/打卡云端通道，**不能将功能一致表述为三端本地历史已同步**。
- 不在源码、产物或验证日志中写入个人账号凭据；Android 含 Token 的设置文件排除备份与换机迁移。

## 平台专属交互（不计为缺少业务功能）

| 平台 | 保留的原生能力与限制 |
|---|---|
| macOS | 菜单栏状态、桌面窗口、键盘快捷键 |
| iOS | 触屏导航、系统本地通知、回前台校时；后台暂停执行时不能承诺实时网络计分 |
| Android | 前台服务通知及通知栏控制；系统提醒受通知权限、电池策略和系统调度影响 |

## 最终验证要求

- macOS 两种架构构建及打包、iOS Simulator 构建、Android Debug 构建均需实际执行。
- 使用隔离存储/专用模拟器检查暂停继续、休息延长、放弃/跳过、块数增减、任务编辑、种植持久化及统计分钟。
- Mac/iPhone 的新增共享数据文件必须接入文件夹发现、读取、重新加载和变更检测。
- 构建通过不等于真机后台与在线功能通过；没有真实测试账号时，Habitica 在线打分/导入/账号切换必须标为未实测。
- 真实设备的声音、锁屏通知和 iCloud 文件选择授权留给人工验收。遵循本项目偏好，不新增自动化测试框架。

## 当前验证状态

**2026-10-10：三端 v1.2.3 本地测试版构建全部通过并安装到位（Mac /Applications 与 iPhone 均为含终审修复的最终构建）；Apple 两项终审修复经 fresh 只读独审通过（Scope A/B passed），Android archive-delete 续修经 fresh 只读独审 G1–G7 全数通过（另报 D1 中危/D2-D4 低危附加缺陷，属修复范围外的既有边界）。仍未做在线 E2E、账号切换 E2E 和正式发布。**

- 第一轮已修：账号归属/删除队列、任务顺延与分类同步、待创建结果核对、七文件远端变更消费、Android 阶段恢复及休息/奖励规则。
- Android 第三轮：父核读计数确认 47/47 后追加 `archive-delete` 失败（同 UUID moved 历史副本误拦截明确删除）；续修代理 `deleg_0d8636dc` 以 owner 分区持久化 `deletedCloudTaskOrigins` 修复，transcript 内 red-archive-resume 先红（1/1 EXIT=1）后绿，扩展 18/18、全量 53/53（GREEN_EXIT=0、ALL_EXIT=0）。父复核：`PomodoroViewModel.kt` SHA `5b2b0cb6…`、`Models.kt` SHA `46158252…` 与代理受测快照一致，`deletedCloudTaskOrigins` 实际落盘（VM 4 处/Models 6 处）。scratch 夹具目录已被系统 24h 清理，仅余 delegation transcript 证据。settled `assembleDebug` BUILD SUCCESSFUL（1m40s），APK 1.2.3/versionCode 3，SHA `dcf478c3…`（24M）。
- Apple 第三轮五处定向修复（rename/replacement/version/histogram/steal）与 cloud/save 回归日志父核读通过。fresh 独立终审（`deleg_01b26164`）两项失败已于 2026-10-08 修复：
  1. **派发竞态（high）**：`HabiticaAPI.perform` 改为 `@MainActor` 隔离 + `withCheckedThrowingContinuation` 同步创建并 `resume()` `URLSessionDataTask`；`scoreHabit/createTodo/updateTodo/scoreTodo/deleteTodo` 全链 `@MainActor`。调用方（`pushTask`/`synchronize`，均 `@MainActor`）的身份/revision 校验与真实 HTTP dispatch 现处于同一不可中断 MainActor 段，消除 guard 与派发之间的 executor 切换窗口。
  2. **旧 Histogram 备份归属（P2）**：`HistogramManager.backup(at:)` 删除 `legacyPath == nil` 自动归属分支；旧全局备份仅当 `_backupPath` 与目标路径精确匹配才采用，来源不明备份保留为未归属数据，不再冒充沙箱/授权目录数据。
- 修后三端 Apple 构建全部 exit 0：Mac universal（build.sh）、iOS Simulator（build_ios.sh --no-install）、iOS 真机 Release 签名构建（Team Q7N96QQT8M，profile 含本机 UDID，有效期至 2026-10-15T11:32:35Z）。产物父核验：Mac app 1.2.3/build 6、x86_64+arm64、strict 签名 valid、DMG CRC VALID、14 音频、0 运行数据 JSON；真机 app 1.2.3/build 2、strict 签名、TeamIdentifier Q7N96QQT8M、embedded.mobileprovision 含设备 UDID。
- iPhone 实机（2026-10-10 最终态）：10-08 两次覆盖安装后，含 @MainActor 全链修复的最终真机构建已于 10-10 重新构建（旧 scratch 产物被系统 24h 清理）并覆盖安装（databaseSequenceNumber 5916），手机回读 1.2.3/build 2、strict 签名、profile 含本机 UDID、14 音频、0 业务数据 JSON；应用已启动，旧 `.habitica-pomodoro` 数据目录（9/23）与 UserDefaults plist 保留。均同 bundle ID 覆盖安装，不卸载不清数据。免费 profile 2026-10-15T11:32:35Z 过期，届时需重签重装。
- `/Applications/HabiticaPomodoro.app`（2026-10-10 最终态）：经用户确认后正常退出（AppleScript quit，非强杀）旧实例并替换为含终审修复的 1.2.3/build 6；二进制 SHA `083fea2e…` 与源构建一致、双架构、strict 签名。旧版备份在 `~/Library/Caches/HabiticaPomodoroInstallBackups/20261010-183351/`。
- **fresh 独立终审（`deleg_9c3e2a99`，2026-10-10，只读静态控制流审查，SHA 门控与受测源一致）**：
  - Apple Scope A（派发竞态修复）**passed**：pushTask 守卫 → updateTodo/scoreTodo/createTodo/deleteTodo → perform → matchesCurrentRequest → continuation 同步 resume() 为同一不可中断 MainActor 段（6 处 @MainActor 全链核验，Swift 5.9 minimal 模式下注解完整生效）；completion-handler 风格下 willPerformHTTPRedirection 仍投递 session 级 NoRedirectDelegate（非 bypass 清单回调），x-api-key 无跨源泄漏回归；无死锁/重入/数据竞争。3 条信息级备注（perform 内 MainActor.run 冗余、读侧 API 仍 nonisolated 但 dispatch 统一经 MainActor、dataTask 仅此一处）。
  - Apple Scope B（Histogram 旧备份归属修复）**passed**：来源不明全局备份无法再流入任何目录（init/reload/save 全调用面核验）；A 目录备份在 revoke 到 B 后不再冒充 B 数据，safe-by-default。1 条低危备注：真正旧版（有 legacy 键无 _backupPath）+ 首启文件恰好损坏的窄场景失去自动恢复（数据未删、可人工找回，对照被修复的 P2 误归属判定可接受）；另 rememberBackup 三写非原子为修复前遗留理论残余。
  - Android G1–G7 **全部 passed（7/7）**：同 UUID 归档副本豁免三条件（origin 非空 + UUID 相同 + movedToToday）精确限定；不同 UUID/同 UUID 活跃行仍阻塞；旧 JSON 无字段安全解码且无 origin 时 fail-safe 保护；origin 跨重启持久化（temp+rename 原子写）；owner 分区隔离与别名合并保守（冲突即丢弃、退化为人工核对）；DELETE 精确 id + 双集合同一 copy 原子清除无孤儿。附加缺陷（修复范围外既有问题）：**D1（中）**`deletedCreateMarkers` 在"入队后 404 确认前进程死亡"的重启重试路径上成为永久孤儿并持续隔离同分类+日期+标题的未来云端 todo；D2（低）persistStore 磁盘写失败静默吞掉无 UI 提示；D3（低）legacy 首次迁移认领既有队列（被服务端鉴权与行过滤兜住，无跨账号删除能力）；D4（信息）topThreeSyncError 只增不清。
- 全局快捷键回调、保存全部遗漏植物、Mac 块任务预计数编辑/删除确认已修；快捷键保持原有 `⌥⌘P`。
- macOS 可运行产物放在 `~/Library/Caches/HabiticaPomodoroBuild/HabiticaPomodoro.app`，避免 iCloud FileProvider 附加 Finder 属性破坏严格签名；DMG 仍在项目目录。
- 仍未做：真实 Habitica 在线 E2E、账号切换 E2E、锁屏通知/服务恢复/音频焦点验收、真机音效与 iCloud 跨设备传播人工验收、正式 release（公开 Mac 仍 v1.2.2，移动仍 v1.0.0-ios / v1.0.0-android）。构建、离线夹具与静态独审绿色不等于在线/UI/后台验收通过。
- **Android D1 修复（2026-10-13，用户批准"把任务跑完"）**：`deleg_2fa04882` 以严格 TDD 修复 `deletedCreateMarkers` 孤儿问题——新增 owner 分区内持久化字段 `TopThreeStore.deletedCloudIdMarkers`（remoteId→marker 关联），三处入队点（deleteTask/retryDeletedCreations/syncTaskToHabitica 姊妹死亡窗口路径）记录关联，deleteCloudTask 404 确认分支在**同一次 copy+persistStore** 中同时清除 deletedCloudIds/deletedCloudTaskOrigins/deletedCloudIdMarkers 三集合并按 resolvedMarker 出队 deletedCreateMarkers。父复核：改动文件 SHA 与代理报告一致（VM `51fe66d0…`、Models `fe8a3c1f…`，TopThreeCloudSync/LocalStore 未动），red.log 4 个 D1 用例 EXIT=1 → green.log 17/17 EXIT=0（两遍）。**注意**：旧 53/18 用例集的 transcript 已被系统清理无法恢复，17 用例为代理重建套件（覆盖 deletion queue/origins/markers/quarantine/owner switch 点名领域），不能宣称 53/53 回归；API 为离线替换件（HTTP 0）。settled `assembleDebug` BUILD SUCCESSFUL（7m53s），APK 1.2.3/versionCode 3、新 SHA `42162dc1…`（24M），dex 内确认含 `deletedCloudIdMarkers`。已知边界：修复前已产生的存量孤儿 marker 不会自动治愈（阻止新孤儿，存量需人工处理）。**fresh 只读独审（`deleg_2088e1f2`，2026-10-13）已返回：I1–I7 全部 passed，总体 passed=true**——三入队点与唯一消费点在同一次原子保存中维护关联与三集合一致性（PVM:819-824/976-977/1180-1181→864-866），404 读回严格门控（网络异常 statusCode=null 不误触发），无过度消费、无跨 owner 泄漏、嵌套分区持久化往返完整、无位置参数构造破坏。三条低危观察均非阻断：①别名分区合并对 marker map 为 primary 静默胜出无冲突过滤（理论边缘，非回归）；②marker 被同标题兄弟绑定吸收时永不退休（修复前既有行为）；③**存量孤儿 marker 无自愈路径**（反复报错+持续隔离同日同名入站 todo，只能改数据文件解除）——建议后续版本加一次性迁移或人工清除入口，已列为已知限制。
- 本地测试版版本配置 **1.2.3**：macOS build 6、iOS build 2、Android versionCode 3。
- **第五轮改进（2026-10-20，用户批准 P0/P1/P2，跳过 Android 真机测试）**：
  - P0 `HabiticaPomodoro/resign_ios.sh`：一键重签脚本——自动发现已连接实体 iPhone（排除模拟器/unavailable）→ 每台构建签名 Release（自动注册新设备）→ 核验（strict 签名/profile 含 UDID/有效期）→ 覆盖安装 → 启动。免费签名 7 天过期后重跑即可。设备发现逻辑经真实输出样例单测；无设备时正确报错；完整安装路径与 10-20 13 Pro 手动实测序列一致。
  - P1 Apple `rememberBackup` 原子化：data+path 合并为单次写入 `_backupEntry`（消除崩溃窗口错配），`backup(at:)` 优先原子 entry、保留 legacy 键兼容与精确路径匹配门控。Mac + iOS Simulator 双端构建 exit 0。
  - P2 CI `.github/workflows/build.yml`：tag push/手动触发；macOS runner 出 universal DMG + 未签名 IPA + Simulator 编译检查，ubuntu runner 出 debug APK；各带 SHA256SUMS artifact。未接自动 release（发布仍本地做）。
  - P0/P1 Android（`deleg_7e817a9e`，TDD 先红后绿）：①设置页"Top3 同步队列"计数 + 确认对话框门控的孤儿 marker 清理入口（`clearQuarantinedCreateMarkers()`，仅清当前 owner 的 deletedCreateMarkers+deletedCloudIdMarkers，**不触碰**删除队列/origins/其他分区）；②`LocalStore.writeJson` 返回 Boolean 上抛，`UiState.persistenceError` 在 Task/设置页展示磁盘写失败；③`topThreeSyncError` 成功完成点带守卫清除（活跃错误不清）；④D3 legacy 认领评估：确认旧 JSON 无可靠归属证据，保留认领 + 11 行决策注释 + 特征化用例钉住行为。
  - 父复核：5 个改动文件 SHA 与代理报告一致（VM `8c3be9df…`、Models `1f16ea18…`、LocalStore `7ed3812a…`、SettingsScreen `d4261aa6…`、TaskScreen `37dace9d…`；TopThreeCloudSync 未动）；red-evidence 9 红（全为新 FIX 例）→ full-regression 30/30；**父独立复跑 harness 30/30 PASS（exit 0）**；settled `assembleDebug` BUILD SUCCESSFUL，APK 新 SHA `1b6cba36…`（1.2.3/code 3），dex 含 `clearQuarantinedCreateMarkers`/`persistenceError` 标记。
  - P2 harness 入仓：`HabiticaPomodoroAndroid/fixtures/`（40+ 文件：run.py + 6 stubs + 31 cases + README），含重建的 D1 17 例套件（原 transcript 已被清理，从生产代码注释语义重建）；未接入 Gradle；API 为离线替身（HTTP 0）。父发现并修复文档坑：kotlinc 2.0.21 在 JDK 22+ 崩溃（JavaVersion.parse），README 已标注 JDK 17–21 要求。
  - 未验证（如实）：Compose UI 仅编译级验证（对话框交互未演练，行为在 VM/state 层断言）；CI workflow 未实际运行（待 push 后触发）；Apple `_backupEntry` 崩溃窗口场景无专项运行探针（逻辑静态审查级）；版本号未 bump（仍 1.2.3，是否发 1.2.4 待用户决定）。
- **macOS 桌面小组件（2026-10-20，用户需求："增加小组件能看到今天任务的完成情况"）**：
  - 平台决策：用户仅选 Mac。iPhone 小组件因免费 Apple ID 不支持 App Groups（Widget Extension 无法读主 App 数据）不可行；Android 未选。
  - 实现：`HabiticaPomodoro/TodayTasksWidget/`（WidgetKit + SwiftUI，中尺寸 systemMedium）——显示今日（逻辑日，与主 App 同 day-boundary 语义：第一个块开始分钟前算昨日）Top3 任务各分类 done/total 进度条，全部完成显示 ✓；`movedToToday` 归档行与空标题不计入。
  - **数据链路（沙箱快照桥）**：首版"非沙箱直读 ~/Documents"被系统拒绝——pkd 日志明确 `plug-ins must be sandboxed`（macOS 强制 app extension 沙箱，ad-hoc 签名不豁免）。改为：appex 带 `com.apple.security.app-sandbox` entitlement 签名；主 App（非沙箱）在 `TopThreeManager` init/save/reload 后经 `WidgetBridge.writeSnapshot` 把 store+boundaryMinutes 写入 widget 容器 `~/Library/Containers/<widget-id>/Data/Library/Application Support/widget-data.json`；widget 沙箱内读自己容器合法。无需 App Group/付费账号。widget 端保留直读回退（非沙箱运行时）与空态占位。
  - 刷新：主 App `TopThreeManager.save()` 成功后写快照 + `WidgetCenter.shared.reloadTimelines(ofKind: "TodayTasks")` 即时推送（`#if os(macOS)`，iOS 共享源码无影响）；TimelineProvider 另有 15 分钟兜底策略。
  - 构建集成：build.sh 第 4/6 步编译 widget universal（arm64+x86_64，target macOS 14）、组装 `Contents/PlugIns/TodayTasksWidget.appex`（NSExtensionPointIdentifier=com.apple.widgetkit-extension），第 5/6 步签名由内而外且 appex 带沙箱 entitlement。widget 源码先快照到非 iCloud 构建目录再编译（FileProvider 会中途 touch 源文件，与主源码同对策）。
  - 验证（2026-10-20 实装）：Mac/iOS 构建 exit 0；`.app` 与 DMG 均含 appex、strict 签名；替换安装后**pkd 注册成功**（`pluginkit -m` 列出 TodayTasksWidget(1.2.3)，不再拒绝）；主 App 启动即写入 widget-data.json（23KB，父核验含 boundaryMinutes=60、categoryNames、今日 history）。**桌面渲染与添加流程待用户验收**（桌面右键→编辑小组件→Habitica Pomodoro→今日任务）。
  - **二次崩溃与最终方案（Xcode extension target）**：首装后 widget 进程反复崩溃（EXC_BREAKPOINT，栈在 Apple `ExtensionFoundation._EXRunningExtension` bootstrap 的 `MainActor.assumeIsolated`），系统日志与公开案例（CodexBar#1095、xtool#313，均 macOS 26+）确认根因：**swiftc 手工编译包装的普通可执行文件缺少 Xcode extension target 的入口/链接设置**，WidgetKit bootstrap 必崩，与我们的代码无关。修复：新增 `TodayTasksWidget/project.yml`（xcodegen `type: app-extension`），build.sh 第 4/6 步改为 xcodegen+xcodebuild 构建 appex（`ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64"` universal，CODE_SIGNING_ALLOWED=NO，签名仍由 build.sh ad-hoc+沙箱 entitlement 完成）；生成物 xcodeproj/Generated 已入 .gitignore。验收判据：appex 二进制直接执行输出 **"An XPC Service cannot be run directly."**（普通可执行文件则直接跑 main）。重装后 pkd 注册成功、快照桥正常、无新崩溃报告。
  - 已知边界：小组件最低 macOS 14；快照含完整 store（数据量随 history 增长，当前 23KB，量级无碍）。
- **栖时（Qishi）随机背景音 · 三端（2026-10-20，用户需求："每个pomo播放的背景音乐随机 qishi 的一个场景，设置可选 qishi 随机或自定义"）**：
  - 资源方案（用户批准：三端都支持、整场景混音）：152MB/133 个 mp3 不打包；场景清单以快照 `qishi_presets.json`（73 presets/175 tracks，26KB）随包分发，由 `scripts/export_qishi_presets.py` 从本机 `~/GitHub/qishi-meditation` 的 `src/data.ts` 导出（node 求值解析——presets 混用 JSON 与 TS 字面量两种写法，Python json 解析不了；文件名校验 `<soundId>.mp3` 全部存在）。栖时场景更新后重跑脚本+三端重建即可。
  - 音频来源：macOS 优先读本机栖时仓库 `public/audio/`（零网络、自动同步栖时更新），缺失回退公开站流式；iOS/Android 从 `https://allen7wang.github.io/qishi-meditation-web/audio/<file>` 流式（HTTP 200/audio/mp3/CORS 开放已验证）。
  - Apple 共享实现：`UserSettings.ambientSource`（"custom" 默认/"qishi"，宽松解码）；`QishiSceneStore`（快照加载+随机避开上个番茄）+ `AudioManager.playAmbientFor(settings:newSession:)` 统一入口——多 AVPlayer 混音（didPlayToEndTime→seek(.zero) 循环，每轨音量=栖时比例×用户音量），`stopAmbient()` 级联停 qishi（覆盖全部既有停止点）；Engine 三调用点（开始=新场景、暂停恢复/回前台=延续同场景）；设置 UI Mac/iOS 均有来源分段选择+试听按钮。
  - Android（`deleg_9c670e3f`，TDD）：同语义实现——Models `ambientSource` 宽松解码、VM `selectQishiScene`/`lastQishiSceneId` 防重复（选择逻辑全在 VM 层可离线测）、PomoAudio 多轨 MediaPlayer prepareAsync 流式+isLooping、Service refreshAudio 分支、设置页分段选择+试听。父复核：6 文件 SHA 与报告一致；**父独立复跑 harness 36/36 PASS（30 既有+6 新 q1 用例）**；关键实现落盘抽查通过。
  - 离线已验证 vs 需真机：设置解码/随机防重/延续/停止点清空/73 场景解析均离线断言；**流式出声、音频焦点、锁屏后台播放需真机**（未验证，如实记录）。
  - 坑：AGP `mergeDebugAssets` 在 iCloud 目录增量构建时对同一 assets 文件报 Duplicate resources（幻影重复，目录实际干净无 `._`/`.icloud` 文件）——`clean assembleDebug` 即恢复，33s 成功。
- 版本 **1.2.4**（四处同步 bump）：macOS build 7、iOS build 3、Widget 1.2.4/7、Android versionCode 4。产物：Mac DMG 11MB（仓库内）、iOS 未签名 IPA SHA `a8f9b3b4…`、Android APK 25.3MB SHA `8d0ca88eaff03546069d76facfae6612de0f44c9069ab661b606427722b680b8`（1.2.4/code 4，assets 含 qishi_presets.json+14 mp3）。Mac 本机已替换安装 1.2.4 build 7（备份 20261020-193433），用户实测 qishi 试听通过（"mac上没有问题"）。
- **Mac 无响应修复（2026-10-22，本地修复版 1.2.4 build 8，未提交/发布）**：
  - 根因证据：系统 `/Library/Logs/DiagnosticReports/HabiticaPomodoro_2026-10-19-155800_Allens-MacBook-Pro.hang` 记录 1.2.3(6) 无响应 23.71 秒；主线程 `PomodoroFileChanges.startMonitoring → syncFromDiskIfNeeded → changedFileNames → Data(contentsOf:) → read → apfs_materialize_dataless_file_ext`。为既有云占位文件读取阻塞，不是该报告能证明的 Qishi 回归；本轮检查时 `/Applications` 实际为 1.2.2(5)，不以之前的装机记录代替当前核验。
  - 修复：七文件轮询/回前台检测改串行后台读取不可变 Result 快照；主线程用预取字节重载（包括首次 manager 初始化），避免 reload 二次云读取。single-flight 覆盖发布及同步 Combine 回调；目录代次、读取代次和每个 manager 应用前的本地变更代次阻止过期结果覆盖；失败保存保留 dirty 路径直到实际写盘成功；块三文件作为一组，dirty/读取错误/坏 JSON 不走备份回写。手动保存全部在异步扫描 completion 后执行，保留先读后写顺序。没有关闭 iCloud 同步或改动 JSON schema。
  - 实测：scratch 内从真实生产源提取的读延迟探针先 RED（主线程最大停顿 2.412s）再 GREEN（最终 0.029s）；真实六个生产 Swift 文件 + DEBUG isolatedDirectory/CFFIXED_USER_HOME 的隔离模型探针 **18 项断言通过**（最终主线程最大间隔 0.019s），覆盖七文件重载、无变化不发布、本地写竞争、坏 JSON 重试、20 请求合批/完成回调顺序、注入写权限失败后的 dirty 保留、块关联文件保护和发布期间回调重入。探针仅模拟慢文件 read，未强制操作真实云占位文件、未读取真实账号。
  - 构建/审查：Mac universal arm64+x86_64、iOS Simulator 最终构建均 exit 0；主 App/Widget strict 签名通过，Qishi 资源仍在包内；最终只读 diff 独审未发现范围内阻断问题。Mac/Widget build 同步到 8，iOS 营销版本及 build 未改；Android 无改动。
  - 本机已安装 1.2.4(8)，二进制 SHA256 `2240750238c3c81a4d5271aceb91acd3a75e3e74bdff5013da813752b45ebf79`；旧 1.2.2(5) 完整备份于 `~/Library/Caches/HabiticaPomodoroInstallBackups/20261022-165741-hang-fix/`。未清理业务数据、未强停计时、未自动启动主 App。
  - 边界：这轮针对已证实的轮询读取阻塞；冷启动直接加载、显式保存/Histogram 读前写、iOS 授权目录元数据查询仍有既有同步 IO，不宣称消除了所有潜在卡顿。真实日常使用仍待用户复验。探针及构建日志暂存 `~/.hermes/cache/scratch/pomo-hang-20261022/`，不入发布物。

## 优化完成与最终验证（2026-10-22，未提交/发布）

- **CI**：修正 xcodegen 安装顺序及 Android SDK 显式包清单；新增 master push/PR，保留 tag/manual；构建前运行两端离线套件。父端复跑 actionlint + ShellCheck 退出 0，9 段 Bash 语法通过；明确产物校验和文件名，避免旧 SHA256SUMS 自包含。**未推送、未触发远端 Actions，不能称 hosted CI 已绿**。
- **Apple 音频**：专注暂停保留场景、播放器与位置；自定义轨道同样复用。试听独立持有资源，不改专注场景或防重复历史；停止试听/离开设置/更换来源清理试听，新专注清理遗留试听。EOF 通知核实播放器归属后始终重置循环位置，暂停时不 play，避免“暂停刚好遇结尾”恢复后静音。
- **前台和目录边界**：Mac/iOS 实际 activation body 统一走 Engine 异步恢复边界，先采纳磁盘快照再补结算；真实 scheduled Timer 同样受屏障保护。恢复令牌、phase revision、目录 generation 拦截重置/暂停/新阶段/A→B→A 后的旧回调，生产按完成时墙钟校时；恢复过程中换目录会暂停原阶段，避免后续 tick 自动写入新目录。失败写入的 dirty ownership 改为每路径 epoch，成功显式替换只确认被替换的旧 epoch，不清除新订阅者失败写入或 Histogram 尚未保存增量。
- **审查闭环**：首轮 48 断言虽通过，独审仍发现上述前台先写、暂停 EOF、目录往返 dirty 残留三项边界。定向用例均先实际失败再修绿；修后由新上下文分别审查生产控制流和 fixtures/实际钩子提取，**两项复审均 passed，无安全或逻辑阻断**。静态审查不是实际设备运行验收。

| 最终父端独立运行 | 结果 |
|---|---|
| `file_monitor` | 24 PASS，native delayed reads=7，最大主线程心跳间隔 0.064s |
| `foreground_recovery` | 21 PASS，native delayed reads=9，最大主线程心跳间隔 0.030s |
| `dirty_reload` | 14 PASS，七存储显式重载/失败写入/坏 JSON/订阅者重入 |
| `qishi_audio` | 29 PASS，保留原断言并加强异步恢复、真实 EOF 状态模型 |
| Apple 全套 | **4/4 cases，88 PASS，40 个编译输入指纹与当前源码一致**；原 48 断言未删减/弱化 |
| Android 既有套件 | **36/36 PASS**，JDK 21、`--no-download`，本轮未改 Android 生产代码或重建 APK |
| Mac + Widget | build.sh 退出 0，二者 arm64+x86_64、strict 签名通过；DMG CRC、只读挂载签名/二进制一致性通过 |
| iOS Simulator | Debug 和 Release 均退出 0，未安装或启动模拟器/手机 |

三份 Apple 应用及挂载 DMG 均核验 14 个自定义 MP3 + 73 场景/175 轨引用的真实 JSON，逐文件 SHA 与源码资源一致；包内未发现运行设置、数据库、凭据配置、fixtures 或 profile 文件。检查不读取真实账号设置，不能把文件清单检查夸大为对所有可能二进制秘密的形式证明。

本轮未升版本：候选仍为 Mac/Widget **1.2.4 build 8**、iOS **1.2.4 build 3**。为避免与已安装的同版本防卡顿包混淆：
- 最终候选 Mac 可执行文件 SHA-256：`192a32c9f7bbc6dc86cf6637310c0538764fd09d7433e05bef5a825c087c7204`。
- 最终 `HabiticaPomodoro-Installer.dmg` SHA-256：`0cf831e7e83657333b604db0e9a640c4214a79cb96249d6f29f31a2763d4e784`。
- `/Applications` 保持之前的防卡顿包，二进制 SHA-256 仍为 `2240750238c3c81a4d5271aceb91acd3a75e3e74bdff5013da813752b45ebf79`；本轮未替换、未启动或中断用户应用，也未更新手机。

回归可从 [Apple fixtures](fixtures/README.md) / [Android fixtures](../HabiticaPomodoroAndroid/fixtures/README.md) 重跑。最终日志与 `artifacts.json` 暂存 `~/.hermes/cache/scratch/pomo-opt-20261022/verified-final/`，scratch 会被清理；本节保存本次摘要与产物身份。真实音频/EOF 听感、窗口/Tab 退出、锁屏后台、Habitica 在线和账号切换、FileProvider 传送、书签与安全作用域均未在本轮实测。A/B 测试仅操作合成 DEBUG 目录，不是用户目录迁移或真实授权验收；Android 真机因无设备继续暂缓。冷启动及部分显式保存的同步 I/O、文件级最后写入冲突仍是既有限制。

## v1.2.5 发布记录（2026-10-23）

- 版本：macOS **1.2.5 (9)**、Widget **1.2.5 (9)**、iOS **1.2.5 (4)**、Android **1.2.5 (versionCode 5)**。界面与 v1.2.4 相同，不含视觉改造；清新方向仅存于 `sketches/fresh-ui/` 预览。
- 发布前回归：Apple fixtures **4 cases / 88 assertions PASS**（file_monitor 24、foreground_recovery 21、dirty_reload 14、qishi_audio 29）；Android **36/36 PASS**（JDK 21、`--no-download`）。
- 产物核验：Mac universal arm64+x86_64、Widget 与 DMG 内 App 均 strict 签名通过，DMG 挂载版本 1.2.5/9；iOS IPA 版本 1.2.5/4；Android APK versionCode 5，含 15 个音频资源（14 MP3 + `qishi_presets.json`），debug 签名。三份包内未发现运行设置/凭据 JSON。
- SHA-256：DMG `ed33c6c5f9418cc4526a09a00d50f4142c565e9d0e7a931e7bd5f57ba63f5261`；IPA `df9e6bd35bc9fa27070e2ce83829a40c20199b188853a5f40f2fae3a39e73a9e`；APK `b30bc8ddf52e44a9db48da67abfaba8e2970e0464ff7804fc54831be90ab3230`。
- 边界：这三份产物没有安装到本机 Mac、手机或 Android 设备；真实 iCloud 传送、Habitica 在线链路、锁屏后台音频及长期使用仍未验收。Apple fixtures 与 Android 回归均为离线验证，不等于在线上/设备上通过。
