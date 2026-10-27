#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-native.py
python3 scripts/convert-assets.py
mkdir -p build
${CC:-cc} -std=c11 -O2 -D_POSIX_C_SOURCE=200809L -include android/native/compat/platform.h \
  -Iandroid/native/compat -Iandroid/native -Isrc \
  android/native/core.c android/native/graphx.c android/native/common.c android/native/memory.c \
  android/native/presentation.c android/native/generated/*.c android/tests/benchmark_presentation.c \
  -o build/benchmark-presentation
build/benchmark-presentation
