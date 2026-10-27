#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR=${OIRAM_TOOLS_DIR:-/workspace/tools}
export ANDROID_HOME=${ANDROID_HOME:-$TOOLS_DIR/android-sdk}
if [[ -z "${JAVA_HOME:-}" && -x "$TOOLS_DIR/jdk-21.0.8+9/bin/java" ]]; then
  export JAVA_HOME="$TOOLS_DIR/jdk-21.0.8+9"
else
  export JAVA_HOME=${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}
fi
GODOT=${GODOT:-$TOOLS_DIR/godot/Godot_v4.6.3-stable_linux.x86_64}
if ! test -x "$GODOT" && test -x /opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64; then
  GODOT=/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64
fi
"$GODOT" --version | grep -q '^4\.6\.3\.' || { echo 'Godot 4.6.3 is required.' >&2; exit 1; }
OUTPUT=${1:-$REPO_ROOT/build/oiram-arm64-debug.apk}
mkdir -p "$(dirname "$OUTPUT")" "$TOOLS_DIR"
OUTPUT=$(realpath -m "$OUTPUT")
"$REPO_ROOT/scripts/build-native.sh" linux
"$REPO_ROOT/scripts/build-native.sh" android
"$REPO_ROOT/scripts/test-native.sh"
# Gradle is required to encode the Android 13 minimum in the APK manifest.
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable"
if ! test -f "$TEMPLATE_DIR/android_source.zip"; then
  unzip -j -o "$TOOLS_DIR/godot-4.6.3-templates.tpz" templates/android_source.zip -d "$TEMPLATE_DIR"
fi
GRADLE_BUILD="$REPO_ROOT/android/.android-build/build"
if ! test -f "$GRADLE_BUILD/gradlew"; then
  mkdir -p "$GRADLE_BUILD"
  unzip -q -o "$TEMPLATE_DIR/android_source.zip" -d "$GRADLE_BUILD"
  printf '4.6.3.stable\n' > "$REPO_ROOT/android/.android-build/.build_version"
  touch "$GRADLE_BUILD/.gdignore"
  chmod +x "$GRADLE_BUILD/gradlew"
  # There is no CMake rebuild: use the same installed NDK for native stripping.
  sed -i "s/29.0.14206865/28.1.13356709/" "$GRADLE_BUILD/config.gradle"
fi
# Java/Gradle does not automatically honor shell HTTPS_PROXY. Preserve the proxy
# route and use the host Java trust store when one is provided by the environment.
if [[ -n "${HTTPS_PROXY:-}" ]]; then
  PROXY_JVM=$(python3 - <<'PY'
import os, urllib.parse
p = urllib.parse.urlsplit(os.environ['HTTPS_PROXY'])
print(f'-Dhttp.proxyHost={p.hostname} -Dhttp.proxyPort={p.port or 80} -Dhttps.proxyHost={p.hostname} -Dhttps.proxyPort={p.port or 80}')
PY
)
  export GRADLE_OPTS="${GRADLE_OPTS:-} $PROXY_JVM"
fi
if test -f /etc/ssl/certs/java/cacerts; then
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
fi
# The editor scan registers extensions and creates editor settings on a fresh host.
"$GODOT" --headless --editor --path "$REPO_ROOT/android" --quit
for TEST_PATH in tests/test_packs tests/test_shell tests/test_native_integration editor/test_editor; do
  TEST=${TEST_PATH##*/}
  test -f "$REPO_ROOT/android/$TEST_PATH.gd" || { echo "Missing required test $TEST" >&2; exit 1; }
  TEST_LOG="$TOOLS_DIR/$TEST.log"
  timeout 600 "$GODOT" --headless --path "$REPO_ROOT/android" --script "res://$TEST_PATH.gd" > "$TEST_LOG" 2>&1
  cat "$TEST_LOG"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|Assertion failed|[1-9][0-9]* failures' "$TEST_LOG"; then
    echo "Godot test failed: $TEST" >&2; exit 1
  fi
  case "$TEST" in
    test_packs) grep -Eq 'Pack codec: [0-9]+ checks, 0 failures' "$TEST_LOG" ;;
    test_shell) grep -q 'PASS:' "$TEST_LOG" ;;
    test_native_integration) grep -Eq 'Native shell integration: [0-9]+ checks, 0 failures' "$TEST_LOG" ;;
    test_editor) grep -Eq 'Editor: [0-9]+ checks, 0 failures' "$TEST_LOG" ;;
  esac
