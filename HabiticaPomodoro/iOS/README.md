# Habitica Pomodoro iOS

macOS 版 Habitica Pomodoro 的 iOS 客户端，与 Mac 版共享同一套核心代码（引擎 / 数据 / Habitica API / 视图），通过 `#if os(iOS)` 与跨平台兼容层适配移动端。

## 数据同步（iCloud Drive 文件）

iOS 与 Mac 版读写**同一批 JSON 文件**（settings / block_progress / block_history / daily_blocks / top_three 共 5 个），存放在 iCloud Drive 的 `Documents/.habitica-pomodoro/` 隐藏文件夹。

### 首次连接（一次性操作）

1. 打开 Settings → **iCloud Drive 同步** → 点「选择 iCloud Drive 文件夹…」
2. 在 Files 选择器中选 **iCloud Drive → Documents**（注意：`.` 开头的隐藏文件夹在 Files 里不可见，选它的父目录即可，App 会自动定位/创建里面的 `.habitica-pomodoro`）
3. 授权后数据立即从云端加载；此后每次启动自动恢复，无需再选

### 技术实现

- iOS 沙箱不允许直接读写 iCloud Drive 根目录，走 **UIDocumentPicker（fileImporter）+ 普通 bookmark 持久化**：用户选一次目录 → security-scoped URL → 存 bookmark → 冷启动 resolve 恢复。无需 entitlement、无需付费开发者账号。
- 授权范围递归覆盖子目录（含隐藏目录），bookmark 失效（文件夹被移动/权限被撤销）时 UI 会提示重新选择。
- 未授权时回退 App 沙箱本地存储，App 始终可用；任务数据仍经 Habitica 云端同步。
- 已验证链路（模拟器端到端）：grant → 冷启动 resolve → 数据目录改道 → Settings/TopThree 读写全部落在授权目录。

## 功能（v1.0 MVP）

- **Pomo**：番茄计时（点击圆圈启动/暂停）、暂停/跳过休息/结束、今日番茄数、时间块进度（Block Mode 开启时）、Habitica 金币/经验/血量
- **Task**：每日三件事（Work / MyOwn，各 3 件）+ 琐事自由列表；今天可编辑、昨天只读归档、未完成任务一键 ➡️ 顺延到今天；任务与分类 tag 双向同步 Habitica todo
- **Role**：Habitica 角色面板（头像、职业等级、HP/MP/EXP、金币、四维属性、成就）
- **Settings**：Habitica 凭据、番茄时长、计分开关、提示音与音量、时间块配置

## 与 Mac 版的数据关系

- **授权 iCloud Drive 后**：iOS 与 Mac 读写**同一批 JSON 文件**（`Documents/.habitica-pomodoro/` 下 5 个文件），双端数据实时互通
- **未授权时**：iOS 回退应用沙盒 `Documents/.habitica-pomodoro/`（文件名一致），任务仍经 **Habitica 云端**跨端一致（todo + tag）
- 不依赖 iCloud 容器/entitlement/开发者账号，只靠文档选择器的一次性授权 + bookmark 持久化

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
| 后台 Timer 被系统挂起 | 引擎记录 `phaseEndsAt` 绝对结束时刻，回前台 `resyncAfterForeground()` 按真实时间校正；后台跨过结束点会补触发结束逻辑（Habitica 计分、进休息） |
| 锁屏/后台无提醒 | 启动番茄时预排一条 `UNTimeIntervalNotificationTrigger` 本地通知，阶段结束准点弹出；提前暂停/结束会取消 |
| 通知权限弹窗打扰启动 | 懒加载：首次点击开始番茄时才请求权限 |
| 静音开关吞掉提示音 | `AVAudioSession` 设为 `.playback + .mixWithOthers` |
| macOS-only API | `PlatformCompat.swift` 提供 `Color.cardBackground` / `cancelOnExitCommand` 等跨平台垫片 |

## 代码结构

```
project.yml                    # xcodegen 工程定义（唯一事实源）
build_ios.sh                   # 构建脚本
iOS/                           # iOS 专属代码
├── HabiticaPomodoroMobileApp.swift  # 入口、AppDelegate、底部 TabView
├── MobilePomoView.swift             # 番茄主页（触屏大按钮）+ 时间块列表
├── MobileSettingsView.swift         # 原生 Form 风格设置页（含 iCloud Drive 同步区块）
├── ICloudFolderGrant.swift          # iCloud Drive 文件夹授权（fileImporter + bookmark 持久化）
└── Assets.xcassets/                 # 图标
HabiticaPomodoro/              # 与 Mac 版共享
├── PomodoroEngine.swift       # 计时引擎（含 iOS 后台重同步）
├── Managers.swift             # 数据管理 + iCloud Drive/沙盒文件存储
├── HabiticaAPI.swift          # Habitica REST API
├── TopThreeView.swift         # Task 页（跨平台共用）
├── HabiticaTabsView.swift     # Role/Habits/Dailies 视图（跨平台共用）
└── PlatformCompat.swift       # 跨平台兼容垫片
```
