extends SceneTree

const Main = preload("res://scripts/main.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	check(ClassDB.class_exists("OiramEngine"), "Native engine is registered")
	if failures:
		quit(1)
		return
	var shell = Main.new()
	root.add_child(shell)
	shell.set_process(false)
	shell.store.path = "user://native_integration_test.json"
	shell.store.clear_files()
	shell.store.data = {"version": 1, "packs": {}, "settings": {}}
	check(shell.packs.size() > 0, "Default pack is installed")
	var levels: Array = shell.packs[0].levels
	check(levels.size() == 12, "All twelve stages are present")
	# Shared binary fixture lets the sanitised C harness traverse the actual pack.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../build"))
	var fixture = FileAccess.open("res://../build/native-fixtures.bin", FileAccess.WRITE)
	check(fixture != null, "Native fixture file is writable")
	if fixture != null:
		fixture.store_8(levels.size())
		for level in levels:
			fixture.store_8(level.width)
			fixture.store_8(level.height)
			fixture.store_8(level.scroll)
			fixture.store_16(level.color)
			fixture.store_16(level.warps.size())
			for warp in level.warps: fixture.store_32(warp)
			fixture.store_buffer(level.tiles)
		fixture.close()
	for index in levels.size():
		print("Integration: configuring default stage %d (%dx%d, scroll=%d)" % [index + 1, levels[index].width, levels[index].height, levels[index].scroll])
		shell._start(index)
		print("Integration: stage %d configured" % [index + 1])
		check(shell.running and not shell.paused, "Stage %d starts in the shell" % [index + 1])
		var state: Dictionary = shell.engine.state()
		check(int(state.level) == index, "Native stage %d is configured" % [index + 1])
		check(shell.engine.frame().size() == 320 * 240 * 4, "Stage %d produces full LCD RGBA" % [index + 1])
		for tick in 150:
			var mask = 2 | 32
			if tick % 40 < 15: mask |= 16
			shell.controls.set_touch(0, mask)
			shell._process(1.0 / 30.0)
			if shell.paused: break
		check(shell.engine.frame().size() == 320 * 240 * 4, "Stage %d remains renderable after movement" % [index + 1])
	shell._start(0)
	shell.store.data.packs.clear()
	shell._start(0)
	var screenshot = Image.create_from_data(320, 240, false, Image.FORMAT_RGBA8, shell.engine.frame())
	check(screenshot.save_png(ProjectSettings.globalize_path("res://../build/gameplay.png")) == OK, "Native first-stage framebuffer screenshot is saved")
	var first_state: Dictionary = shell.engine.state()
	shell.controls.set_touch(0, 2 | 32)
	for tick in 20: shell._process(1.0 / 30.0)
	check(shell.engine.state().x > first_state.x, "Shell forwards physical movement to native engine")
	var seconds_before: int = shell.engine.state().seconds
	shell.clock_last_usec = Time.get_ticks_usec() - 2100000
	shell._process(0.0)
	check(shell.engine.state().seconds == seconds_before - 2, "Countdown uses wall-clock seconds independently of simulation")
	shell._pause("PAUSED")
	var paused_state: Dictionary = shell.engine.state()
	shell._process(20.0)
	check(shell.engine.state() == paused_state, "Paused shell advances neither physics nor clock")
	shell.clock_last_usec -= 100000000
	shell._resume()
	shell._process(0.0)
	check(shell.engine.state().seconds == paused_state.seconds, "Resume drops suspended wall-clock time")
	# Original timer exhaustion enters the original death animation, then shell retries.
	shell.engine.advance_clock(601)
	var lives_before: int = shell.engine.state().lives
	for tick in 240:
		shell._process(1.0 / 30.0)
		if shell.engine.state().lives < lives_before: break
	check(shell.engine.state().lives == lives_before - 1, "Native death animation triggers one shell life decrement")
	check(shell.engine.state().seconds == 600 and not shell.engine.state().failed, "Death retries the stage with a fresh timer")
	var checkpoint = shell.store.progress(shell.packs[shell.selected].id)
	check(checkpoint.lives == lives_before - 1 and checkpoint.level == 0, "Death retry checkpoint persists remaining lives")
	# Exhausting the final life stops at a reviewable game-over panel with a reset save.
	shell.checkpoint = {"lives": 1, "coins": 4, "score": 500, "flags": 0}
	shell._begin_level(levels[0])
	shell.engine.advance_clock(601)
	for tick in 240:
		shell._process(1.0 / 30.0)
		if shell.terminal: break
	check(shell.terminal and shell.paused, "Final death presents game over")
	checkpoint = shell.store.progress(shell.packs[shell.selected].id)
	check(checkpoint.lives == 15 and checkpoint.level == 0 and checkpoint.score == 0, "Game over persists a new fifteen-life adventure")
	shell._checkpoint()
	check(shell.store.progress(shell.packs[shell.selected].id).lives == 15, "Terminal save cannot restore exited engine statistics")
	shell._toggle_pause()
	check(shell.paused, "Game-over engine cannot be resumed by Start or Escape")
	# Three seconds of native simulation must be independent of render frequency.
	var tiles = PackedByteArray()
	tiles.resize(40 * 10)
	tiles.fill(27)
	for x in 40: tiles[9 * 40 + x] = 13
	tiles[8 * 40 + 2] = 240
	var safe_level = {"width": 40, "height": 10, "tiles": tiles, "warps": PackedInt32Array(), "scroll": 0, "color": 0xD77E, "index": 0, "count": 1}
	var reference: Dictionary = {}
	shell.testing = true
	for render_rate in [30, 60, 120, 144]:
		shell.checkpoint = {"lives": 15, "coins": 0, "score": 0, "flags": 0}
		shell._begin_level(safe_level)
		shell.controls.set_touch(0, 2 | 32)
		for frame_index in render_rate * 3:
			shell.clock_last_usec = Time.get_ticks_usec()
			shell._process(1.0 / render_rate)
		var state: Dictionary = shell.engine.state()
		if reference.is_empty(): reference = state
		check(state == reference, "Native held-input simulation matches after three seconds at %d render Hz" % render_rate)
	shell.settings.secret_code = 1337
	shell.checkpoint = {"lives": 15, "coins": 0, "score": 0, "flags": 21}
	shell._begin_level(safe_level)
	check(shell.engine.state().flags == 17, "Stage restart clears temporary star invulnerability")
	shell.checkpoint.flags = 0
	shell._begin_level(safe_level)
	var secret_frame: PackedByteArray = shell.engine.frame()
	shell.settings.secret_code = 0
	shell._begin_level(safe_level)
	check(shell.engine.frame() != secret_frame, "Original secret code reaches native sprite selection")
	shell.store.clear_files()
	shell.queue_free()
	await process_frame
	print("Native shell integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
