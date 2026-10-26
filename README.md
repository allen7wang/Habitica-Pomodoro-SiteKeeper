# Habitica Pomodoro / SiteKeeper

本仓库同时保留原始浏览器扩展，以及目前维护的 macOS、iOS、Android 原生番茄钟。原生应用包含番茄计时、时间块、种植记录、每日三件事、Habitica 集成与栖时随机场景背景音。

## 项目入口

| 模块 | 安装与开发说明 |
|---|---|
| macOS / 三端概览 | [HabiticaPomodoro/README.md](HabiticaPomodoro/README.md) |
| iOS / iCloud Drive 授权与重签 | [HabiticaPomodoro/iOS/README.md](HabiticaPomodoro/iOS/README.md) |
| Android | [HabiticaPomodoroAndroid/README.md](HabiticaPomodoroAndroid/README.md) |
| 业务规则、历次验证与待验收项 | [FEATURE_PARITY.md](HabiticaPomodoro/FEATURE_PARITY.md) |
| Apple 离线回归 | [Apple fixtures](HabiticaPomodoro/fixtures/README.md) |
| Android 离线回归 | [Android fixtures](HabiticaPomodoroAndroid/fixtures/README.md) |

## 版本与同步边界

- 2026-10-26 已发布 **macOS v1.2.6**：界面新增三套可切换风格（清新原生 / 留白花园 / 效率工作台），通过主窗口右上角调色板或 设置 → 外观 切换。iOS / Android 仍为 v1.2.5，界面改造尚未落地到移动端。
- v1.2.5 已包含云文件读取防卡顿、Apple 暂停/试听资源隔离、前台到期补记顺序修复及 CI/离线回归改进；macOS v1.2.6 在其基础上只改展示层。
- Mac/iPhone 授权同一 iCloud Drive 父目录后共享 JSON；Android 只经 Habitica 交换带应用日期/分类标记的 Task，设置与历史不做三端云同步。
- 首次使用自行配置 Habitica 凭据；不配置也可离线使用。发布物不应携带个人账号或运行数据。

## 开发与验证

```sh
# macOS：需要完整 Xcode 和 xcodegen（Widget 需 xcodebuild，只有 Command Line Tools 不够）
(cd HabiticaPomodoro && bash build.sh)
# iOS：仅编译，不安装或启动设备
(cd HabiticaPomodoro && bash build_ios.sh --no-install)
# Apple：隔离存储、无实际音频或 Habitica 请求
python3 HabiticaPomodoro/fixtures/run.py --work "$HOME/Library/Caches/HabiticaPomodoroFixtures"
# Android：先将 JAVA_HOME 指向 JDK 21，工具链可复用本机缓存
python3 HabiticaPomodoroAndroid/fixtures/run.py --work "$HOME/Library/Caches/HabiticaPomodoroAndroidFixtures"
```

CI 定义见 [build.yml](.github/workflows/build.yml)：master push、面向 master 的 PR、版本 tag 与手动触发；离线回归先于构建。当前修改尚未推送，远端是否绿色须在实际运行后确认。CI 收集构建产物，不自动发布 Release。离线通过不等于真实声音、设备后台、Habitica 在线流程或 iCloud 跨设备传播已验收。

## 原始浏览器扩展（历史说明）

以下保留上游扩展的功能、安装和调试说明；原生客户端请使用上方入口。

### Description:
This extension has two main features:

**1. "Pay to Pass" Website Blocker:**
Website Blocker that plugs into Habitica and limits you from visiting websites that you decide. You can decide to visit these sites by spending Habitica currency, which you'll earn by developing good habits and doing chores.

**2. Pomodoro Timer:**
Including a Pomodoro Timer.
You can read about the pomodoro technique here:
https://habitica.fandom.com/wiki/Pomodoro

During Pomodoro mode, all websites in the list are blocked, websites with cost 0 are blocked only during pomodoro.
A Pomodoro habit is created automatically for the user in Habitica, with an option in the extension settings to automatically score [+] or [-] of the habit when a Pomodoro is done successfully or fails accordingly.

### How to use:
After installing the extension, click on the icon at the top right to open the menu. In here, you must set your API Credentials. You can then block a site by navigating to it and clicking block site. It will ask you to enter a cost. From this point on, when you visit this site, the extension will ask you if you'd like to spend GP to access it. To start a pomodoro timer simply click on the Tomato character. Click again to stop the timer. In the settings you will find a lot of option that allow you tweak and change the pomodoro behavior to fit best for you.

-----------------------------------------

For more information, recommended settings and version update log:
https://habitica.fandom.com/wiki/Habitica_Pomodoro_SiteKeeper

Bug reports and Feature requests are welcome! https://github.com/ofekmiz/Habitica-Pomodoro-SiteKeeper/issues

If you like this project and want to support, you can buy me a coffe :) https://ko-fi.com/ofexcoffee

### Debuging in Firefox:
To test the extension in firefox go to the url "about:debugging" => This firefox => Load Temporary add-on => choose manifest.json file in the app folder.

*Before installing, add the following option to manifest.json to allow using local storage to the temporary add-on:

    "browser_specific_settings": {
        "gecko": {
            "id": "{9ed782e5-6280-4bed-bece-dea374ea9c2f}",
            "strict_min_version": "42.0"
        }
    }
