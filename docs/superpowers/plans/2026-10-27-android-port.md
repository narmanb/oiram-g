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
- [x] Add native regression harness for collision, movement, run, jump, tile/power-up interactions and level lifecycle. Run before implementation.
- [x] Implement compat headers, graphx framebuffer, common.s translation and cooperative lifecycle. Generate sprite arrays from original PNGs.
- [x] Build host shared engine and run tests under sanitizers.
- [x] Commit engine foundation.
Interfaces: configure,step,advance_clock,frame,state as specified.

### Task 2: Pack codec and editor
- [x] Test default decoding, truncated/malformed files, offsets and RLE boundaries.
- [x] Implement original CD/CE AppVar decoding, encoding and validation; cross-check original editor round trip.
- [x] Implement mobile editor after playable game integration, with any deferred work explicit.
Interfaces: OiramPack.load_bytes and encode as specified.

### Task 3: Godot game shell
- [x] Build main menu, pack selection, game texture and progression around OiramEngine and OiramPack.
- [x] Add semantic touch/gamepad controls, remapping, adjustable mirrored layout, settings, atomic per-pack save and background pause.
- [x] Run headless lifecycle/input/save tests and desktop visual smoke.

### Task 4: Android build
- [x] Install reproducible SDK/NDK/templates, compile Linux/ARM64 GDExtension.
- [x] Export installable debug APK and inspect native libraries, assets and signature.
- [x] Add workflow_dispatch CI and build/install documentation.

### Task 5: Integration verification
- [x] Run complete tests, render representative gameplay, smoke all default levels, review native memory and lifecycle risks.
- [x] Build final APK after fixes and preserve downloadable artifact.
- [x] Commit/push android-port without publicly releasing APK; accurately report validation limits.

## Completion record

The final private-test APK exists at build/oiram-arm64-debug.apk (84,140,755 bytes), SHA256 88630580cd021978e244077ba27518647588a8369a84e7fa329b194ae6e2d38d. Signature, SDK33/35, ARM64 ELF and16KiB ZIP/load alignment, zero permissions, original pack bytes and licenses verified. Original source tree unchanged.

Independent review found original callback use-after-free risks, SAF URI handling, unbounded editor import, editor Back routing and transient save flags. Targeted regressions and safe native tick reclamation resolve the reported issues. The final negative-coordinate padding regression also passes. Full native/default-stage sanitizer checks and Godot suites passed; see docs/test-report.md for exact coverage and device/timing limits.

Milestone4 is intentionally bounded: the editor preserves existing warps and supports editing/testing/export, but does not create new warp pairs. 30Hz remains an uncalibrated baseline; no Android physical device or emulator execution is claimed. Calculator menus/transitions are adapted. APK upload in the manual workflow is private-repository-only because the requested repository is public. No workflow was dispatched and no public APK release was created.
