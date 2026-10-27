#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR=${OIRAM_TOOLS_DIR:-/workspace/tools}
export GODOT_CPP_DIR=${GODOT_CPP_DIR:-$TOOLS_DIR/godot-cpp}
export ANDROID_HOME=${ANDROID_HOME:-$TOOLS_DIR/android-sdk}
PLATFORM=${1:-linux}
TARGET=${2:-template_debug}
case "$PLATFORM" in
  linux) ARCH=x86_64 ;;
  android) ARCH=arm64 ;;
  *) echo 'Usage: build-native.sh [linux|android] [template_debug|template_release]' >&2; exit 2 ;;
esac
mkdir -p "$TOOLS_DIR" "$REPO_ROOT/android/bin"
python3 "$REPO_ROOT/scripts/prepare-native.py"
python3 "$REPO_ROOT/scripts/convert-assets.py"
printf '%s\n' '{"enabled_classes":["RefCounted","OS"]}' > "$TOOLS_DIR/oiram-build-profile.json"
cd "$REPO_ROOT/android/native"
exec python3 -m SCons -j"${JOBS:-4}" platform="$PLATFORM" arch="$ARCH" target="$TARGET" \
  android_api_level=33 ndk_version=28.1.13356709 build_profile="$TOOLS_DIR/oiram-build-profile.json"
