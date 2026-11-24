#!/usr/bin/env bash
# Builds an installable APK without Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${ANDROID_SDK:-/c/Users/jack/android-sdk}"
BT="$SDK/build-tools/34.0.0"
ANDROID_JAR="$SDK/platforms/android-35/android.jar"
JDK_BIN="${JDK_BIN:-/d/Program Files/Java/jdk-11.0.15.1/bin}"
OUT="$ROOT/build"

[ -x "$BT/aapt2.exe" ] || { echo "aapt2 not found in $BT"; exit 1; }
[ -f "$ANDROID_JAR" ] || { echo "android.jar not found at $ANDROID_JAR"; exit 1; }

export PATH="$JDK_BIN:$PATH"

MIN_SDK=24
TARGET_SDK=34
VERSION_CODE=1
VERSION_NAME=1.0.0
PKG=io.juejin.lite

echo "== clean"
rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

echo "== icons"
python "$ROOT/tools/make_icons.py"

echo "== aapt2 compile"
"$BT/aapt2.exe" compile --dir "$ROOT/app/res" -o "$OUT/res.zip"

echo "== aapt2 link"
"$BT/aapt2.exe" link \
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
find "$ROOT/app/src" "$OUT/gen" -name '*.java' | while read -r f; do cygpath -w "$f"; done > "$OUT/sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
  -classpath "$ANDROID_JAR" \
  -d "$OUT/classes" @"$OUT/sources.txt"

echo "== d8"
find "$OUT/classes" -name '*.class' | while read -r f; do cygpath -w "$f"; done > "$OUT/classes.txt"
"$BT/d8.bat" --release --lib "$ANDROID_JAR" --min-api "$MIN_SDK" \
  --output "$OUT/dex" @"$OUT/classes.txt"

echo "== package dex"
cp "$OUT/app.unsigned.apk" "$OUT/app.apk"
python - "$OUT/dex/classes.dex" "$OUT/app.apk" <<'PY'
import sys, zipfile
dex, apk = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, "a", zipfile.ZIP_DEFLATED) as z:
    z.write(dex, "classes.dex")
PY

echo "== zipalign"
"$BT/zipalign.exe" -f -p 4 "$OUT/app.apk" "$OUT/app.aligned.apk"

echo "== sign"
KS="$ROOT/keystore/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$ROOT/keystore"
  keytool -genkeypair -keystore "$KS" -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi
"$BT/apksigner.bat" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$ROOT/app-$(echo $VERSION_NAME).apk" "$OUT/app.aligned.apk"

echo "== verify"
"$BT/apksigner.bat" verify --print-certs "$ROOT/app-$VERSION_NAME.apk" | head -4
"$BT/aapt2.exe" dump badging "$ROOT/app-$VERSION_NAME.apk" | head -3
ls -lh "$ROOT/app-$VERSION_NAME.apk"
