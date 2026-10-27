# Retained engine and fidelity audit

The original calculator tree (`src/`, `extra/`, `readme.md`, `LICENSE`) remains
unchanged. The starting commit is `85d124f394c23d4ee0f5fd0235aef6275879c7b9`,
which matched upstream Oiram HEAD at inspection. The authoritative gameplay is
compiled C, not Godot physics. There is no ROM, calculator OS, instruction
interpreter, or emulated CPU.

## Original code used by the native build

| Source | Retained behavior |
| --- | --- |
| `src/oiram.c` | Integer movement, momentum thresholds, deceleration/ice, jumping and release, gravity, crouch, slopes/sliding, swimming, vines, shells, raccoon spin/flying, pipes/doors, death motion and camera |
| `src/simple_mover.c` | Pixel collision sweeps, enemy gravity, smart ledge turns, bouncing and flying motion |
| `src/enemies.c` | Spawn marker conversion and all original enemy/pool initialization |
| `src/events.c` | Every original enemy event, boss, shell/stomp interactions, damage, item collection, invulnerability, projectiles, tile bumps and sprite timing |
| `src/powerups.c` | Mushroom, fire flower, star, leaf, form changes and blue switch effects |
| `src/tile_handlers.c` | Original 256-entry dispatch table; slopes, semisolids, hazards, vines, water, ice, quicksand, question blocks, bricks, blue switches, doors, pipe warps and goal pipes |
| `src/lower.c` | Original coin/life/score/chain rules and HUD placement |

`android/native/common.c` translates `src/common.s` tile dispatch, solid/empty
handlers, tile-to-pixel conversion and animation. Left/right testing sides,
bound checks, return values, four-tick animation cadence, four-frame/three-frame
tile cycles, sprite toggles and player index toggles are retained. The blue coin
animation uses original raw tiles 247–250, rather than indexing logical tile 234.
Generated PNG sprites are separate arrays, so animation selects original frames
instead of advancing pointers inside an AppVar blob.

`android/native/core.c` replaces the blocking menu/main loop and TI file loading
with configure/step/clock/frame/state functions. Godot owns pack selection,
checkpoints, touch/gamepad input, Android lifecycle, adapted menus and the editor.
The original splash delay, black-circle transitions and walking-goomba completion
screen are replaced by Godot panels. The original default pack order and gameplay
goals remain. Gameplay is silent: no sound/music playback implementation or audio
assets were found in the original game sources.

## Physics and controls

Values come directly from the C files: ordinary horizontal velocity 2 pixels per
tick, sprint velocity thresholds at momentum >5, >10 and >20, capped momentum 40;
normal jump velocity −11, release clamp −5 before the next gravity update, player
fall cap 8, mover fall cap 7. Collision boxes and per-pixel collision tests are
unchanged. No `CharacterBody2D`, Godot gravity, collision shapes or second physics
implementation exists.

Native input is semantic: directions, Jump, Run, Special. The original
`handler_keypad` maps 2nd to internal jump/door action, Alpha to run, and Up to an
edge-triggered special action. `handler_keypad_alternate` maps 2nd to run, Alpha
to special, and Up to jump/door. The keyboard equivalent uses Z=2nd, X=Alpha,
C=Up, and the saved alternate option rotates all three roles. Touch labels and
remappable gamepad buttons represent the semantic actions directly. D-pad Up
also requests the original jump/door action. Native code retains jump-release
clamping and special rising-edge semantics. Original Ans codes 1337, 1202, 505,
and 101 are available through the saved secret-code setting.

## Timing and viewport

The original `main.c` runs movement, tile drawing, events, countdown handling and
animation once per unthrottled loop. It has no fixed tick duration, VSync-based
game clock, elapsed-time movement scaling, or documented target FPS. Its
`clock()` countdown is separate and checks one-second deadlines. It is therefore
not possible to prove an original 60 FPS or 30 FPS rate from these sources.

This build explicitly uses a **30 Hz calibration baseline**, preserving integer
calculations per tick. Godot presentation is independent, with a floating-point
boundary tolerance and bounded catch-up after long foreground stalls. Native
state equality is tested under 30/60/120/144 Hz presentation schedules. Countdown
uses elapsed foreground wall time. Pause/background stops both clocks, releases
inputs and clears accumulated catch-up; returning requires Resume. Original
calculator wall-time parity remains unverified and requires hardware measurement.

The full LCD is 320×240. The original action area is only **320×128**, with HUD
and other lower LCD content underneath. Original camera limits, autoscroll and
enemy activation tests (±360 horizontal, ±160 vertical relative to player) are
retained. Godot nearest filtering scales the full LCD without aspect distortion.
No expanded simulation viewport is enabled. Vertical autoscroll enum values are
accepted for format compatibility but perform no vertical scrolling because the
original `scroll_map` only implements left/right.

