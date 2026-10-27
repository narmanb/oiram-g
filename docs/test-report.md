# Private test build verification

## Automated and host verification

- Original calculator source and bundled default pack preservation: compare
  `git diff 85d124f -- src extra readme.md LICENSE` and
  `cmp extra/OiramPK.8xv android/assets/OiramPK.8xv`.
- `scripts/test-native.sh`: AddressSanitizer/UndefinedBehaviorSanitizer checks
  original movement, momentum thresholds, jump/release/apex/landing, collision
  bounds, tile coordinates, score/coin/life rules, form changes and damage,
  leaf/spin, fireball edge triggering, stars, enemy motion, timer expiry, sprite
  output and full-capacity pool removal. Targeted regressions reproduce and
  prevent shell/chomper and full generator/mover pool use-after-free.
- `res://tests/test_packs.gd`: **21,423 checks** in the latest full codec run,
  covering every default-pack truncation, every single-byte mutation with repaired
  checksum, structured RLE/header/offset/string/warp/capacity errors, CD/CE data,
  large-map encoding and round trips. An optional pinned original-editor C source
  interoperability test loads Godot output in the original editor and parses its
  resaved output back in Godot, comparing all levels/tiles/warps/colors.
- `res://tests/test_shell.gd`: checkpoint writes/reopening, backup recovery,
  malformed save fields, persistent form flags, multi-touch and sliding input,
  normal and original alternate keys, focused gamepad menu navigation,
  physical pause/resume, background release, aspect ratio/layout and editor Back
  navigation without an invisible gameplay session behind the editor.
- `res://tests/test_native_integration.gd`: **70 checks**, including all twelve
  stages configured through the real GDExtension, original framebuffer output,
  movement, independent countdown, pause/resume, death/retry/lives/game over,
  saved stats, secret-code sprites and equal native states at presentation
  schedules of 30, 60, 120 and 144 Hz. It emits real decoded default fixtures.
- `scripts/test-default-native.sh`: **96 sanitizer scenarios** across all twelve
  default stages, four forms, both horizontal directions, jump/run/special/crouch
  inputs, up to 1,800 ticks per scenario or original stage exit.
- `res://editor/test_editor.gd`: **32 checks** for original tile/object palette,
  paint/erase/spawn, touch drag painting/pan, undo/redo, resize/warp remapping,
  stage operations, local save/load, test signal, SAF URI preservation, bounded
  import and largest-map fit.
- Actual host renders captured through Godot GL compatibility on Xorg dummy with
  llvmpipe: menu, landscape gameplay and portrait gameplay. Original native
  framebuffer screenshots were also inspected. These are real engine captures,
  not mockups.

The build pipeline runs these suites and stops on nonzero exit status or logged
Godot script/errors. The pipeline's codec run may have a different check count
when the optional external original-editor source path is absent; the required
parser/error suite remains enabled.

## APK checks

`build-apk.sh` exports an actual debug-signed APK after tests and verifies:

- Android minimum API 33 (Android 13), target API 35;
- only ARM64 native libraries, including the Oiram GDExtension and Godot runtime;
- signature via Android `apksigner`;
- 16 KiB native library page/ZIP alignment;
- default pack, original graphics, scripts, extension registration and license
  notices included in the exported project;
- no Internet permission or broad external-storage permission.

The APK checksum and exact artifact size are recorded in `build/apk-report.txt`
when the final artifact is assembled. Build outputs and test captures are ignored
by Git; the APK is delivered separately for private testing.

## Not performed

No connected Android device was available. Emulator tools were installed, but
hardware acceleration reports no VMX/SVM support and `/dev/kvm` is unavailable.
No Android emulator execution or physical Galaxy S25 Plus/Retroid Pocket 5 test
is claimed. The host screenshots/simulated input tests do not substitute for
Android touch, controller, rotation, document-provider or suspend testing.

Original-calculator frame timing and a full human playthrough are unverified.
The source's unthrottled loop does not define a target rate, so the 30 Hz baseline
must be calibrated before claiming wall-time fidelity. The editor still lacks
new pipe/door-pair creation and desktop password-lock UI. These limitations are
explicit rather than placeholder gameplay.

## Touch input regression fix (0.1.1-private)

The first Android build disabled mouse-from-touch emulation. Custom gameplay
controls handled native fingers, but standard Godot menu buttons received no
mouse click, so the title screen could not be operated by touch. Earlier tests
called menu callbacks directly and did not catch this Android input-path error.

