# Touch menu repair and saved gameplay-control toggle

The user reports a nonresponsive Android title menu and wants both gamepad and
toggleable touch controls. Reproduce finger taps through Godot Input, enable
mouse-from-touch for native widgets, and keep custom multi-touch handlers from
processing the synthetic mouse copy. Use the existing Settings screen for a
Show touch controls switch, default on and saved with other preferences.
When off, omit gameplay regions and painting, release held pointer actions,
and reclaim display space; retain menu/Pause touch, keyboard and gamepad input.
No native gameplay/physics changes. Version the update 0.1.1-private/code2 and
sign with the existing debug key so it installs over code1 without deleting data.

Verification: fail the actual-input regression with the old project setting;
pass real touch navigation, persistence, on/off input behavior and three-finger
run/jump/steering after correction; run the existing suites and export/verify
an ARM64 APK, then deliver a new private Drive link rather than a workspace path.