## Necessary portability and memory adaptations

`scripts/prepare-native.py` generates build-only copies; it does not edit `src/`.
These changes address undefined or unsafe memory behavior rather than retuning
mechanics:

- List removal shifts only the remaining valid elements, avoiding one-past-array
  reads at full capacity.
- Coin-neighbor coordinates are checked before dereferencing the map.
- Tile-row pointer differences use pointer-sized arithmetic on ARM64.
- Allocated objects are zero-initialized; in particular original fireballs left
  their `smart` boolean unspecified.
- Removed movers skip the remainder of their callback, avoiding writes through a
  freed mover after pickup/invincible kills.
- Shell/chomper collision caches the poof coordinate before removing the chomper.
- Original pools may evict their currently executing object when full. Objects
  leave the original lists immediately; `memory.c` defers storage reclamation
  until callbacks finish at tick end. Pool capacities and eviction rules remain.
- Temporary bonus objects may originate a row above the map; empty padding and
  floor-divided tile coordinates make that valid without out-of-map collisions.
- NULL temporary-object origins return zero coordinates; callers then supply
  their actual location, avoiding undefined subtraction of unrelated pointers.
- Original 24-bit score wrapping is explicit after native ticks. Native timer
  and bounded level-coordinate values fit safely in standard 32-bit integers.

Player image copies in the original code copy 434 bytes even for small forms.
Generated sprites include padding so these original copies remain safe. Original
RLET boss PNGs are stored unpacked and drawn with identical transparent pixels;
no calculator compression format is required at runtime.

The C engine is a singleton, like the original global-state game. The Godot app
creates one engine and reconfigures it on stage/pack changes.

## Graphics and licenses

`scripts/convert-assets.py` reads all original `src/gfx/*.png` files, indexes their
233 distinct colors without palette reduction, splits the original tile sheet,
and retains the original logical tile remapping. LCD output uses the original
RGB1555 encoding (5-bit red/blue, 6-bit green for stored palettes). Index zero
becomes the stage background for tiles and is transparent for sprites. Godot
renders the resulting texture through its 2D renderer with nearest filtering.

The original BSD-3-Clause license applies to original Oiram code and is preserved
at repository root and bundled in `android/licenses/Oiram-LICENSE.txt`. Nintendo
artwork is not covered by that code license. This build is for private testing.
The HUD font data comes from CE Programming GraphX at toolchain commit
`a2e96f9aee3e73322dde81df5822988343bd9a6a`, `_DefaultTextData` and
`_DefaultCharSpacing` in `src/graphx/graphx.asm`; its LGPL-3.0/GPL-3.0 notices are
bundled in `android/licenses/`. Complete font source data and relinkable application
sources/build instructions are included. Godot/godot-cpp use their MIT licenses
and are fetched from the pinned upstream distributions described in the build doc.

## Smooth presentation added in 0.1.2

Simulation remains 30 ticks/second, with the same uncalibrated timing baseline
and original calculations. The default 60 FPS mode does real render-only
interpolation rather than advancing gameplay twice as fast or blending images.
`presentation.c` records each original C sprite/tilemap draw call, retains scalar
allocation-lifetime IDs and draw ordinals, and interpolates matched positions
and clipping/camera coordinates into a separate indexed framebuffer. Tilemap
data and animation aliases are snapshotted before events/animation mutate them.
The original current framebuffer is preserved; at alpha1 the replay matches it.
Positions are rounded to the original pixel grid, so very slow one-pixel moves
and original animation frames retain their discrete pixel/animation cadence.

New render IDs in `memory.c` are metadata only. Generated event code marks object
draw contexts and player/body/shell/tail channels; no mechanics are changed.
Removed objects leave no dangling entity pointer in frame history, and reused
allocations receive new IDs. Replay does not invoke event handlers or clocks.
The bounded command buffer falls back to the authentic current frame on overflow.
Nonfinite alpha is handled safely; presentation target/clip state is restored.
Configure, shutdown, resume and pipe/door teleport transitions clear history.
Large coordinate discontinuities also snap instead of interpolating.

GDExtension adds `frame_interpolated(alpha)` and `reset_interpolation()`. The shell
uses its fixed-step remainder to render intermediate positions in smooth mode,
sets Godot's target cap to 60, and displays measured `Engine.get_frames_per_second()`
when enabled. Classic mode caps at30 and uses `frame()`. Physics, countdown, enemy
activation, assets, pause behavior and saved progression are unchanged. Android
sustained FPS still requires physical-device measurement with the visible counter.
