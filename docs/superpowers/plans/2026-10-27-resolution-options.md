# Resolution Options Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline with one fresh final review. User authorized autonomous implementation.

**Goal:** Add measurable quarter-pixel presentation and screen-aware saved resolution choices without changing gameplay Hz.

**Architecture:** Parameterize the existing native replay for scale2/4 with bounded shared buffers, and expose `frame_smooth(alpha, scale=2)` in GDExtension. Main shell normalizes a saved `render_resolution` value of 0/2/4, selects physical-screen-aware Auto and reports actual output dimensions.

**Tech Stack:** Portable C, Godot 4.6.3/GDExtension, GDScript, existing Android ARM64 toolchain.

**Spec:** `docs/superpowers/specs/2026-10-27-resolution-options.md`

## Global Constraints

- Original logical play area 320x240 and 30 Hz authoritative C simulation unchanged.
- Sharp original artwork and fallback, clip, identity and warp guarantees preserved.
- Native outputs bounded to 640x480 or 1280x960; classic output remains 320x240.
- Private APK, Android13+, same app/signing identity; no physical-device claims.

## Review Focus

- Quarter-pixel tests must distinguish the new positions from the existing 2x renderer.
- Invalid/malicious scales must not overrun native output buffers or allocate unbounded memory.
- Auto must use physical output dimensions under canvas stretching and rotation.
- Resolution changes must preserve game state and saved preferences in classic mode.
- Higher buffer/copy cost must be measured and a lighter override retained.

### Task 1: Scaled native replay

- [x] Add failing quarter-position, 4x alpha1/fallback and invalid-scale regressions.
- [x] Implement `native_presentation_frame_scaled(double alpha,unsigned scale)` and
  `oiram_native_frame_scaled(double alpha,unsigned scale)`, normalizing unsupported
  values to2. Keep old 2x APIs as wrappers; bind optional scale in `frame_smooth`.
- [x] Run native sanitizer tests; benchmark original/2x/4x native replay and RGBA.

### Task 2: Saved resolution options

- [x] Add failing Godot tests for physical auto selection, explicit overrides,
  real 4x pixels, texture switching, preference persistence and classic isolation.
- [x] Add saved Auto/640x480/1280x960 selector and actual resolution FPS display.
- [x] Run pacing/layout/input/native integration suites and fix regressions.

### Task 3: Delivery

- [x] Fresh read-only review and full APK pipeline including default-stage checks.
- [x] Update docs/version/test report; verify signer, ARM64 assets and original source.
- [x] Commit/push android-port; upload verified APK privately and read metadata back.

## Execution record

- Native tests first failed linking the absent scaled entry points, then passed
  under ASan/UBSan with quarter-position, whole-image and bounds regressions.
- Godot tests first failed the absent screen-aware selection assertion. The final
  44 checks pass, including real stretched/portrait windows and touch-opened popup
  navigation/save/reopen. Existing layout163 and full pipeline suites also pass.
- Independent fresh read-only review found no Critical or Important findings.
- Native CPU timings, exact artifact checksum/size and verification limits are
  recorded in `docs/test-report.md`. No Android device performance claim is made.
- Private upload metadata matches the exact 84,169,025-byte APK and owner-only
  permissions. Source remains on the dedicated android-port development branch.
