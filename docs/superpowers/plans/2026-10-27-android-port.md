# Oiram Android Port Implementation Plan

> **For agentic workers:** Execute independent bounded components using the parallel-agents skill; integrate and verify together.

**Goal:** Deliver a native playable Oiram ARM64 APK with retained C gameplay.
**Architecture:** Original C + graphx portability adapter + Godot GDExtension, validated pack parser and native Godot shell.
**Tech Stack:** Godot 4.6.3, C11/C++17, Android SDK/NDK, Python asset converter.
**Spec:** docs/superpowers/specs/2026-10-27-android-port-design.md

## Global Constraints
Keep original src/ intact; native engine authoritative; offline ARM64 Android 13+; preserve constants and assets; private testing only; manual CI.

## Review Focus
Malformed RLE and warp offsets must never reach unsafe native access. Suspend must release input and freeze gameplay. Saves must stay associated with pack content. Enemy activation and graphics clipping must retain original action area. Original 24-bit integers and pointer arithmetic must port safely to ARM64.

### Task 1: Retained native engine
- [ ] Add native regression harness for collision, movement, run, jump, tile/power-up interactions and level lifecycle. Run before implementation.
- [ ] Implement compat headers, graphx framebuffer, common.s translation and cooperative lifecycle. Generate sprite arrays from original PNGs.
- [ ] Build host shared engine and run tests under sanitizers.
- [ ] Commit engine foundation.
Interfaces: configure,step,advance_clock,frame,state as specified.

### Task 2: Pack codec and editor
- [ ] Test default decoding, truncated/malformed files, offsets and RLE boundaries.
- [ ] Implement original CD/CE AppVar decoding, encoding and validation; cross-check original editor round trip.
- [ ] Implement mobile editor after playable game integration, with any deferred work explicit.
Interfaces: OiramPack.load_bytes and encode as specified.

### Task 3: Godot game shell
- [ ] Build main menu, pack selection, game texture and progression around OiramEngine and OiramPack.
- [ ] Add semantic touch/gamepad controls, remapping, adjustable mirrored layout, settings, atomic per-pack save and background pause.
- [ ] Run headless lifecycle/input/save tests and desktop visual smoke.

### Task 4: Android build
- [ ] Install reproducible SDK/NDK/templates, compile Linux/ARM64 GDExtension.
- [ ] Export installable debug APK and inspect native libraries, assets and signature.
- [ ] Add workflow_dispatch CI and build/install documentation.

### Task 5: Integration verification
- [ ] Run complete tests, render representative gameplay, smoke all default levels, review native memory and lifecycle risks.
- [ ] Build final APK after fixes and preserve downloadable artifact.
- [ ] Commit/push android-port without publicly releasing APK; accurately report validation limits.
