#!/usr/bin/env bash
# End-to-end test: install, launch, verify the feed loads from the real Juejin API,
# open an article detail page, go back, and scroll for pagination.
# Works on any resolution (coordinates are derived from uiautomator bounds).
#
# Usage: bash tools/e2e.sh [adb-serial]
#   ADB=D:/pan/adb/adb.exe bash tools/e2e.sh 10.31.95.123:5555
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-D:/pan/adb/adb.exe}"
PKG=io.juejin.lite
ACT=$PKG/.MainActivity
SHOTS="$ROOT/docs/shots"
mkdir -p "$SHOTS"

SERIAL="${1:-}"
# No 2>&1 here: `exec-out screencap -p` writes binary PNG to stdout and merged stderr corrupts it.
adb() { if [ -n "$SERIAL" ]; then "$ADB" -s "$SERIAL" "$@"; else "$ADB" "$@"; fi; }

pass=0; fail=0
ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; fail=$((fail+1)); }
info(){ echo "INFO  $1"; }

echo "=== 0. device"
adb devices
if ! adb shell true >/dev/null 2>&1; then echo "no device attached"; exit 1; fi
SIZE=$(adb shell wm size | tr -d '\r' | sed -n 's/.*: *//p')
W=${SIZE%x*}; H=${SIZE#*x}
info "screen ${W}x${H}"
if [ -z "$W" ] || [ -z "$H" ]; then W=1080; H=1920; info "size unknown, assuming ${W}x${H}"; fi

echo "=== 1. install"
# MIUI/HyperOS shows a "USB安装提示" dialog and reports INSTALL_FAILED_USER_RESTRICTED until
# 继续安装 is tapped. Detect that and press it, then re-check the package list.
accept_miui_prompt() {
  MSYS_NO_PATHCONV=1 adb shell uiautomator dump /sdcard/i.xml >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 adb exec-out cat /sdcard/i.xml 2>/dev/null > "$SHOTS/ui-install.xml"
  local b
  b=$(grep -o 'text="继续安装"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$SHOTS/ui-install.xml" | head -1 | grep -o 'bounds="[^"]*"')
  [ -z "$b" ] && b=$(grep -o 'text="安装"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$SHOTS/ui-install.xml" | head -1 | grep -o 'bounds="[^"]*"')
  [ -z "$b" ] && return 1
  local n; n=$(echo "$b" | grep -o '[0-9]*'); set -- $n
  info "accepting MIUI install prompt at $(( ($1 + $3) / 2 )),$(( ($2 + $4) / 2 ))"
  adb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
  sleep 6
  adb shell pm list packages | grep -q "$PKG"
}

adb uninstall $PKG >/dev/null 2>&1 || true
( adb install -r "$ROOT"/app-*.apk > "$SHOTS/install.log" 2>&1 & )
installed=0
for _ in $(seq 1 12); do
  sleep 5
  if adb shell pm list packages | grep -q "^package:$PKG$"; then installed=1; break; fi
  accept_miui_prompt && { installed=1; break; }
done
cat "$SHOTS/install.log" 2>/dev/null | tail -3
if [ "$installed" = 1 ]; then ok "apk installed"; else bad "apk install"; exit 1; fi

echo "=== 2. package registered"
if adb shell pm list packages | grep -q "$PKG"; then ok "package $PKG present"; else bad "package missing"; fi

echo "=== 3. launch"
adb logcat -c >/dev/null 2>&1
adb shell am start -W -n "$ACT" | tail -5
sleep 10
# Emulators on a shared hotspot can lose DNS for the first request; give the feed one refresh.
if ! adb logcat -d -s JuejinLite:V | grep -q "feed loaded size="; then
  info "first load did not land, tapping refresh once"
  adb shell input tap $((W - 90)) 130
  sleep 12
fi

echo "=== 4. process alive (no crash)"
pid=$(adb shell pidof $PKG | tr -d '\r')
if [ -n "$pid" ]; then ok "process alive pid=$pid"; else bad "process died"; fi

echo "=== 5. feed loaded from the live API"
logs=$(adb logcat -d -s JuejinLite:V AndroidRuntime:E)
echo "$logs"
if echo "$logs" | grep -q "feed loaded size="; then
  ok "feed loaded: $(echo "$logs" | grep -o 'feed loaded size=[0-9]* total=[0-9]*' | tail -1)"
else
  bad "no feed loaded log"
fi
if echo "$logs" | grep -q "FATAL EXCEPTION"; then bad "fatal exception in logcat"; else ok "no fatal exception"; fi

echo "=== 6. article rows rendered"
MSYS_NO_PATHCONV=1 adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
MSYS_NO_PATHCONV=1 adb exec-out cat /sdcard/ui.xml > "$SHOTS/ui-feed.xml" 2>/dev/null
rows=$(grep -o 'text="[^"]\{6,\}"' "$SHOTS/ui-feed.xml" 2>/dev/null | wc -l)
if [ "$rows" -ge 3 ]; then ok "feed rows with text: $rows"; else bad "feed rows with text: $rows"; fi
adb exec-out screencap -p > "$SHOTS/e2e-01-feed.png"
[ -s "$SHOTS/e2e-01-feed.png" ] && ok "feed screenshot" || bad "feed screenshot"

echo "=== 7. open the first article"
# First card sits just below the header; derive from the dump when possible.
TAPX=$((W/2)); TAPY=$((H/4))
BOUNDS=$(grep -o 'resource-id="io.juejin.lite:id/item_title"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$SHOTS/ui-feed.xml" 2>/dev/null | head -1 | grep -o 'bounds="[^"]*"')
if [ -n "$BOUNDS" ]; then
  nums=$(echo "$BOUNDS" | grep -o '[0-9]*')
  set -- $nums
  TAPX=$(( ($1 + $3) / 2 )); TAPY=$(( ($2 + $4) / 2 ))
  info "tapping first article title at ${TAPX},${TAPY}"
else
  info "title bounds not found, tapping ${TAPX},${TAPY}"
fi
adb shell input tap "$TAPX" "$TAPY"
sleep 6
if adb shell dumpsys activity activities | grep -q "DetailActivity"; then ok "DetailActivity resumed"; else bad "DetailActivity not resumed"; fi
# The WebView needs a real network fetch; poll for the finish callback rather than a fixed nap.
for _ in $(seq 1 12); do
  adb logcat -d -s JuejinLite:V | grep -q "detail page finished" && break
  sleep 5
done
if adb logcat -d -s JuejinLite:V | grep -q "detail page finished"; then
  ok "detail page finished: $(adb logcat -d -s JuejinLite:V | grep -o 'detail page finished [^ ]*' | tail -1)"
else
  bad "detail page not finished"
fi
sleep 3
adb exec-out screencap -p > "$SHOTS/e2e-02-detail.png"
MSYS_NO_PATHCONV=1 adb shell uiautomator dump /sdcard/ui2.xml >/dev/null 2>&1
MSYS_NO_PATHCONV=1 adb exec-out cat /sdcard/ui2.xml > "$SHOTS/ui-detail.xml" 2>/dev/null

echo "=== 8. back to feed"
adb shell input keyevent KEYCODE_BACK; sleep 2
if adb shell dumpsys activity activities | grep -q "MainActivity"; then ok "back to MainActivity"; else bad "back failed"; fi

echo "=== 9. scroll + pagination"
adb shell input swipe $((W/2)) $((H*3/4)) $((W/2)) $((H/6)) 200; sleep 2
adb shell input swipe $((W/2)) $((H*3/4)) $((W/2)) $((H/6)) 200; sleep 2
adb shell input swipe $((W/2)) $((H*3/4)) $((W/2)) $((H/6)) 200; sleep 3
n=$(adb logcat -d -s JuejinLite:V | grep -c "feed loaded size=")
if [ "$n" -ge 2 ]; then ok "pagination triggered ($n loads)"; else bad "pagination not triggered ($n loads)"; fi
adb exec-out screencap -p > "$SHOTS/e2e-03-scrolled.png"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
