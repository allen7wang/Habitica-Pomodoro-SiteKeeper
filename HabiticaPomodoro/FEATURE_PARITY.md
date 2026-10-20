# 桌面与移动端功能对齐验收清单

> 本轮目标：macOS、iOS、Android 的业务功能与记录规则一致，不要求把桌面布局机械复制到手机。当前正在实施，本文是验收标准，**不是全部已通过的验证报告**。本轮不包含手表端，不提交或发布版本。

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
- 未提交、推送或发布。
