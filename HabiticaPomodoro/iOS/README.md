# Habitica Pomodoro iOS

macOS 版 Habitica Pomodoro 的 iOS 客户端，与 Mac 版共享同一套核心代码（引擎 / 数据 / Habitica API / 视图），通过 `#if os(iOS)` 与跨平台兼容层适配移动端。

## 功能（v1.0 MVP）

- **Pomo**：番茄计时（点击圆圈启动/暂停）、暂停/跳过休息/结束、今日番茄数、时间块进度（Block Mode 开启时）、Habitica 金币/经验/血量
- **Task**：每日三件事（Work / MyOwn，各 3 件）+ 琐事自由列表；今天可编辑、昨天只读归档、未完成任务一键 ➡️ 顺延到今天；任务与分类 tag 双向同步 Habitica todo
- **Role**：Habitica 角色面板（头像、职业等级、HP/MP/EXP、金币、四维属性、成就）
- **Settings**：Habitica 凭据、番茄时长、计分开关、提示音与音量、时间块配置

## 与 Mac 版的数据关系

- iOS 数据存于**应用沙盒** `Documents/.habitica-pomodoro/`（文件名与 Mac 版一致）
- 任务通过 **Habitica 云端**跨端一致（todo + tag）
- iOS 沙箱无法直接读写 Mac 的 `~/Documents`，两端本地 JSON 不直接互通（不做 iCloud 容器共享，避免开发者账号/entitlement 配置）

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
├── MobileSettingsView.swift         # 原生 Form 风格设置页
└── Assets.xcassets/                 # 图标
HabiticaPomodoro/              # 与 Mac 版共享
├── PomodoroEngine.swift       # 计时引擎（含 iOS 后台重同步）
├── Managers.swift             # 数据管理 + iCloud Drive/沙盒文件存储
├── HabiticaAPI.swift          # Habitica REST API
├── TopThreeView.swift         # Task 页（跨平台共用）
├── HabiticaTabsView.swift     # Role/Habits/Dailies 视图（跨平台共用）
└── PlatformCompat.swift       # 跨平台兼容垫片
```
