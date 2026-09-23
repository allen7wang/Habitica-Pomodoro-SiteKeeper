# Habitica Pomodoro (macOS + iOS)

一款原生番茄钟应用（macOS 菜单栏 + iOS 客户端，共享同一套核心代码），深度集成 [Habitica](https://habitica.com)，并独创 **智能时间块（Block Mode）** 与 **每日三件事（Top 3）** 功能，帮你把一天组织成可执行、可回顾的节奏。

基于 [ofekmiz/Habitica-Pomodoro-SiteKeeper](https://github.com/ofekmiz/Habitica-Pomodoro-SiteKeeper) Chrome 扩展的 macOS 原生重制与增强版。

**双端数据同步**：Mac 与 iPhone/iPad 登录同一 Apple ID 时，通过 iCloud Drive 读写**同一批 JSON 数据文件**（`Documents/.habitica-pomodoro/`），设置、任务、时间块进度、历史全部双向同步；任务另经 Habitica 云端（todo + tag）跨端一致。

## 功能特性

### 🍅 番茄钟核心
- 菜单栏实时倒计时显示（与番茄数交替展示）
- 点击圆圈开始 / 暂停 / 跳过休息 / 提前结束
- 自定义番茄时长、短休息、长休息、番茄组数量
- 完成 / 失败自动同步 Habitica habit（+ / -）
- 结束音效、环境音（雨声、鸟鸣、蟋蟀、钟声）

### 🧱 智能时间块 (Block Mode)
- 将一天划分为 8 个时间块（时间段可自定义，默认 04:00 起每 3 小时一块）
- 每块设定目标（Block Goal）与任务清单
- 可视化时间轴：横向卡片展示 B1–B8，当前块橙色高亮，支持 "Current" 按钮一键定位居中
- 块内番茄进度追踪（如 4/6），主界面圆点直观展示
- 块完成自动 Habitica 奖励 + 休息建议
- 智能提醒：块开始前 5 分钟提醒、块进度冲刺提醒（可配置）
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
- 借助 iCloud Drive「桌面与文稿」同步能力，自动在多设备间同步，无需登录授权、无需开发者账号
- UserDefaults 本地双备份，数据永不丢失

### 📊 统计
- 每日番茄数 / 专注时长直方图
- Habitica 金币、经验、血量实时展示

## 系统要求

| 平台 | 要求 |
|------|------|
| macOS | 13.0+，Universal 二进制（Apple Silicon + Intel） |
| iOS | 16.0+，iPhone（iPad 未适配布局） |

## 安装 — macOS

1. 从 [Releases](https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper/releases) 下载 `HabiticaPomodoro-Installer.dmg`
2. 打开 DMG，将应用拖入 Applications
3. 首次打开如提示无法验证开发者：右键应用 → 打开，或在「系统设置 → 隐私与安全性」中允许
4. 在 Settings → Habitica 中填入你的 User ID 与 API Token（Habitica 网站 → Settings → API）

## 安装 — iOS

> ⚠️ **iOS 无法像 macOS 那样"下载即装"。** App Store 上架需要付费开发者账号（$99/年），本项目没有，因此 Release 里的 `.ipa` 是**未签名**的，必须用你自己的 Apple ID 重签后才能装到手机。

### 方式 A：源码构建（推荐，免费 Apple ID 即可）

需要一台装了 Xcode 16+ 的 Mac。

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

从 Release 下载 `HabiticaPomodoro-iOS-unsigned.ipa`，用 [AltStore](https://altstore.io) / [Sideloadly](https://sideloadly.io) 等工具以你自己的 Apple ID 重签后安装。同样受 7 天有效期限制（AltStore 可自动续签）。

> 出于隐私考虑，Release 不提供已签名的 .ipa —— 已签名版本内嵌开发者 Team ID 与被授权设备的 UDID，且只能在那一台设备上安装。

### 安装后：连接 iCloud Drive（与 Mac 同步）

打开 App → **Settings → iCloud Drive 同步 → 选择 iCloud Drive 文件夹…** → 在文件选择器里选 **iCloud Drive → Documents**

- `.habitica-pomodoro` 是隐藏文件夹，iOS 的「文件」App 看不到它，**只需选它的父目录**（选 iCloud Drive 根或 Documents 都可以，App 会自动定位）
- 连接成功后会显示「✅ 已找到 5 个数据文件，与 Mac 版共用同一份数据」
- Mac 端需已开启 iCloud「桌面与文稿」同步（系统设置 → Apple ID → iCloud → iCloud 云盘）
- 不连接也能用：数据存本机沙箱，任务仍通过 Habitica 云端跨端同步

## 使用说明

- 应用常驻菜单栏：未运行时显示时钟图标，运行时交替显示倒计时与块进度
- 点击菜单栏图标打开主窗口
- 主窗口分五个 Tab：**Pomo**（番茄钟 + 时间块）/ **Task**（每日三件事 + 琐事）/ **Habits**（习惯打分）/ **Dailies**（每日打卡）/ **Role**（角色面板）

### ⌨️ 快捷键

| 按键 | 功能 |
|------|------|
| ⌘1 – ⌘5 | 切换到 Pomo / Task / Habits / Dailies / Role |
| ⌘⇧P | 启动 / 暂停番茄（进行中→暂停，已暂停→继续，空闲→启动） |
| ⌥⌘P | 全局热键：激活番茄钟（应用不在前台也可用） |

## 构建

```bash
cd HabiticaPomodoro

# macOS
bash build.sh        # 产物: HabiticaPomodoro.app + HabiticaPomodoro-Installer.dmg（swiftc 直接编译，无需 Xcode 工程）

# iOS（需 Xcode + xcodegen）
bash build_ios.sh    # 生成工程 → 编译 → 安装到 iPhone 17 模拟器；详见 iOS/README.md
```

## License

与原项目保持一致。
