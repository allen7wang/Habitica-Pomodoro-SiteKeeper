#!/bin/bash
# iOS 构建脚本：生成 Xcode 工程 → 编译 → 安装到模拟器
# 用法:
#   bash build_ios.sh              # 构建并安装到 iPhone 17 模拟器
#   bash build_ios.sh --no-install # 仅构建
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

MODE="${1:-}"
if [ "$MODE" != "" ] && [ "$MODE" != "--no-install" ]; then
    printf 'Usage: %s [--no-install]\n' "$0" >&2; exit 2
fi
SIM_NAME="${SIM_NAME:-iPhone 17}"
BUNDLE_ID="com.hermes.habitica-pomodoro.ios"
BUILD_ROOT="${HABITICA_IOS_BUILD_DIR:-${HERMES_SCRATCH:-$HOME/.hermes/cache/scratch}/pomo-ios-parity-build}"
DESTINATION="generic/platform=iOS Simulator"
if [ "$MODE" != "--no-install" ]; then
    DESTINATION="platform=iOS Simulator,name=$SIM_NAME"
    if [ -n "${SIM_UDID:-}" ]; then DESTINATION="id=$SIM_UDID"; fi
fi

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
    -destination "$DESTINATION" \
    -derivedDataPath "$BUILD_ROOT" \
    -jobs 1 -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet

APP="$BUILD_ROOT/Build/Products/Debug-iphonesimulator/HabiticaPomodoro.app"
if [ ! -d "$APP" ]; then echo "找不到本次构建产物: $APP" >&2; exit 1; fi
echo "      ✅ Built: $APP"
if [ "$MODE" = "--no-install" ]; then
    echo "3/4 & 4/4  Skipped simulator boot and install (--no-install)"
    exit 0
fi

# ── 3. 启动明确选择的模拟器 ──
echo "3/4  Booting simulator..."
UDID="${SIM_UDID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; name=sys.argv[1]; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and d["name"]==name]; ds.sort(key=lambda d:d.get("state")!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM_NAME")}"
if [ -z "$UDID" ]; then echo "找不到可用模拟器: $SIM_NAME" >&2; exit 1; fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# ── 4. 安装并启动 ──
if [ "$MODE" != "--no-install" ]; then
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
