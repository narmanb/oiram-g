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
