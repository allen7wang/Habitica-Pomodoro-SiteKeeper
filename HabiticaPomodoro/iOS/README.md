# Habitica Pomodoro iOS

macOS 版 Habitica Pomodoro 的 iOS 客户端，与 Mac 版共享同一套核心代码（引擎 / 数据 / Habitica API / 视图），通过 `#if os(iOS)` 与跨平台兼容层适配移动端。

## 数据同步（iCloud Drive 文件）

仅授权共享目录后，iOS 才与 Mac 读写 iCloud Drive `Documents/.habitica-pomodoro/` 下的同一批 JSON。五个既有文件保存设置、块进度/历史和 Task；独立 `habitica_pomodoro_plants.json` 保存种植，新增独立 `habitica_pomodoro_histogram.json` 保存番茄数量和实际完成分钟。七类文件全部接入目录发现、保存、reload 与前台变更检测；未授权时数据在应用沙盒。

### 首次连接（一次性操作）

1. 打开 Settings → **iCloud Drive 同步** → 点「选择 iCloud Drive 文件夹…」
2. 在 Files 选择器中选 **iCloud Drive → Documents**（注意：`.` 开头的隐藏文件夹在 Files 里不可见，选它的父目录即可，App 会自动定位/创建里面的 `.habitica-pomodoro`）
3. 授权后数据立即从云端加载；此后每次启动自动恢复，无需再选

### 技术实现

- iOS 沙箱不允许直接读写 iCloud Drive 根目录，走 **UIDocumentPicker（fileImporter）+ 普通 bookmark 持久化**：用户选一次目录 → security-scoped URL → 存 bookmark → 冷启动 resolve 恢复。无需 entitlement、无需付费开发者账号。
- 授权范围递归覆盖子目录（含隐藏目录），bookmark 失效（文件夹被移动/权限被撤销）时 UI 会提示重新选择。
- 未授权时回退 App 沙箱，仍可用；配置 Habitica 后任务有独立云端通道，但不代表专注/块/植物历史已同步。文件级最后写入生效，同时编辑可能覆盖。「立即保存全部数据」只写文件，传送由 iCloud 系统负责。
- 本轮已用 scratch 探针验证选择 iCloud 根或其 Documents 父目录时，Histogram 单独存在也能发现同一数据目录；真实 fileImporter 授权、冷启动 bookmark、跨设备系统传送仍须真机人工验收。

## 功能（当前源码，尚未发布新版 iOS Release）

- **Pomo**：启动、暂停/继续、放弃/跳到休息、手动/自动短长休息与延长、空闲时 1/5/15/30 分钟自选休息；1–24 块的 timeline/Current、目标/跨午夜时段/任务编辑与预计番茄数；🌿 完成、🥀 放弃、🌳 combo、○ 空位；达标同一天同一块只记一次历史/奖励
- **Task**：Work/MyOwn 各最多新增 3 条，Chores 不限；统一新增、修改标题、完成/取消、确认删除、分类改名；昨日只读及未完成任务顺延；todo/tag 出站、应用专用 dated Top3 todo 入站；普通 todo 不导入，失败保留本机，待上传修改/删除标记阻止旧响应覆盖。按 UID＋规范 HTTPS API 根保存每个账号的 UUID/远端映射/tag/待同步修改与删除队列，其他账号不执行这些操作；回切保留映射，同账号 Token 轮换不改变归属
- **Habits / Dailies**：读取并打分/勾选，刷新及错误提示；同一任务请求期间阻止重复操作，切换账号时清旧列表并拒绝旧响应
- **Role**：角色属性、成就、请求状态、刷新和失败提示；账号切换拒绝旧响应
- **历史**：今天/累计/日均番茄与专注分钟/小时、近期图表、时间块及植物历史；旧统计从原 UserDefaults 备份迁移到独立 JSON，已有不可读文件不在初始化时覆盖
- **Settings**：Habitica、计时/组合/计分、默认或自定义 Habit ID、短长休息消息提醒、块奖励/开始/冲刺提醒、真实打包音效/环境音/独立音量/预听、重置与分别清理、iCloud Drive 父目录授权；未实现的旧开关不显示但保留解码字段。自定义服务会收到凭据，只接受 HTTPS API 根地址，并禁止自动跟随重定向

## 与 Mac 版的数据关系

- **授权共享目录后**：Mac/iPhone 读写同一目录下七类文件（包括独立 Histogram/Plant），前台重载变更。目录授权成功不证明系统传送已完成。Android 本机历史不会通过此授权共享。
- **未授权时**：iOS 回退应用沙盒 `Documents/.habitica-pomodoro/`，任务仍可经 Habitica 云端上传 todo/tag
- 不依赖 iCloud 容器/entitlement/开发者账号，只靠文档选择器的一次性授权 + bookmark 持久化

Task 使用第一个块起点的逻辑日（默认 04:00）；统计、时间块及植物保留自然日 `yyyy-MM-dd`，不重归档旧记录。

iPhone 原生 TabView 超过五个目的地时，Role/Settings 在 **More**，不是缺少页面。

