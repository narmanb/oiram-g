# Update ideas and mobile feedback

Recorded 2026-10-27. This is a discussion backlog, not an implementation promise
or an approved feature design.

## Current user priorities

- Investigate smoother motion and performance. The user is interested in visibly
  smoother 60 Hz presentation, not merely a higher reported FPS or faster gameplay.
- Optional automatic shell pickup and holding: pick up a nearby eligible turtle
  shell when empty-handed. Touchscreen manual pickup is difficult for the user.
  Keep manual controls available. Throwing behavior and preventing unintended
  pickup immediately after throwing still need a design decision.
- Keep the earlier quality-of-life and game-update suggestions for later.
- Higher presentation resolutions are acceptable when they help smoothness.
  The original logical play area and gameplay remain unchanged; this is permission
  to increase rendering precision, not a request to replace the original artwork.

## Verified constraints and possible next steps

- Version 0.1.2 caps smooth presentation at 60 rendered frames/second and
  interpolates between 30 simulation ticks/second. Sustained on-device frame
  pacing has not been measured here.
- The interpolated scene is rasterized into the original 320 by 240 framebuffer.
  Coordinates are rounded to whole source pixels. Consequently, a one-pixel move
  per simulation tick cannot display a distinct half-pixel intermediate position.
  This can remain visibly stepped even when the frame counter reads 60 FPS.
- Investigate display-resolution or subpixel positioning of individual sprites
  and camera movement, retaining nearest-neighbor artwork and authoritative C
  collision coordinates. This requires renderer work; translating or filtering
  the entire framebuffer is insufficient for independently moving objects.
- Measure frame times, display refresh and presentation cadence before identifying
  a performance bottleneck. A 60 FPS counter alone does not establish even pacing.
- A true 60 Hz gameplay simulation would require auditing and converting all
  tick-dependent movement, integer rounding, collision, timers and enemy behavior.
  Halving movement constants or running the current engine twice as often does
  not preserve behavior. Keep this distinct from smoother rendering.
- Original shell pickup (`src/oiram.c`, `pickup_shell`) already checks for an
  empty hand, a stationary red or green shell, and a facing-dependent pickup
  rectangle. It currently occurs on the Special button's press edge. A mobile
  assist should reuse this eligibility logic without synthesizing Special presses
  that could also throw a shell, fire a fireball or trigger a tail attack.

## Earlier assistant suggestions, deferred

These are suggestions, not user-approved scope:

- Exact mid-stage suspend/resume, beyond current stage checkpoint saves.
- Multiple control presets, individual action-button sizes and optional automatic
  touch-control hiding when a gamepad connects.
- Cleared-level selection, personal records and multiple save slots per pack.
- Frame-time diagnostics, quick retry and optional adjustable vibration.
- Time trials with ghost replays.
- Finish mobile-editor warp creation/linking, then selection/copy/move tools.
- An additional campaign using existing mechanics.
- Optional challenge modes with separate records.
- Optional original or properly licensed audio, retaining silent mode.
- Any future altered physics or new mechanics should have an explicitly selected
  enhanced mode so faithful original gameplay remains available.

Suggested earlier order was suspend/resume and time trials, then warp editing.
The user's latest interest puts presentation/performance and mobile shell pickup
ahead of that proposed order; no implementation order has been agreed.

## Follow-up on presentation

The user confirmed that smooth mode reads 60 FPS but feels only slightly smoother
and prefers the finer-position rendering approach while retaining current gameplay
Hz. Version 0.1.3 implements a bounded 2x presentation canvas (half-source-pixel
positions) and optional foreground frame-time diagnostics for device comparison.
Actual device benefit remains to be established. Shell assistance remains deferred.
The user is open to resolution increases beyond the current 640x480 smooth canvas.
Evaluate finer actor/camera positioning against frame-time and rendering cost
before adopting a higher default. Increasing output resolution alone does not
create extra motion samples or new animation frames.

The user then explicitly requested implementation. Version 0.1.4 adds saved
Auto/640x480/1280x960 choices, quarter-source-pixel placement at 4x, and actual
render dimensions in the FPS overlay. Auto uses physical display size; phone
frame pacing and perceived benefit still need comparison. Gameplay Hz and the
visible play area remain unchanged. Mobile shell assistance remains deferred.
