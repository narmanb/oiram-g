#!/usr/bin/env bash
set -euo pipefail
# Linux x86_64 host; dependencies are kept outside the checkout.
TOOLS_DIR=${OIRAM_TOOLS_DIR:-/workspace/tools}
export ANDROID_HOME=${ANDROID_HOME:-$TOOLS_DIR/android-sdk}
GODOT_VERSION=4.6.3
CPP_REV=e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
mkdir -p "$TOOLS_DIR" "$ANDROID_HOME/cmdline-tools"
python3 -m pip install 'scons==4.9.1' 'Pillow==11.3.0'
download() { test -f "$2" || curl --fail --location --retry 3 "$1" --output "$2"; }
if ! command -v javac >/dev/null && ! test -x "${JAVA_HOME:-/nonexistent}/bin/javac"; then
  JDK="$TOOLS_DIR/OpenJDK21U-jdk_x64_linux_hotspot_21.0.8_9.tar.gz"
  download 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.8%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.8_9.tar.gz' "$JDK"
  printf '%s  %s\n' f2dc5418092c43003db8f9005c4a286e1c0104fea96ccdd49e8ebd037cac9219 "$JDK" | sha256sum --check
  test -x "$TOOLS_DIR/jdk-21.0.8+9/bin/java" || tar -xzf "$JDK" -C "$TOOLS_DIR"
  export JAVA_HOME="$TOOLS_DIR/jdk-21.0.8+9"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
if ! test -x "$ANDROID_HOME/cmdline-tools/19.0/bin/sdkmanager"; then
  ARCHIVE="$TOOLS_DIR/commandlinetools-linux-13114758_latest.zip"
  download https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip "$ARCHIVE"
  printf '%s  %s\n' 7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee "$ARCHIVE" | sha256sum --check
  mkdir -p "$TOOLS_DIR/cmdline-unpack"
  unzip -q -o "$ARCHIVE" -d "$TOOLS_DIR/cmdline-unpack"
  mv "$TOOLS_DIR/cmdline-unpack/cmdline-tools" "$ANDROID_HOME/cmdline-tools/19.0"
fi
SDKMANAGER="$ANDROID_HOME/cmdline-tools/19.0/bin/sdkmanager"
if test -f /etc/ssl/certs/java/cacerts; then
  export SDKMANAGER_OPTS="${SDKMANAGER_OPTS:-} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
fi
# Accept the SDK licenses for this developer/testing toolchain.
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null
set -o pipefail
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" 'build-tools;35.0.0' 'build-tools;36.1.0' 'platforms;android-35' 'platforms;android-36' 'ndk;28.1.13356709'
PLATFORM_TOOLS="$TOOLS_DIR/platform-tools_r35.0.2-linux.zip"
download https://dl.google.com/android/repository/platform-tools_r35.0.2-linux.zip "$PLATFORM_TOOLS"
printf '%s  %s\n' acfdcccb123a8718c46c46c059b2f621140194e5ec1ac9d81715be3d6ab6cd0a "$PLATFORM_TOOLS" | sha256sum --check
python3 - "$ANDROID_HOME" <<'PY'
import pathlib, sys
# sdkmanager may leave version metadata from a previously installed newer adb.
(pathlib.Path(sys.argv[1])/'platform-tools/package.xml').unlink(missing_ok=True)
PY
unzip -q -o "$PLATFORM_TOOLS" -d "$ANDROID_HOME"
if ! test -d "$TOOLS_DIR/godot-cpp/.git"; then
  git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git "$TOOLS_DIR/godot-cpp"
fi
test "$(git -C "$TOOLS_DIR/godot-cpp" rev-parse HEAD)" = "$CPP_REV" || { echo 'Unexpected godot-cpp revision.' >&2; exit 1; }
BASE="https://github.com/godotengine/godot-builds/releases/download/$GODOT_VERSION-stable"
TEMPLATES="$TOOLS_DIR/godot-$GODOT_VERSION-templates.tpz"
download "$BASE/Godot_v$GODOT_VERSION-stable_export_templates.tpz" "$TEMPLATES"
printf '%s  %s\n' da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68 "$TEMPLATES" | sha512sum --check
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$GODOT_VERSION.stable"
mkdir -p "$TEMPLATE_DIR"
unzip -j -o "$TEMPLATES" templates/android_debug.apk templates/android_release.apk templates/android_source.zip -d "$TEMPLATE_DIR"
if ! test -x "$TOOLS_DIR/godot/Godot_v$GODOT_VERSION-stable_linux.x86_64"; then
  ENGINE="$TOOLS_DIR/Godot_v$GODOT_VERSION-stable_linux.x86_64.zip"
  download "$BASE/Godot_v$GODOT_VERSION-stable_linux.x86_64.zip" "$ENGINE"
  printf '%s  %s\n' a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c "$ENGINE" | sha512sum --check
  mkdir -p "$TOOLS_DIR/godot"
  unzip -o "$ENGINE" -d "$TOOLS_DIR/godot"
fi
printf 'Toolchain ready. ANDROID_HOME=%s\nGODOT=%s/godot/Godot_v%s-stable_linux.x86_64\n' "$ANDROID_HOME" "$TOOLS_DIR" "$GODOT_VERSION"
