# Habitica Pomodoro Android

macOS / iOS 版 Habitica Pomodoro 的 Android 客户端。Kotlin + Jetpack Compose 原生实现，业务规则与另外两端一致（Habitica API、逻辑日、Task 分类上限、计分时机均从 Swift 端逐条对齐）。

## 功能（v1.0 MVP）

四个底部 Tab：

| Tab | 内容 |
|-----|------|
| **Pomo** | 圆环计时器（点击圆环启动/暂停）、开始/暂停/跳过休息/结束、今日番茄数、本组进度、Habitica 金币/等级/血量速览 |
| **Task** | 每日三件事 + 琐事：Work/MyOwn 各限 3 条、Chores 自由列表；今天可增删改勾选，昨天只读，未完成任务 ➡️ 顺延到今天；分类可重命名 |
| **Role** | Habitica 角色面板：HP/MP/EXP/GP、STR/CON/INT/PER 四维、streak/完美天数/任务总数、注册时间 |
| **设置** | Habitica 凭据（Token 密文显示+测试连接）、番茄/休息时长、手动休息、音量、数据存储说明 |

- **后台计时**：前台服务 + 常驻通知（暂停/继续/结束直接在通知栏操作），基于绝对结束时刻（phaseEndsAt）计算，回前台自动校正；WakeLock 保证锁屏不冻结
- **阶段结束提醒**：高优先级通知（锁屏横幅），Android 13+ 首次启动请求通知权限
- **Habitica 同步**：Task 任务 ↔ todo、分类名 ↔ tag（自动创建/重命名/删除）、完成/取消实时打分、番茄结束按设置计分

## 数据同步（与 Mac/iPhone 的关系）

- **任务数据三端一致**：经 Habitica 云端（todo + tag + 打分），任何一端完成，其他端刷新即见
- **本机设置/番茄历史**：存应用私有目录 `files/.habitica-pomodoro/`（文件名与 Mac/iOS 相同的 5 个 JSON），随 Android 系统云备份/换机迁移
- Android 无法访问 iCloud Drive（Apple 不向非苹果平台开放该目录），因此 Mac↔iPhone 之间的 iCloud 文件同步不适用于 Android；这是平台限制，非本应用缺陷

## 构建与运行

```bash
# 依赖：JDK 21（brew install openjdk@21）+ Android SDK（platform-tools / platforms;android-35 / build-tools;35.0.0）
bash build_android.sh           # debug APK → app/build/outputs/apk/debug/app-debug.apk
bash build_android.sh release   # release APK（无 keystore.properties 时用 debug 签名，可直接安装）

# 安装到 USB 连接的手机/模拟器
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

正式签名（发布用）：在项目根目录创建 `keystore.properties`（不入库）：

```properties
storeFile=/path/to/release.keystore
storePassword=***
keyAlias=habitica
keyPassword=***
```

## 代码结构

```
build_android.sh               # 构建脚本
app/src/main/java/com/habitica/pomodoro/
├── MainActivity.kt            # 入口、底部导航、通知权限、回前台重同步
├── data/
│   ├── Models.kt              # 数据模型（JSON 字段与 Swift Codable 逐字一致）
│   ├── HabiticaAPI.kt         # Habitica REST（x-client header、dailys 拼写等约定同 Swift 端）
│   └── LocalStore.kt          # 本地 JSON 存储 + 逻辑日计算
├── engine/PomodoroViewModel.kt # 计时引擎（绝对结束时刻）+ Task/Habitica 业务
├── service/PomodoroTimerService.kt # 前台服务计时 + 通知控制
└── ui/
    ├── PomoScreen.kt          # 番茄主页（圆环计时器）
    ├── TaskScreen.kt          # Task 页（今天/昨天、分类、顺延）
    ├── RoleScreen.kt          # Role 页（角色面板）
    ├── SettingsScreen.kt      # 设置页
    └── theme/Theme.kt         # 番茄红主题
```

## 与 Swift 端对齐的业务规则（改代码前先读）

- 逻辑日边界 = 第一个时间块起点（默认 04:00），凌晨 02:00 算"昨天"
- Work/MyOwn（前 2 个分类）各限 3 条；第 3 个分类起（Chores）自由列表
- Dailies 类型参数必须是 `dailys`（不是 dailies）
- Role：maxHealth 固定 50；maxMP = 30 + 3*(level-1) + INT/2；注册时间在 `auth.timestamps`
- 完成任务 score up、取消完成 score down、删除任务同步删 todo
- Habitica task id 存 UUID 大写连字符格式，与 Swift 端序列化一致
