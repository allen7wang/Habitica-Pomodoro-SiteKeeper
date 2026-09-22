#!/bin/bash
# iOS 构建脚本：生成 Xcode 工程 → 编译 → 安装到模拟器
# 用法:
#   bash build_ios.sh              # 构建并安装到 iPhone 17 模拟器
#   bash build_ios.sh --no-install # 仅构建
set -e

BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

SIM_NAME="${SIM_NAME:-iPhone 17}"
BUNDLE_ID="com.hermes.habitica-pomodoro.ios"

# ── 1. 生成 Xcode 工程（project.yml 是唯一事实源，xcodeproj 不入库）──
echo "1/4  Generating Xcode project (xcodegen)..."
if ! command -v xcodegen >/dev/null; then
    echo "  xcodegen 未安装: brew install xcodegen" >&2; exit 1
fi
xcodegen generate

# ── 2. 编译（模拟器，免签名）──
echo "2/4  Building for iOS Simulator ($SIM_NAME)..."
xcodebuild -project HabiticaPomodoroMobile.xcodeproj \
    -scheme HabiticaPomodoroMobile \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet

APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 \
    -path "*Debug-iphonesimulator/HabiticaPomodoro.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ]; then echo "找不到构建产物" >&2; exit 1; fi
echo "      ✅ Built: $APP"

# ── 3. 启动模拟器 ──
echo "3/4  Booting simulator..."
UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

# ── 4. 安装并启动 ──
if [ "$1" != "--no-install" ]; then
    echo "4/4  Installing & launching..."
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    echo ""
    echo "════════════════════════════════════════════"
    echo "✅ iOS 版已在模拟器运行"
    echo "   真机部署: 用 Xcode 打开 HabiticaPomodoroMobile.xcodeproj，"
    echo "   Signing & Capabilities 选择你的 Team 后运行。"
    echo "════════════════════════════════════════════"
else
    echo "4/4  Skipped install (--no-install)"
fi
