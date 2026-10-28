# Habitica Pomodoro (macOS + iOS + Android)

一款原生番茄钟应用（macOS 菜单栏 + iOS / Android 客户端，目标是统一业务规则），深度集成 [Habitica](https://habitica.com)，并独创 **智能时间块（Block Mode）** 与 **每日三件事（Top 3）** 功能，帮你把一天组织成可执行、可回顾的节奏。

基于 [ofekmiz/Habitica-Pomodoro-SiteKeeper](https://github.com/ofekmiz/Habitica-Pomodoro-SiteKeeper) Chrome 扩展的 macOS 原生重制与增强版。

**Mac ↔ iPhone 数据同步**：Mac 与 iPhone 登录同一 Apple ID 并在 iOS 授权 iCloud Drive 文件夹后，读写 `Documents/.habitica-pomodoro/` 中的七类 JSON 数据文件。系统负责跨设备传送，同时编辑仍可能最后写入覆盖。Android 无法读取该 iCloud 目录，只经 Habitica todo 导入已上传、带应用日期与分类标记的 Top 3 任务；纯本地任务、设置及历史不通过 Habitica 同步。

> **版本状态（2026-10-28）**：macOS **[v1.2.7](https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper/releases/tag/v1.2.7)** 补齐任务、习惯、每日、角色四页的三套皮肤与深浅色适配，工作台采用任务日期与角色信息分栏，修复花园风格滚动与留白。右上角调色板或 设置 → 外观 可切换风格。iOS / Android 仍为 v1.2.5，业务与同步逻辑未改。

## 功能特性

### 🍅 番茄钟核心
- 菜单栏实时倒计时显示（与番茄数交替展示）
- 点击圆圈开始 / 暂停 / 继续；放弃为独立操作，暂停不会被记成失败
- 自定义番茄时长、短休息、长休息、番茄组数量
- 完成 / 失败自动同步 Habitica habit（+ / -）
- 结束音效、环境音（自定义雨声/鸟鸣/蟋蟀/钟声，或栖时 73 场景随机混音）
- 栖时模式每个番茄随机且避开上次场景；本轮 Apple 修复暂停后同场景/同播放器继续，以及设置试听与专注分离
- 仅清单随包：Mac 优先读取本机栖时仓库音频，不存在时流式；iOS/Android 从公开站流式，需要联网

### 🧱 智能时间块 (Block Mode)
- 时间块数量可设为 1–24（默认 8 块，04:00 起每 3 小时一块），每块 1–12 个番茄；支持跨午夜时段
- 每块设定目标（Block Goal）与任务清单
- 可视化时间轴：横向卡片展示 B1–B8，当前块橙色高亮，支持 "Current" 按钮一键定位居中
- 块内番茄进度追踪（如 4/6）；macOS 首页 B1–B8 的种植位：空圆点表示尚未种植，完成一个 Pomo 长一棵灌木 🌿，中途放弃或跳过显示枯萎 🥀；完成一个 combo 还会在同排末尾额外长一棵树 🌳（不替代灌木）
- 种植记录按天保存在 `habitica_pomodoro_plants.json`，位于 Mac/iPhone 共用的 iCloud Drive 数据目录；与时间块进度文件分开。三端 v1.2.4 均已包含种植位，Android 记录保存在本机
- 块完成自动 Habitica 奖励 + 休息建议
- 智能提醒：块开始前提醒（提前 1–60 分钟可配）、块进度冲刺提醒
- 每日块记录持久化，支持历史回看

### ⭐ Top 3 — 每日最重要的三件事
- 独立 Task 页，分 **Work / MyOwn / Chores（琐事）** 三类（分类名可自定义）
- 三类交互统一：底部输入行添加（回车确认）、点击文字编辑、点击圆圈完成、删除（带确认）
- Work / MyOwn 每类上限 3 件；琐事为自由列表不限数量
- 昨天未完成的任务可一键 ➡️ 移动到今日对应分类
- 仅展示今天与昨天；昨天的记录自动归档、不可修改
- **逻辑日**：一天的起点 = 第一个时间块的启动时间（默认 04:00），熬夜时段（00:00–04:00）仍归属前一天

### 🔄 Habitica 任务同步
- 每条任务自动同步为 Habitica **todo**，分类名自动作为 **tag**
- 应用内完成/取消、改标题、删除任务、重命名分类，均实时同步到 Habitica
- 未配置凭据时静默跳过，仅本地存储

### 🎮 Habitica 集成页（Habits / Dailies / Role）
- **Habits**：习惯列表，行内 +/- 直接打分，按任务 value 健康度着色排序（弱项在前）
- **Dailies**：每日打卡清单，勾选完成实时同步
- **Role**：角色面板 —— 头像、用户名、职业与等级，HP/MP/EXP 进度条，金币，STR/CON/INT/PER 四维属性，连续完美天数等成就统计

### ☁️ 数据存储与同步
- 所有数据以 JSON 文件存储于 `~/Documents/.habitica-pomodoro/`（隐藏文件夹）
- Mac 借助 iCloud Drive「桌面与文稿」同步；iPhone 需先在应用内授权同一父目录。无需付费开发者账号，不代表 Android 可以共享该目录
- Mac/iOS 的 UserDefaults 提供本机兜底备份；文件同步并不保证无冲突，同时在多台设备修改同一文件仍可能按最后写入覆盖

### 📊 统计
- 每日番茄数 / 专注时长直方图
- Habitica 金币、经验、血量实时展示

## 系统要求

| 平台 | 要求 |
|------|------|
| macOS | 13.0+，Universal 二进制（Apple Silicon + Intel） |
| iOS | 16.0+，iPhone（iPad 未适配布局） |
| Android | 8.0+（API 26），Kotlin + Jetpack Compose 原生 |

## 安装 — macOS

1. 从 [Releases](https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper/releases) 下载 `HabiticaPomodoro-Installer.dmg`
2. 打开 DMG，将应用拖入 Applications
3. 首次打开如提示无法验证开发者：右键应用 → 打开，或在「系统设置 → 隐私与安全性」中允许
4. 在 Settings → Habitica 中填入你的 User ID 与 API Token（Habitica 网站 → Settings → API）

## 安装 — iOS

> ⚠️ **iOS 无法像 macOS 那样"下载即装"。** App Store 上架需要付费开发者账号（$99/年），本项目没有，因此 Release 里的 `.ipa` 是**未签名**的，必须用你自己的 Apple ID 重签后才能装到手机。

### 方式 A：源码构建（推荐，免费 Apple ID 即可）

需要一台装了 Xcode 16+ 的 Mac。已有签名环境时，可连接并解锁 iPhone，在 `HabiticaPomodoro` 目录运行 `bash resign_ios.sh` 重签覆盖安装；该命令会操作所有已连接的实体 iPhone，详情见 [iOS 说明](iOS/README.md)。

```bash
git clone https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper.git
cd Habitica-Pomodoro-SiteKeeper/HabiticaPomodoro
brew install xcodegen
xcodegen generate    # 由 project.yml 生成 Xcode 工程（工程文件不入库）
open HabiticaPomodoroMobile.xcodeproj
```

模拟器快速验证（构建 + 安装 + 启动一步到位）：

```bash
bash build_ios.sh              # 安装到 iPhone 17 模拟器
bash build_ios.sh --no-install # 仅编译
```

在 Xcode 里装到真机：

1. 打开 `HabiticaPomodoroMobile.xcodeproj`
2. Target `HabiticaPomodoroMobile` → **Signing & Capabilities**
3. 勾选 *Automatically manage signing*，**Team** 选你的 Apple ID（没有就先 Add Account 登录一个免费的）
4. Bundle Identifier 若提示被占用，改成你自己的唯一值，如 `com.yourname.habitica-pomodoro`
5. 数据线连 iPhone，解锁并信任此电脑，**设置 → 隐私与安全性 → 开发者模式** 打开（需重启）
6. 顶部设备选你的 iPhone，按 **⌘R** 运行
7. 首次启动若闪退/提示未验证：**设置 → 通用 → VPN与设备管理** → 信任你的开发者证书

> 免费 Apple ID 签名的应用 **7 天后过期**，过期后重新 ⌘R 安装一次即可（数据不受影响）。付费开发者账号可签 1 年。

### 方式 B：未签名 .ipa + 第三方重签工具

从 `v1.2.5-ios` Release 下载 `HabiticaPomodoro-iOS-1.2.5-unsigned.ipa`（CI 收集时使用通用名 `HabiticaPomodoro-iOS-unsigned.ipa`），用 [AltStore](https://altstore.io) / [Sideloadly](https://sideloadly.io) 等工具以你自己的 Apple ID 重签后安装。同样受 7 天有效期限制（AltStore 可自动续签）。

> 出于隐私考虑，Release 不提供已签名的 .ipa —— 已签名版本内嵌开发者 Team ID 与被授权设备的 UDID，且只能在那一台设备上安装。

### 安装后：连接 iCloud Drive（与 Mac 同步）

打开 App → **Settings → iCloud Drive 同步 → 选择 iCloud Drive 文件夹…** → 在文件选择器里选 **iCloud Drive → Documents**

- `.habitica-pomodoro` 是隐藏文件夹，iOS 的「文件」App 看不到它，**只需选它的父目录**（选 iCloud Drive 根或 Documents 都可以，App 会自动定位）
- 连接成功后显示找到的数据文件数量；新版统一发现七类文件，植物和番茄统计使用独立 JSON 文件，尚未产生某类记录时对应文件可能尚不存在
- Mac 端需已开启 iCloud「桌面与文稿」同步（系统设置 → Apple ID → iCloud → iCloud 云盘）
- 不连接 iCloud 也能用：数据存 iOS 本机沙箱；已配置 Habitica 时，本机新建任务仍可上传为 todo

## 安装 — Android

1. 从 [Android v1.2.5 Release](https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper/releases/tag/v1.2.5-android) 下载 `HabiticaPomodoro-Android-1.2.5.apk`
2. 传到手机，点击安装（需允许「安装未知来源应用」）
3. 打开 App → 设置 → 填写 Habitica User ID 与 API Token

- APK 为 debug 签名构建（开源侧载分发，功能与正式签名无差异），无 7 天过期问题
- Android 新版源码的 Task 页可手动刷新 Habitica todo，并在启动、返回前台或更换账号后自动尝试导入 **Mac/iPhone 已上传且备注包含应用专用日期、分类标记** 的任务；通过 Habitica ID 合并标题与完成状态，不覆盖本机离线任务。纯本地任务及其他 Habitica todo 不会被导入；此在线同步尚未使用真实账号端到端验证
- Android 的设置/历史/植物保存在本机，不能通过 iCloud Drive 与 Mac/iPhone 同步
- Android 无法访问 iCloud Drive，因此 Mac↔iPhone 的 iCloud 文件同步不适用于 Android（平台限制）
- Android v1.2.5 已包含时间块/种植、Habits/Dailies、历史及栖时随机场景；真机验收因暂无设备暂缓，不能把发布或离线回归视作这些交互已实测

源码构建：

```bash
git clone https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper.git
cd Habitica-Pomodoro-SiteKeeper/HabiticaPomodoroAndroid
# 需要 JDK 21 + Android SDK（platform-tools / platforms;android-35 / build-tools;35.0.0）
bash build_android.sh            # debug APK
bash build_android.sh release    # release APK（无 keystore.properties 时用 debug 签名）
```

详见 [HabiticaPomodoroAndroid/README.md](../HabiticaPomodoroAndroid/README.md)。

## 使用说明

- 应用常驻菜单栏：未运行时显示时钟图标，运行时交替显示倒计时与块进度
- 点击菜单栏图标打开主窗口
- 主窗口分五个 Tab：**Pomo**（番茄钟 + 时间块）/ **Task**（每日三件事 + 琐事）/ **Habits**（习惯打分）/ **Dailies**（每日打卡）/ **Role**（角色面板）

### ⌨️ 快捷键

| 按键 | 功能 |
|------|------|
| ⌘1 – ⌘5 | 切换到 Pomo / Task / Habits / Dailies / Role |
| ⌘⇧P | 启动 / 暂停番茄（进行中→暂停，已暂停→继续，空闲→启动） |
| ⌥⌘P | 全局热键：启动 / 暂停 / 继续（应用不在前台也可用） |

## 构建

```bash
cd HabiticaPomodoro

# macOS（主程序 swiftc，Widget 需要 xcodegen + Xcode）
bash build.sh        # swiftc Universal .app 输出 ~/Library/Caches/HabiticaPomodoroBuild/；DMG 留在本目录

# iOS（需 Xcode + xcodegen）
bash build_ios.sh    # 生成工程 → 编译 → 安装到 iPhone 17 模拟器；详见 iOS/README.md
```

构建输出的 `.app` 位于 `~/Library/Caches/HabiticaPomodoroBuild/`，可用 `HABITICA_BUILD_OUTPUT` 指向其他**非 iCloud** 目录；不要运行旧的仓库内 `.app` 副本。iCloud FileProvider 会反复给包根附加 Finder 属性，DMG 封装不受该 `.app` 路径问题影响，仍输出 `HabiticaPomodoro-Installer.dmg`。

## 离线回归与 CI

从仓库根运行 `python3 HabiticaPomodoro/fixtures/run.py --work "$HOME/Library/Caches/HabiticaPomodoroFixtures"`，覆盖真实七文件重载/慢读/本地写竞争，以及 Apple 音频暂停和试听生命周期。音频 transport 为替身，不联网、不出声；详见 [fixtures/README.md](fixtures/README.md)。Android 套件及 JDK 21 配置见 [Android fixtures](../HabiticaPomodoroAndroid/fixtures/README.md)。

CI 已配置 master push、PR、tag 与手动触发；先安装依赖并运行两端离线套件，再生成 DMG/未签名 IPA/APK。远端结果以 GitHub Actions 实际记录为准；真实声音、锁屏后台、账号切换与 iCloud 系统传送仍需分别验收。

## License

与原项目保持一致。
