#!/usr/bin/env bash
# End-to-end test on the pad: install, launch, verify feed, open an article.
# Usage: bash tools/e2e.sh [adb-serial]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-D:/pan/adb/adb.exe}"
PKG=io.juejin.lite
ACT=$PKG/.MainActivity
SHOTS="$ROOT/docs/shots"
mkdir -p "$SHOTS"

if [ $# -ge 1 ]; then ADB="$ADB -s $1"; fi

pass=0; fail=0
ok()   { echo "PASS  $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1"; fail=$((fail+1)); }

adb() { "$ADB" "$@" 2>&1; }

echo "=== 0. device"
adb devices
adb shell true >/dev/null || { echo "no device"; exit 1; }

echo "=== 1. install"
adb uninstall $PKG >/dev/null 2>&1
out=$(adb install -r "$ROOT"/app-*.apk)
echo "$out"
case "$out" in
  *Success*) ok "apk installed" ;;
  *) bad "apk install"; exit 1 ;;
esac

echo "=== 2. package registered"
if adb shell pm list packages | grep -q "$PKG"; then ok "package $PKG present"; else bad "package missing"; fi

echo "=== 3. launch"
adb logcat -c
adb shell am start -W -n "$ACT" | tail -5
sleep 8

echo "=== 4. process alive (no crash)"
pid=$(adb shell pidof $PKG | tr -d '\r')
if [ -n "$pid" ]; then ok "process alive pid=$pid"; else bad "process died"; fi

echo "=== 5. app logs"
logs=$(adb logcat -d -s JuejinLite:V AndroidRuntime:E)
echo "$logs"
if echo "$logs" | grep -q "feed loaded size="; then
  ok "feed loaded: $(echo "$logs" | grep -o 'feed loaded size=[0-9]* total=[0-9]*' | tail -1)"
else
  bad "no feed loaded log"
fi
if echo "$logs" | grep -q "FATAL EXCEPTION"; then bad "fatal exception in logcat"; else ok "no fatal exception"; fi

echo "=== 6. screenshot feed"
adb exec-out screencap -p > "$SHOTS/e2e-01-feed.png"
[ -s "$SHOTS/e2e-01-feed.png" ] && ok "feed screenshot" || bad "feed screenshot"

echo "=== 7. tap first card"
adb shell input tap 1016 900
sleep 7
if adb shell dumpsys activity activities | grep -q "DetailActivity"; then ok "DetailActivity resumed"; else bad "DetailActivity not resumed"; fi
if echo "$(adb logcat -d -s JuejinLite:V)" | grep -q "detail page finished"; then ok "detail page finished"; else bad "detail page not finished"; fi
adb exec-out screencap -p > "$SHOTS/e2e-02-detail.png"

echo "=== 8. back to feed"
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell dumpsys activity activities | grep -q "MainActivity" && ok "back to MainActivity" || bad "back failed"

echo "=== 9. scroll + pagination"
adb shell input swipe 1016 2200 1016 500 200; sleep 2
adb shell input swipe 1016 2200 1016 500 200; sleep 3
n=$(adb logcat -d -s JuejinLite:V | grep -c "feed loaded size=")
if [ "$n" -ge 2 ]; then ok "pagination triggered ($n loads)"; else echo "INFO pagination not triggered ($n loads)"; fi
adb exec-out screencap -p > "$SHOTS/e2e-03-scrolled.png"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