## 构建与运行

```bash
# 依赖: Xcode 16+、xcodegen (brew install xcodegen)
bash build_ios.sh              # 生成工程 → 编译 → 安装并启动到 iPhone 17 模拟器
bash build_ios.sh --no-install # 仅编译
SIM_NAME="iPhone Air" bash build_ios.sh   # 指定其他模拟器
```

工程文件 `HabiticaPomodoroMobile.xcodeproj` 由 `project.yml`（xcodegen）生成，**不入库**；改文件列表请改 `project.yml`。

### 真机部署

1. `open HabiticaPomodoroMobile.xcodeproj`
2. Target → Signing & Capabilities → Team 选你的 Apple ID（免费账号即可，7 天有效需重签）
3. 连接 iPhone，选为运行目标，⌘R

## iOS 专属适配

| 问题 | 方案 |
|------|------|
| 后台 Timer 被系统挂起 | `phaseEndsAt` 绝对时刻；回前台补处理过期专注→休息→延长，不产生无人操作的下一轮专注；观察到时钟后退时不补回已消耗秒数。后台不能承诺实时 Habitica 计分 |
| 锁屏/后台无提醒 | 启动番茄时预排 `UNTimeIntervalNotificationTrigger`；Block Mode 开始前提醒使用每日重复的 `UNCalendarNotificationTrigger`，设置变更时重排，不依赖后台运行的计时器 |
| 通知权限弹窗打扰启动 | 懒加载：首次点击开始番茄时才请求权限 |
| 静音开关吞掉提示音 | `AVAudioSession` 设为 `.playback + .mixWithOthers` |
| macOS-only API | `PlatformCompat.swift` 提供 `Color.cardBackground` / `cancelOnExitCommand` 等跨平台垫片 |

## 代码结构

```
project.yml                    # xcodegen 工程定义（唯一事实源）
build_ios.sh                   # 构建脚本
iOS/                           # iOS 专属代码
├── HabiticaPomodoroMobileApp.swift  # 入口、AppDelegate、底部 TabView
├── MobilePomoView.swift             # 番茄主页 + 时间块种植
├── MobileBlockTimelineView.swift    # 水平 timeline / Current / 编辑导航
├── MobileBlockEditorView.swift      # 时间块目标/时段/任务编辑
├── MobileHistoryView.swift          # 专注统计与块历史
├── MobileSettingsView.swift         # 原生 Form 风格设置页（含 iCloud Drive 同步区块）
├── ICloudFolderGrant.swift          # iCloud Drive 文件夹授权（fileImporter + bookmark 持久化）
└── Assets.xcassets/                 # 图标
HabiticaPomodoro/              # 与 Mac 版共享
├── PomodoroEngine.swift       # 计时引擎（含 iOS 后台重同步）
├── Managers.swift             # 数据管理 + iCloud Drive/沙盒文件存储
├── PlantJournal.swift         # Mac/iOS 共用植物记录（独立 JSON）
├── HabiticaAPI.swift          # Habitica REST API
├── TopThreeView.swift         # Task 页（跨平台共用）
├── HabiticaTabsView.swift     # Role/Habits/Dailies 视图（跨平台共用）
└── PlatformCompat.swift       # 跨平台兼容垫片
```

## 本轮验证与手测清单

当前制作 **1.2.3 / build 2 本地测试版**；版本配置已更新，第三轮定向修复、新产物构建和独立审查尚在进行。下列旧构建/探针仅作前轮基线，不表示新版已完成验收。

实际完成 iOS Simulator Debug 构建、macOS arm64/x86_64 编译和 scratch 离线状态/持久化探针。早期专用模拟器已安装启动，Pomo 截图包含计时圈、控制、自选休息、历史入口和原生 More。后续详细页面验证遇到模拟器启动超时 / LaunchdSimError 111，**白屏不能证明 Settings 布局已验收**。

本轮未提交或发布，没有真实 Habitica 账号、没有授权真实 iCloud 目录；探针只用离线模拟记录，不新增测试框架或仓库测试文件。按 `FEATURE_PARITY.md` 人工验收：

- [ ] 圆圈启动/暂停/继续；暂停休息后恢复仍是休息；放弃/跳过不计完成。
- [ ] 手动/自动短休息、combo 长休息、自选休息；0 延长、延长后保留/清 combo。
- [ ] 块数 1→24→1→24 保留目标/任务；Current、跨午夜时段、块任务编辑/预计数/完成/删除。
- [ ] 达标去重、重置当前块不重复奖励；清块/植物与清统计不误删 Task。
- [ ] Task 增改完成删除、分类改名、跨 04:00 日界及昨日顺延。
- [ ] 测试账号验证 Habits/Dailies/Role、Top3 双向合并、请求中修改/删除/账号切换。
- [ ] 真机声音/环境音/音量、暂停结束停止环境音、锁屏提醒与后台恢复。
- [ ] 真机 iCloud 根/其 Documents 两种父目录授权、冷启动 bookmark、Mac/iPhone Histogram/Plant 新文件前台重载与系统传送。
