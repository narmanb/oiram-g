# Higher-resolution smooth rendering

The user explicitly asked to start, permits increased rendering resolution, and
wants gameplay Hz unchanged. Preserve the 320x240 logical play area, original
artwork, C physics and 30 Hz simulation. Build and privately deliver a test APK.

Extend the existing isolated replay rasterizer to integer scales 2 and 4:
640x480 half-source-pixel and 1280x960 quarter-source-pixel positioning. Prefer
these even scales so halfway motion remains representable at either setting.
Round each actor/camera/clip coordinate only after applying the selected scale;
nearest-neighbor artwork must remain sharp. Replay already captured game commands,
not a completed small framebuffer. Keep old native entry points backward compatible.

Settings offers Auto, 640x480 and 1280x960 for smooth mode. Auto selects 4x when
the gameplay image occupies more than 640x480 physical display pixels, otherwise
2x. Account for Godot canvas/window stretching rather than virtual UI size alone.
Persist the selection and safely switch/rotate without advancing game state.
Classic mode always uses 320x240 and retains the resolution preference for later.
Show the actual render dimensions in the existing optional FPS overlay.

This is the smallest extension of the proven rasterizer; a GPU renderer could
eventually avoid larger pixel copies but needs a broader texture/lifetime bridge.
Do not add higher frame caps, change Android display Hz, add interpolation artwork,
or implement shell assistance in this update. Higher resolution alone is not a
guarantee of improved phone smoothness. Keep the lighter choice available and
measure host work without presenting host numbers as Android measurements.

Validation must demonstrate distinct quarter-pixel actor/camera positions,
whole-image alpha1/fallback equality at both scales, clipping bounds, snapshot and
teleport behavior, unchanged native state, safe invalid scales, saved preferences,
actual scaled-window auto selection, rotation and classic/smooth transitions.
Run the full APK pipeline, verify same signer and package, preserve original
calculator source and upload privately rather than publishing copyrighted assets.
