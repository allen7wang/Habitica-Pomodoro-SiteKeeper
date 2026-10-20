#!/bin/bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export PATH="$JAVA_HOME/bin:$PATH"
SCRATCH="${HERMES_SCRATCH:-$HOME/.hermes/cache/scratch}"
mkdir -p "$SCRATCH/pomo-android-tmp"
export TMPDIR="$SCRATCH/pomo-android-tmp"
case "${1:-debug}" in
    debug) TASK=assembleDebug; OUT="$SCRATCH/pomo-parity-build/app/outputs/apk/debug/app-debug.apk" ;;
    lint) TASK=lintDebug; OUT="$SCRATCH/pomo-parity-build/app/reports/lint-results-debug.html" ;;
    release) TASK=assembleRelease; OUT="$SCRATCH/pomo-parity-build/app/outputs/apk/release/app-release.apk" ;;
    *) printf 'Usage: %s [debug|lint|release]\n' "$0" >&2; exit 2 ;;
esac
./gradlew --project-cache-dir "$SCRATCH/pomo-parity-gradle" -PpomoBuildRoot="$SCRATCH/pomo-parity-build" "$TASK" --console=plain
printf 'Artifact: %s\n' "$OUT"
test -f "$OUT"
