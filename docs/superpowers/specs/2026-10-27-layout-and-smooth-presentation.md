# Movable touch layout and smooth presentation

The user wants to drag the D-pad as one unit, arrange Jump/Run/Special separately,
see actual FPS, and reach 60 FPS without changing the retained C gameplay speed.
Work on android-port; retain all previous input/physics guarantees and private APK delivery.

## UI

Settings opens Edit touch layout, with a live paused game preview (or default
preview from the title), four draggable handles (D-pad group and three action
buttons), Save, Cancel and Reset. Touch and desktop mouse both work. Persist
normalized positions separately for landscape and portrait; clamp entire control
bounds inside the usable viewport (below the pause bar) after size/rotation.
Keep mirrored-layout behavior meaningful and preserve saved size/opacity. Editing
must not send gameplay actions or advance simulation, and Back must cancel safely.
Existing Show touch controls setting remains; editing temporarily previews controls.

Settings also offers Show FPS and 30 FPS classic / 60 FPS smooth, default 60.
FPS is measured, not a hardcoded target. The target controls Godot presentation;
retained simulation stays at 30 original-speed ticks/sec. Smooth mode draws
intermediate sprite/camera positions, not duplicate frames or image cross-fades.
Pause/resume, stage changes and warps must not interpolate across discontinuities.

## Native rendering

Record original C tilemap/sprite draw commands per tick with stable entity IDs
(allocation lifetime IDs + draw ordinal). Replay current commands at interpolated
positions and camera scroll, with current pixel assets and original clipping;
never call gameplay handlers during presentation. A separate output buffer keeps
render calls from mutating original framebuffer or state. Animation/power-up/tile
changes remain at original cadence. Clamp alpha, reject teleport/size mismatches,
use bounded command storage with a safe current-frame fallback, and reset history
on configure/shutdown/resume. Tests compare classic alpha1 framebuffer bytes and
state before/after presentation, intermediate object/camera pixels and original
movement trajectories. This is smooth 60 FPS presentation, not claimed 60Hz physics.

## Boundary

OiramEngine adds frame_interpolated(alpha: float)->PackedByteArray RGBA320x240
and reset_interpolation()->void. Existing frame(), step(), state(), configure()
remain compatible. The shell passes accumulator/TICK as alpha only in smooth60;
classic30 uses frame(). Native C still owns all mechanics and rendering decisions.

## Delivery

Run meaningful native/render/UI/layout regressions and the full build pipeline,
export Android ARM64 version0.1.2-private/code3 using the existing signing key,
commit/push and deliver the APK privately through connected Google Drive. No
public release or workflow dispatch. Physical sustained 60 FPS on the user's
phone cannot be guaranteed without device testing; the FPS display exposes it.
