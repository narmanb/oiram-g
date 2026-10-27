#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-native.py
python3 scripts/convert-assets.py
mkdir -p build
${CC:-cc} -std=c11 -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
  -include android/native/compat/platform.h -Iandroid/native/compat -Iandroid/native -Isrc \
  android/native/core.c android/native/graphx.c android/native/common.c android/native/generated/*.c \
  android/tests/test_native.c -o build/test-native
UBSAN_OPTIONS=halt_on_error=1 ASAN_OPTIONS=detect_leaks=1 build/test-native
