#!/usr/bin/env bash
# Builds an installable APK without Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner.
# 同一份脚本在 PC（Windows/MSYS）和 pad（Termux 的 ubuntu proot）上都能跑。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# ---- 平台探测：Windows 的工具带 .exe/.bat，POSIX 的不带 ----
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) HOST=windows ;;
  *)                    HOST=posix ;;
esac

if [ "$HOST" = windows ]; then
  SDK="${ANDROID_SDK:-/c/Users/jack/android-sdk}"
  JDK_BIN="${JDK_BIN:-/d/Program Files/Java/jdk-11.0.15.1/bin}"
  EXE=.exe; BAT=.bat
  PY="$(command -v python || echo python)"
else
  SDK="${ANDROID_SDK:-/opt/android-sdk}"
  JDK_BIN="${JDK_BIN:-}"
  EXE=; BAT=
  PY="$(command -v python3 || command -v python || echo python3)"
fi

BT="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"
[ -n "$BT" ] || { echo "build-tools not found under $SDK"; exit 1; }

# 优先用 platforms/android-35，没有就用最高的一个
ANDROID_JAR="$SDK/platforms/android-35/android.jar"
if [ ! -f "$ANDROID_JAR" ]; then
  ANDROID_JAR="$(ls -d "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1)"
fi
[ -f "$ANDROID_JAR" ] || { echo "android.jar not found under $SDK/platforms"; exit 1; }

[ -x "$BT/aapt2$EXE" ] || { echo "aapt2 not found in $BT"; exit 1; }
[ -n "$JDK_BIN" ] && export PATH="$JDK_BIN:$PATH"

OUT="$ROOT/build"
MIN_SDK=24
TARGET_SDK=34
VERSION_CODE=1
VERSION_NAME=1.0.0
PKG=io.juejin.lite

# 写文件清单，Windows 上要转成原生路径（MSYS 只自动转 argv，不转文件内容）
list_paths() {
  local dest="$1"; shift
  if [ "$HOST" = windows ]; then
    find "$@" -name '*.java' -o -name '*.class' | while read -r f; do cygpath -w "$f"; done > "$dest"
  else
    find "$@" \( -name '*.java' -o -name '*.class' \) > "$dest"
  fi
}

echo "== clean"
rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

if "$PY" -c 'import PIL' 2>/dev/null; then
  echo "== icons"
  "$PY" "$ROOT/tools/make_icons.py"
else
  echo "== icons skipped (PIL 没装；res/mipmap-*/ 里已有生成好的图标)"
fi

echo "== aapt2 compile"
"$BT/aapt2$EXE" compile --dir "$ROOT/app/res" -o "$OUT/res.zip"

echo "== aapt2 link"
"$BT/aapt2$EXE" link \
  -o "$OUT/app.unsigned.apk" \
  -I "$ANDROID_JAR" \
  --manifest "$ROOT/app/AndroidManifest.xml" \
  -R "$OUT/res.zip" \
  --java "$OUT/gen" \
  --min-sdk-version "$MIN_SDK" \
  --target-sdk-version "$TARGET_SDK" \
  --version-code "$VERSION_CODE" \
  --version-name "$VERSION_NAME" \
  --auto-add-overlay

echo "== javac"
list_paths "$OUT/sources.txt" "$ROOT/app/src" "$OUT/gen"
javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
  -classpath "$ANDROID_JAR" \
  -d "$OUT/classes" @"$OUT/sources.txt"

echo "== d8"
find "$OUT/classes" -name '*.class' | while read -r f; do
  [ "$HOST" = windows ] && cygpath -w "$f" || echo "$f"
done > "$OUT/classes.txt"
"$BT/d8$BAT" --release --lib "$ANDROID_JAR" --min-api "$MIN_SDK" \
  --output "$OUT/dex" @"$OUT/classes.txt"

echo "== package dex"
cp "$OUT/app.unsigned.apk" "$OUT/app.apk"
"$PY" - "$OUT/dex/classes.dex" "$OUT/app.apk" <<'PY'
import sys, zipfile
dex, apk = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, "a", zipfile.ZIP_DEFLATED) as z:
    z.write(dex, "classes.dex")
PY

echo "== zipalign"
# zipalign 不是可选项：未压缩的 resources.arsc 只要没 4 字节对齐，安装时就报
# INSTALL_PARSE_FAILED_NOT_APK: Failed to load asset path。
# pad 上的 build-tools 原生二进制是 x86，arm64 跑不了，所以退回纯 Python 对齐。
if "$BT/zipalign$EXE" -f -p 4 "$OUT/app.apk" "$OUT/app.aligned.apk" >/dev/null 2>&1; then
  SIGN_IN="$OUT/app.aligned.apk"
  echo "   zipalign -> app.aligned.apk"
elif "$PY" "$ROOT/tools/align_apk.py" "$OUT/app.apk" "$OUT/app.aligned.apk" 4 >/dev/null 2>&1; then
  SIGN_IN="$OUT/app.aligned.apk"
  echo "   zipalign 用不了，改用 tools/align_apk.py 对齐 -> app.aligned.apk"
else
  SIGN_IN="$OUT/app.apk"
  echo "   !! 对齐失败，APK 很可能装不上"
fi

echo "== sign"
KS="$ROOT/keystore/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$ROOT/keystore"
  keytool -genkeypair -keystore "$KS" -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi
"$BT/apksigner$BAT" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$ROOT/app-$VERSION_NAME.apk" "$SIGN_IN"

echo "== verify"
"$BT/apksigner$BAT" verify --print-certs "$ROOT/app-$VERSION_NAME.apk" | head -4
"$BT/aapt2$EXE" dump badging "$ROOT/app-$VERSION_NAME.apk" | head -3
ls -lh "$ROOT/app-$VERSION_NAME.apk"
