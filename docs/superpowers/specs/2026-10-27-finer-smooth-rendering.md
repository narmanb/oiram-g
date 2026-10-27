# Finer smooth rendering

The user reports that 30 FPS feels like 20 and 60 FPS feels like 30 despite a
steady 60 FPS counter. They prefer finer presentation and keeping simulation Hz
unchanged. Earlier autonomous-work instructions apply; proceed without another
design confirmation. No on-device frame-time measurements are available here.

## Approach and scope

Keep original 30 Hz C simulation and original 320x240 classic rendering. Add a
640x480 indexed smooth framebuffer that replays the existing captured commands
with positions rounded only after multiplying by two. Each artwork pixel remains
a sharp 2x2 block; independent actors and camera can move by half an original
pixel. This is a bounded first improvement, not a claim of arbitrary subpixel
precision or a complete GPU renderer. Keep the old interpolation API for tests
and comparisons. Preserve draw order, palette, map snapshots, clipping, stable
object IDs, teleport resets and overflow fallback. Presentation must not modify
native game state or the original framebuffer.

Alternatives: a GPU command renderer would offer arbitrary display positioning
and less pixel copying but requires a broader texture/clip/lifetime bridge;
changing simulation to 60 Hz would change tick-dependent calculations and is
explicitly deferred. Whole-frame filtering cannot independently move actors and
would blur the artwork. A 2x CPU replay is the smallest isolated way to prove
that removing the old pixel-grid restriction improves intermediate frames.

Show rolling mean/p95 frame intervals and late-frame percentage under the
existing optional FPS display. Use monotonic foreground frame intervals, reset
on pause/resume and presentation changes, and exclude inactive/background time.
These are application callback timings, not Android compositor instrumentation.
Do not tune refresh rates without measurements. Benchmark host CPU work to
identify avoidable overhead, while reporting that phone pacing still needs the
user's test. No shell-assist or unrelated feature in this update.

Ship a private debug APK with incremented version code, same signing identity,
and the classic mode available. Verify actual output and upload privately.
