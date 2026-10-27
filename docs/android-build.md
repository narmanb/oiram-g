# Android private testing build

This port compiles the original C gameplay through a portable framebuffer adapter
and a Godot GDExtension. It does not use a calculator ROM, OS, or emulator. The
Godot shell uploads the 320×240 RGBA framebuffer with nearest filtering. The
simulation baseline is 30 ticks per second; countdown time advances separately.
Timing still needs calibration against the original calculator.

The APK is for private testing. Original Nintendo artwork remains subject to its
owners' rights; retain the original repository license and attribution. This
workflow does not create a public release or upload an APK to an app store.

## Build on Linux x86_64

Install Python 3.12, Git, curl, unzip, and a C/C++ toolchain. Setup downloads
Temurin OpenJDK 21.0.8+9 when a JDK is absent; an existing OpenJDK 17/21 works.
Then run from the checkout:

```sh
export OIRAM_TOOLS_DIR="/workspace/tools" # or another writable directory
./scripts/setup-android.sh
./scripts/build-apk.sh
```

Setup accepts the Android SDK licenses and installs dependencies outside the
checkout. Build output defaults to `build/oiram-arm64-debug.apk`. An optional
first argument to `build-apk.sh` chooses another APK path. Set `GODOT` to an
existing Godot 4.6.3 executable, `ANDROID_HOME` to the SDK directory, and `JOBS`
to adjust compile concurrency. No paid services or API credentials are used.

The toolchain pins are:

| Component | Version |
| --- | --- |
| Godot editor and Android templates | 4.6.3 stable |
| godot-cpp | `godot-4.5-stable`, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` |
| SCons | 4.9.1 |
| Downloaded fallback JDK | Temurin 21.0.8+9 |
| Pillow | 11.3.0 |
| Android command-line tools | 19.0 / archive 13114758 |
| Android build tools | 35.0.0 (inspection), 36.1.0 (Godot Gradle template) |
| Android platforms | API 35 and 36 |
| Android platform tools | 35.0.2 |
| Android NDK | 28.1.13356709 |

The stable Godot 4.5 GDExtension ABI is supported by the Godot 4.6.3 runtime.
The native engine stores one global game session; create one `OiramEngine`
instance per application and configure it when changing levels or packs.
The setup script verifies the downloaded command-line tools, platform tools,
engine, and export template checksums. SDK-managed packages are obtained from
Google's versioned repository. The SDK platform revision may receive upstream
metadata updates. Debug signing creates a local standard Android debug key;
rebuilding with a different debug key requires uninstalling the previous APK.
Builds are repeatable from these inputs, but debug signatures and ZIP timestamps
are not promised to be byte-for-byte deterministic.

`scripts/prepare-native.py` applies asserted portability and safety changes to
generated copies of the original C files. `scripts/convert-assets.py` converts the
original PNG assets into indexed arrays without modifying `src/` or `extra/`.
Generated files, intermediate objects, SDKs and binaries are ignored by Git.

For desktop integration or native-only builds:

```sh
./scripts/build-native.sh linux
./scripts/build-native.sh android
```

The extension binaries are written to `android/bin/`. Default builds use
`template_debug`; an optional second argument selects `template_release`.
The Android extension is linked for 16 KiB page alignment.
The official Gradle source template supplies Gradle 8.11.1, Android Gradle Plugin
8.6.1 and Kotlin 2.1.21. Its generated config uses the installed NDK 28.1 for
native library stripping; the prebuilt Godot runtime is unchanged. Gradle's
compile SDK is 36 while the exported application's target remains 35. Generated
Gradle files live under the ignored `android/.android-build/` directory.

## Inspect and install

`build-apk.sh` runs the C gameplay and render-interpolation suites with
AddressSanitizer and UndefinedBehaviorSanitizer, then the full pack codec mutation
suite, shell, native integration, real touch input, draggable-layout/FPS and editor
Godot suites. Another sanitizer suite exercises the decoded default stages and
checks interpolated output against original frames. Failed checks stop export. It verifies the APK
signature, minimum and target SDKs, and 16 KiB ZIP alignment, and checks
that all native libraries are ARM64 and that the Oiram extension is included,
and rejects an Internet permission. The preset uses Android 13/API 33 minimum,
API 35 target, ARM64 only, and disables Internet and broad storage permissions.

Enable USB debugging on an ARM64 Android 13+ device, then run:

```sh
"${OIRAM_TOOLS_DIR:-/workspace/tools}/android-sdk/platform-tools/adb" devices
"${OIRAM_TOOLS_DIR:-/workspace/tools}/android-sdk/platform-tools/adb" install -r build/oiram-arm64-debug.apk
"${OIRAM_TOOLS_DIR:-/workspace/tools}/android-sdk/platform-tools/adb" shell monkey -p org.oiram.private_testing 1
```

Physical-device testing should cover touch controls, simultaneous run/jump,
gamepad mapping, foreground/background pause, file import through Android's
document picker, and progression after force-stop. Host tests and APK inspection
cannot establish physical-device usability or frame timing.

## Manual CI

`.github/workflows/android.yml` runs only through `workflow_dispatch`. It installs
the pinned dependencies, builds the debug APK, and checks it. APK upload is
explicitly disabled for public repositories. A private fork can upload a seven-day
`oiram-arm64-private-testing` Actions artifact. It has read-only repository
permissions and creates no release. Artifact access follows the repository's
visibility and GitHub access controls. The upstream `narmanb/oiram-g` repository
is public: use the local APK or a private fork for private testing downloads.
No push or pull-request event starts this workflow automatically.