done
"$REPO_ROOT/scripts/test-default-native.sh"
DEBUG_KEYSTORE="$TOOLS_DIR/oiram-debug.keystore"
if ! test -f "$DEBUG_KEYSTORE"; then
  keytool -genkeypair -keystore "$DEBUG_KEYSTORE" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
fi
export DEBUG_KEYSTORE
python3 - <<'PY'
import os, pathlib, re
config = pathlib.Path(os.environ.get('XDG_CONFIG_HOME', str(pathlib.Path.home()/'.config')))/'godot/editor_settings-4.6.tres'
text = config.read_text()
values = {
    'export/android/android_sdk_path': os.environ['ANDROID_HOME'],
    'export/android/java_sdk_path': os.environ['JAVA_HOME'],
    'export/android/debug_keystore': os.environ['DEBUG_KEYSTORE'],
    'export/android/debug_keystore_user': 'androiddebugkey',
    'export/android/debug_keystore_pass': 'android',
}
for key, value in values.items():
    line = f'{key} = "{value}"'
    if re.search(r'^'+re.escape(key)+r' = .*$', text, flags=re.M):
        text = re.sub(r'^'+re.escape(key)+r' = .*$', lambda _: line, text, flags=re.M)
    else:
        text += '\n'+line+'\n'
config.write_text(text)
PY
python3 - "$OUTPUT" <<'PY'
import pathlib, sys
# A failed export must never allow an older APK to pass the checks below.
pathlib.Path(sys.argv[1]).unlink(missing_ok=True)
PY
"$GODOT" --headless --path "$REPO_ROOT/android" --export-debug 'Android Private Testing' "$OUTPUT"
"$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --verbose "$OUTPUT"
BADGING=$("$ANDROID_HOME/build-tools/35.0.0/aapt" dump badging "$OUTPUT")
printf '%s\n' "$BADGING"
grep -q "sdkVersion:'33'" <<< "$BADGING"
grep -q "targetSdkVersion:'35'" <<< "$BADGING"
"$ANDROID_HOME/build-tools/35.0.0/zipalign" -c -P 16 4 "$OUTPUT"
PERMISSIONS=$("$ANDROID_HOME/build-tools/35.0.0/aapt" dump permissions "$OUTPUT")
if [[ "$PERMISSIONS" == *android.permission.INTERNET* ]]; then
  echo 'Unexpected Internet permission in private-testing APK.' >&2; exit 1
fi
python3 - "$OUTPUT" "$REPO_ROOT" <<'PY'
import hashlib, pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as apk:
    libraries = [n for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so')]
    assert libraries and all(n.startswith('lib/arm64-v8a/') for n in libraries), libraries
    assert any('liboiram.' in n for n in libraries), libraries
    print('Verified ARM64-only native libraries:', ', '.join(libraries))
    packs = [n for n in apk.namelist() if n.endswith('/assets/OiramPK.8xv')]
    assert len(packs) == 1, packs
    payload = apk.read(packs[0])
    assert payload == (pathlib.Path(sys.argv[2])/'extra/OiramPK.8xv').read_bytes()
    for notice in ['Oiram-LICENSE.txt', 'graphx-LGPL-3.0.txt', 'GPL-3.0.txt']:
        assert any(n.endswith('/licenses/'+notice) for n in apk.namelist()), notice
    print('Verified byte-identical default pack SHA256:', hashlib.sha256(payload).hexdigest())
PY
sha256sum "$OUTPUT"
printf 'Private-testing APK: %s\n' "$OUTPUT"
