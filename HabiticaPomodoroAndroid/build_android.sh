#!/bin/bash
# Android 构建脚本：编译 debug/release APK
# 用法:
#   bash build_android.sh            # 构建 debug APK（本机安装用）
#   bash build_android.sh release    # 构建 release APK（发布用，无 keystore.properties 时以 debug 签名）
set -e

BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"

VARIANT="${1:-debug}"
case "$VARIANT" in
    release) TASK="assembleRelease" ; OUT="app/build/outputs/apk/release/app-release.apk" ;;
    *)       TASK="assembleDebug"   ; OUT="app/build/outputs/apk/debug/app-debug.apk" ;;
esac

echo "==> Gradle $TASK (JAVA_HOME=$JAVA_HOME)"
./gradlew "$TASK" --console=plain 2>&1 | tail -5

if [ -f "$OUT" ]; then
    echo "✅ APK: $BASE/$OUT"
    ls -la "$OUT"
else
    echo "❌ 未找到 APK 产物，请检查上面的构建输出"
    exit 1
fi
