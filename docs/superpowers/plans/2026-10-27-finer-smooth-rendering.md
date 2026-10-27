# Finer Smooth Rendering Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Existing autonomous-work authorization applies.

**Goal:** Remove whole-source-pixel stepping in smooth presentation without changing original gameplay and expose frame pacing.

**Architecture:** Add an isolated 2x indexed replay of captured native commands, exposed as `OiramEngine.frame_smooth(alpha)` returning 640x480 RGBA. Keep classic and old interpolation APIs. The Godot shell selects dimensions, recreates textures only on resolution changes and displays optional foreground interval statistics.

**Tech Stack:** Existing portable C, Godot 4.6.3 GDExtension and GDScript, Android ARM64.

**Spec:** `docs/superpowers/specs/2026-10-27-finer-smooth-rendering.md`

## Global Constraints

- Original 30 Hz authoritative C simulation; original calculator source unchanged.
- Sharp original artwork, original draw order and palette; no image blending.
- Background/pause time excluded from frame statistics; no claimed device testing.
- Private APK, same debug key, Android 13+ and ARM64.

## Review Focus

- One-pixel actor/camera motion must have a distinct half-pixel intermediate frame.
- Clipping/negative positions must not write outside the 640x480 buffer.
- No-history, teleports and command overflow must return a complete safe image.
- Resolution switches and pausing must preserve game state and reset statistics.
- Frame interval statistics must distinguish steady pacing from mixed intervals.

### Task 1: Native fine replay

- [x] Add native regressions for half-pixel sprite and camera positions, clipping,
  original-state invariance, and exact 2x alpha1/fallback output; run to observe failure.
- [x] Implement `native_presentation_frame_fine(double alpha)` returning indexed
  640x480 and `oiram_native_frame_smooth(double alpha)` returning RGBA at that size.
  Keep rasterizer independent of GraphX's original draw target/clip globals.
- [x] Bind `OiramEngine.frame_smooth(alpha)` and run sanitizer presentation suite.
- [x] Benchmark actual original/fine replay host CPU time, including conversion.

### Task 2: Shell integration and frame diagnostics

- [x] Add failing Godot checks for 640x480 smooth output, 320x240 classic output,
  safe in-place mode switches and unchanged native state.
- [x] Add `FramePacing.add_interval(seconds)`, `reset()` and `summary(target_fps)`
  with tests for steady/uneven pacing, bounded samples and reset.
- [x] Update main shell rendering dimensions/texture lifetime and FPS details;
  reset observations on inactive frames/resume/mode change. Run affected suites.

### Task 3: Deliver

- [x] Run full APK build and required native/Godot/default-pack suites; verify
  ARM64 libraries, signatures, version and source preservation.
- [x] Update release/test notes with measured limitations and artifact checksum.
- [x] Commit and push android-port; upload APK privately and verify metadata.

## Execution record

Native RED: new entry points failed linking before implementation. GREEN:
ASan/UBSan suite passes, including every-pixel alpha1 equality and invariance.
Pacing RED: missing diagnostics assertion failed. GREEN: 22 checks pass, along
with 163 existing layout checks and the full APK pipeline. Host benchmark and
full test counts are recorded in `docs/test-report.md`. Reviewer found no blocking
defects; additional full-block default-stage coverage is deferred because the
isolated suite already checks every enlarged pixel. Device comparison remains
outstanding, explicitly separate from host verification.

Private Drive upload metadata confirms the exact 84,164,177-byte APK and
owner-only permissions. Update signing identity matches v0.1.2. Artifact SHA256
is recorded in the test report; build products remain outside Git.
