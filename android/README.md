# Oiram native Android port — private test build

This is a playable Godot 4.6.3 application powered by the original Oiram C game
engine. It loads the original twelve-stage Default Pack, uses original sprites,
and needs no calculator ROM, OS or emulator. Original calculator sources remain
in the repository's `src/` tree, unchanged.

Build/install instructions: [Android build](../docs/android-build.md).
Engine preservation and timing limits: [engine audit](../docs/engine-port.md).
Pack format and editor: [format/editor notes](../docs/pack-format.md).
Verification record: [test report](../docs/test-report.md).

## Playing

Open Play from the pack menu. Touch controls support simultaneous directions,
Jump, Run and Special. Settings save mirrored controls, opacity, size and
remapped gamepad action buttons. **Show touch controls** defaults on; turn it off
to hide the gameplay buttons while using a controller. Menu and Pause buttons
remain touchable with that setting off. Default gamepad controls are left stick/D-pad,
A Jump, B Run, X Special, Start Pause. Keyboard: arrows, Z Jump, X Run,
C Special, Escape Pause. The original alternate scheme and secret codes are
available in Settings. Gameplay is silent, matching the calculator game.

Pause to restart a stage, open settings or save and return to the menu. Progress
is associated with each pack's SHA256 content ID. Backgrounding pauses and saves;
returning requires Resume. After process death the current stage restarts with
saved lives, coins, score and form; this is a checkpoint rather than a live object
snapshot. Transient star/slide flags are not saved without their timers. Reset
progress is available in Settings. Game over resets stats and stage unlocks to
the original 15-life starting adventure.

Import compatible `.8xv` packs with Import pack. Validation runs before a pack
enters app storage. Custom graphics AppVars are not imported; compatible level
packs use the original tiles and sprite set supplied with this build.

## Touch layout and display settings (0.1.2)

Open **Settings → Edit touch layout** from the title or paused game. Drag the
D-pad by its group outline/center and drag Jump, Run and Special individually.
**Save** keeps the arrangement; **Cancel** discards edits; **Reset** restores the
current orientation's defaults. Landscape and portrait positions are saved
separately, work with mirroring, and are clamped inside the screen at the selected
button size. Gameplay stays paused while arranging controls. Controls may overlap
if you place them that way; the visually topmost button receives the tap.

**60 FPS smooth** is the default presentation target. It interpolates original
sprite/camera positions between fixed gameplay updates, preserving the current
game speed and C physics. **30 FPS classic** uses the original framebuffer cadence.
**Show FPS** displays the measured engine frame rate in game; reaching the target
depends on the device's rendering performance, refresh rate and power settings.
The original animation cadence remains unchanged.

In **0.1.3**, smooth mode uses a 640x480 presentation canvas: sprites and camera
can move by half an original pixel, while each original artwork pixel stays a
sharp 2x2 block. This removes a source of repeated/stepped positions in the older
320x240 interpolator. Gameplay still updates at the same 30 Hz. Classic mode
retains the original 320x240 framebuffer.

With Show FPS enabled, the overlay also reports mean callback interval, p95
interval (95% of the recent intervals are at or below it), and the percentage
over 1.5 times the selected frame budget. At steady 60 FPS, intervals are about
16.7 ms; spikes reveal pacing problems hidden by an average FPS counter. The
window covers the latest 180 foreground intervals and resets on pause/resume.
These measure application callback pacing, not Android's display compositor.

## Editing

The built-in editor offers a tile/object palette, paint/erase, unique spawn,
enemies and power-up blocks, dimensions/background/scroll, add/remove stages,
pan/zoom, undo/redo, local save/load, `.8xv` import/export and Test. Save the editor
pack to make it appear in the game pack picker. Existing pipe/door records are
preserved, displayed and remapped on resize. **Creating new warp pairs is still
remaining work.** Desktop editor password hashes round-trip, but its edit-lock
UI is not enforced. Editing is best in landscape. See the format notes for bounds
and the original-editor interoperability test.

## Validation limits

This is a private testing build, not a device-certified release. Automated tests
exercise all default stages and original mechanics, but do not establish that a
human has cleared all twelve stages on an Android device. Samsung Galaxy S25 Plus
and Retroid Pocket 5 testing, Android document-provider interoperability, physical
controller mapping and calculator timing calibration remain outstanding. The
simulation uses a documented 30 Hz baseline; source alone cannot establish the
original calculator's wall-time loop rate. Native Android menus replace the
calculator's menu/transition presentation. No public APK release is created.
