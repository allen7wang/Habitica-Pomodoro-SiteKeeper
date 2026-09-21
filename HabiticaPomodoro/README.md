# Habitica Pomodoro (macOS)

一款 macOS 原生菜单栏番茄钟应用，深度集成 [Habitica](https://habitica.com)，并独创 **智能时间块（Block Mode）** 与 **每日三件事（Top 3）** 功能，帮你把一天组织成可执行、可回顾的节奏。

基于 [ofekmiz/Habitica-Pomodoro-SiteKeeper](https://github.com/ofekmiz/Habitica-Pomodoro-SiteKeeper) Chrome 扩展的 macOS 原生重制与增强版。

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

### ☁️ 数据存储与同步
- 所有数据以 JSON 文件存储于 `~/Documents/.habitica-pomodoro/`（隐藏文件夹）
- 借助 iCloud Drive「桌面与文稿」同步能力，自动在多设备间同步，无需登录授权、无需开发者账号
- UserDefaults 本地双备份，数据永不丢失

### 📊 统计
- 每日番茄数 / 专注时长直方图
- Habitica 金币、经验、血量实时展示

## 系统要求

- macOS 13.0+
- Universal 二进制（Apple Silicon + Intel）

## 安装

1. 从 [Releases](https://github.com/allen7wang/Habitica-Pomodoro-SiteKeeper/releases) 下载 `HabiticaPomodoro-Installer.dmg`
2. 打开 DMG，将应用拖入 Applications
3. 首次打开如提示无法验证开发者：右键应用 → 打开，或在「系统设置 → 隐私与安全性」中允许
4. 在 Settings → Habitica 中填入你的 User ID 与 API Token（Habitica 网站 → Settings → API）

## 使用说明

- 应用常驻菜单栏：未运行时显示时钟图标，运行时交替显示倒计时与块进度
- 点击菜单栏图标打开主窗口
- 主窗口分两个 Tab：**Pomo**（番茄钟 + 时间块）/ **Task**（每日三件事）

## 构建

```bash
cd HabiticaPomodoro
bash build.sh
```

产物：`HabiticaPomodoro.app` 与 `HabiticaPomodoro-Installer.dmg`（swiftc 直接编译，无需 Xcode 工程）。

## License

与原项目保持一致。
