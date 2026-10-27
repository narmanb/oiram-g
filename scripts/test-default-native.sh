#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f build/native-fixtures.bin ]]; then
    echo 'Run Godot res://tests/test_native_integration.gd first to decode the real default pack.' >&2
    exit 1
fi
${CC:-cc} -std=c11 -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
  -include android/native/compat/platform.h -Iandroid/native/compat -Iandroid/native -Isrc \
  android/native/core.c android/native/graphx.c android/native/common.c android/native/memory.c android/native/presentation.c android/native/generated/*.c \
  android/tests/test_default_native.c -o build/test-default-native
UBSAN_OPTIONS=halt_on_error=1 ASAN_OPTIONS=detect_leaks=1 timeout 120s build/test-default-native build/native-fixtures.bin