Version 0.1.1 enables that UI bridge, filters duplicate synthetic mouse events
from the custom gameplay/editor finger handlers, and adds a persistent
Show touch controls setting (on by default). Hiding gameplay controls leaves
menu/Pause taps and gamepad/keyboard input active. The new test_touch.gd injects
actual ScreenTouch events through Input.parse_input_event and verifies Settings,
the saved toggle, Play, Pause, Resume and simultaneous steering/run/jump. The
previous setting reproduces the menu failure; the corrected setting passes.
This is host input-path verification; physical Android retesting remains needed.

The v0.1.1 build passes 35 actual-input touch checks, 70 native integration checks,
32 editor checks, the full pack suite, native sanitizer regressions and all 96
default-stage sanitizer scenarios. Exported APK SHA256: `9397dc58919ecebe12610872783e8da1cf132e39e0f28405cb5ba2cbb2252401`.
Version code 2 uses the same signing certificate as the initial build.

## Layout and smooth presentation (0.1.2-private)

- `test_layout.gd`: 163 checks for grouped D-pad dragging, independent action
  anchors, real touch/mouse events, normalized landscape/portrait save/reopen,
  mirror/clamping including maximum button size and narrow windows, Save/Cancel/
  Reset/Back, paused input isolation, hidden overlay preference, overlap hit
  priority, measured FPS toggle, 30/60 option persistence and native render choice.
- `scripts/test-presentation.sh`: ASan/UBSan checks actual midpoint sprite pixels,
  intermediate camera scroll, snapshots against post-draw tile/animation changes,
  finite/clamped alpha, teleport snapping, allocation-ID reuse, bounded-buffer
  fallback, classic alpha1 equality, unchanged native framebuffer and unchanged
  game state across repeated render-only calls. A visible short door warp failed
  without history clearing and passes with it.
- The 96 default-stage sanitizer scenarios additionally sample interpolated
  presentation across all default levels/forms and assert alpha1 framebuffer
  equality and unchanged game state.

These are host automated checks. They establish the rendering/simulation separation
and unchanged mechanics; they do not establish sustained physical-device 60 FPS.
The new in-game counter exposes the device's actual frame rate.

Final v0.1.2 APK SHA256: `b31402b3b3684fc621a4e2ae38c2f557cddc5322f44f1cae9f4dfd2e36904fe4`; size 84158854 bytes. Version code3 uses the same signing certificate as v0.1.1.

## Finer presentation and timing diagnostics (0.1.3-private)

- Extended ASan/UBSan presentation tests assert a distinct half-pixel sprite
  position for a one-original-pixel move, half-pixel camera motion, clipped
  negative/right-edge sprites, alpha1 exact 2x framebuffer equality, nonfinite
  alpha, teleport/fallback behavior and unchanged GraphX clips/gameplay state.
- `test_pacing.gd`: 22 checks for steady versus uneven intervals with the same
  mean FPS, p95, late-frame threshold, bounded history, malformed sample rejection,
  reset/baseline behavior, real native 640x480 smooth images, live texture-size
  switches and unchanged state, and pause/resume integration.
- Default-stage scenarios now also sample fine rendering, comparing alpha1 to
  the authentic framebuffer and asserting unchanged gameplay state.
- `bash scripts/benchmark-presentation.sh` measures original and fine replay plus
  RGBA conversion on this host only, excluding GDExtension copying, Godot upload,
  display/compositor and Android thermals. A 1,200-frame run measured previous
  mean 0.116 ms / p95 0.230 ms, fine mean 0.270 ms / p95 0.446 ms. Both runs ended
  at identical native states. These figures are not phone FPS predictions.

The new renderer still uses original animation artwork and half-source-pixel
position resolution. Device smoothness and actual compositor pacing require
testing the APK on the user's phone. No simulation-frequency or refresh-rate
change is claimed.

The full v0.1.3 build passed the required 21,420 pack checks, 70 native-shell,
35 touch-input, 163 layout, 22 pacing and 32 editor checks, the shell suite,
native gameplay/presentation sanitizer suites and all 96 default-stage scenarios.
The default-stage fine comparison samples the first pixel of each enlarged block;
the isolated presentation suite additionally compares every pixel in all blocks.
Independent read-only review found no Critical or Important defects.

Final v0.1.3 APK SHA256: `fd8cd6be16124948c8362915d850b7bf3d97568233614bcd25b8846135161e67`;
size 84164177 bytes. Version code 4 has the same verified signing certificate as
v0.1.2. The exported ARM64 native library contains the new `frame_smooth` API.
