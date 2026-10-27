# Oiram native Android port

Implement the user specification on android-port; original src/ and extra/ remain intact. Native C is authoritative. Compile original oiram.c, enemies.c, events.c, powerups.c, simple_mover.c, tile_handlers.c, lower.c against a portable graphx compatibility layer. Translate common.s tile dispatch and animation literally. Godot 4.6.3 GDExtension wraps the engine. Original PNGs generate palette-indexed sprite data; a CPU framebuffer is uploaded as a nearest-filtered Godot texture. No ROM, OS, emulator, network, audio or added music.

## Approaches
Retaining the C core with GDExtension preserves mechanics and is selected under the user delegation. A GDScript rewrite creates unnecessary physics drift. Calculator emulation is explicitly excluded. Hardware-facing main.c and loadscreen.c are replaced by a cooperative lifecycle and validated pack parser.

## Timing
Original main.c is unthrottled, with physics per loop and clock countdown independent. No exact target rate exists in source. Use a documented 30 Hz simulation baseline with real elapsed countdown; calibration against physical calculator remains required. Preserve all integer constants, clipping, activation radius, 320x128 action area within the 320x240 LCD, animation every four ticks.

## Boundaries
OiramEngine.configure(level: Dictionary, progress: Dictionary) -> bool; step(input_mask: int) -> void; advance_clock(seconds: int) -> void; frame() -> PackedByteArray RGBA 320x240; state() -> Dictionary. level keys width,height,tiles (PackedByteArray),warps (PackedInt32Array of flattened 24-bit entry/exit values),scroll,color,index,count. progress keys lives,flags,coins,score. state includes x,y,vy,vx,momentum,flags,lives,coins,score,seconds,exit,completed,failed,level. Input bits left=1,right=2,up=4,down=8,jump=16,run=32,special=64. up is mapped into jump/door semantics.

OiramPack.load_bytes(bytes)->Dictionary returns {ok,error,name,author,levels:Array[Dictionary]}; encode(pack)->PackedByteArray returns compatible .8xv; native engine only accepts decoded validated maps. Pack ID is content SHA256. Save progression per pack using atomic replace plus backup. Suspend pauses engine and releases input; resumes paused, no catch-up.

## Milestones
Prioritize playable default levels and ARM64 debug APK. Then pack import/selection and bounded built-in editor. Explicitly document incomplete editor or verification work. Do not publish releases or activate workflows repeatedly. Keep Nintendo artwork attribution and private-testing restriction.
