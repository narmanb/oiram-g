extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var save_script = load("res://scripts/save_store.gd")
	var controls_script = load("res://scripts/controls.gd")
	check(save_script != null, "Checkpoint store exists")
	check(controls_script != null, "Semantic control adapter exists")
	if save_script == null or controls_script == null:
		quit(1)
		return
	var save = save_script.new()
	save.path = "user://shell_test.json"
	save.clear_files()
	var pack_id = "a".repeat(64)
	save.set_progress(pack_id, {"level": 2, "unlocked": 4, "lives": 13, "coins": 7, "score": 1200, "flags": 3})
	check(save.flush(), "Checkpoint writes atomically")
	var reopened = save_script.new()
	reopened.path = save.path
	reopened.load_data()
	check(reopened.progress(pack_id).get("level") == 2, "Checkpoint survives reopening")
	check(reopened.progress(pack_id).get("lives") == 13, "Checkpoint preserves remaining lives")
	save.set_progress(pack_id, {"level": 3, "unlocked": 4, "lives": 12})
	check(save.flush(), "Second checkpoint creates backup")
	var broken = FileAccess.open(save.path, FileAccess.WRITE)
	broken.store_string("{truncated")
	broken.close()
	reopened.load_data()
	check(reopened.progress(pack_id).get("level") == 2, "Corrupt primary recovers validated backup")
	check(reopened.progress("../bad").is_empty(), "Invalid pack IDs cannot access progress")
	reopened.set_progress(pack_id, {"level": -10, "lives": -10, "coins": -20, "unlocked": -1})
	check(reopened.progress(pack_id).get("lives") == 15, "Malformed progress resets safely")
	reopened.set_progress(pack_id, {"level": 2, "lives": 1000, "coins": 900, "score": 999999999, "flags": 1000})
	var bounded = reopened.progress(pack_id)
	check(bounded.lives == 99 and bounded.coins == 99 and bounded.score == 0xFFFFFF and bounded.flags == 19, "Checkpoint values respect native engine ranges and persistent form bits")
	reopened.set_progress(pack_id, {"level": 0, "lives": 15, "flags": 21})
	check(reopened.progress(pack_id).flags == 17, "Star invulnerability is not persisted without its timer")
	reopened.set_progress(pack_id, {"level": 0, "lives": 15, "flags": 9})
	check(reopened.progress(pack_id).flags == 1, "Slide state is not persisted across stage restart")
	reopened.set_progress(pack_id, {"level": {}, "lives": [], "coins": {}, "score": [], "flags": {}})
	bounded = reopened.progress(pack_id)
	check(bounded.level == 0 and bounded.lives == 15 and bounded.coins == 0 and bounded.score == 0 and bounded.flags == 0, "Malformed field types recover safely")
	var controls = controls_script.new()
	root.add_child(controls)
	controls.set_touch(1, controls.LEFT)
	controls.set_touch(2, controls.JUMP)
	check(controls.mask() == (controls.LEFT | controls.JUMP), "Independent fingers combine semantic actions")
	controls.set_touch(1, controls.RIGHT)
	check(controls.mask() == (controls.RIGHT | controls.JUMP), "Sliding finger changes direction without releasing jump")
	controls.release_all()
	check(controls.mask() == 0, "Suspension releases all held inputs")
	controls.enabled = true
	var key = InputEventKey.new()
	key.keycode = KEY_Z
	key.pressed = true
	controls._input(key)
	check(controls.mask() == controls.JUMP, "Keyboard Z is semantic jump")
	key.pressed = false
	controls._input(key)
	check(controls.mask() == 0, "Keyboard release ends jump")
	controls.alternate = true
	key.keycode = KEY_X
	key.pressed = true
	controls._input(key)
	check(controls.mask() == controls.SPECIAL, "Original alternate Alpha-equivalent key selects special")
	key.pressed = false
	controls._input(key)
	key.keycode = KEY_C
	key.pressed = true
	controls._input(key)
	check(controls.mask() == controls.JUMP, "Original alternate Up-equivalent key selects jump")
	key.pressed = false
	controls._input(key)
	key.keycode = KEY_Z
	key.pressed = true
	controls._input(key)
	check(controls.mask() == controls.RUN, "Original alternate 2nd-equivalent key selects run")
	controls.free()
	save.clear_files()
	var main_script = load("res://scripts/main.gd")
	check(main_script != null, "Main shell parses without native engine")
	var shell = main_script.new()
	root.add_child(shell)
	shell.set_process(false)
	await process_frame
	check(shell.get_viewport().gui_get_focus_owner() is BaseButton, "Menu starts with a focused control for gamepad navigation")
	check(shell.packs.size() >= 1, "Bundled default pack appears in pack picker")
	# Exercise responsive geometry with real controls, independent of native gameplay.
	shell.size = Vector2(960, 640)
	shell._layout()
	check(is_equal_approx(shell.screen.size.x / shell.screen.size.y, 4.0 / 3.0), "Landscape LCD remains undistorted")
	for region in shell.touch_regions:
		check(not shell.screen.get_rect().intersects(Rect2(region.center - Vector2.ONE * region.radius, Vector2.ONE * region.radius * 2)), "Landscape touch button remains outside the LCD")
	shell.size = Vector2(640, 960)
	shell._layout()
	check(is_equal_approx(shell.screen.size.x / shell.screen.size.y, 4.0 / 3.0), "Portrait LCD remains undistorted")
	shell.testing = true
	shell.running = true
	shell.paused = false
	shell.controls.enabled = true
	shell.controls.set_touch(8, controls_script.JUMP)
	shell.accumulator = 20.0
	shell.clock_accumulator = 30.0
	shell._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(shell.paused, "Backgrounding pauses the session")
	check(shell.controls.mask() == 0, "Backgrounding releases held fingers")
	check(shell.accumulator == 0.0 and shell.clock_accumulator == 0.0, "Backgrounding discards catch-up debt")
	shell._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(shell.paused, "Returning from background stays paused")
	shell._resume()
	check(not shell.paused and shell.accumulator == 0.0, "Explicit resume starts without catch-up")
	var pause_key = InputEventKey.new()
	pause_key.keycode = KEY_ESCAPE
	pause_key.pressed = true
	shell.controls._input(pause_key)
	check(shell.paused, "Physical pause shortcut opens pause menu")
	shell.controls._input(pause_key)
	check(not shell.paused, "Physical pause shortcut resumes from pause menu")
	shell._pause("PAUSED")
	shell._settings_menu()
	shell.controls._input(pause_key)
	check(shell.paused, "Physical pause shortcut does not resume behind settings")
	shell.terminal = true
	shell._pause("GAME OVER")
	shell._toggle_pause()
	check(shell.paused, "Pause shortcut cannot resume an exited native level")
	shell.running = false
	shell._open_editor()
	check(is_instance_valid(shell.editor) and shell.editor.visible, "Editor opens from menu")
	var original_editor_pack: Dictionary = shell.editor.pack.duplicate(true)
	shell.editor.pack.levels[0].tiles.fill(27)
	shell.editor.dirty = true
	shell._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(shell.editor.visible and shell.editor.dirty, "Android Back respects the editor refusal to discard invalid unsaved work")
	shell.editor.set_pack(original_editor_pack)
	# A clean editor exercises the same save/back route without altering user work.
	shell.editor.dirty = false
	shell._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not shell.editor.visible, "Android system Back exits through the editor back handler")
	if shell.engine != null:
		shell.store.path = "user://shell_test_session.json"
		shell.store.data = {"version": 1, "packs": {}, "settings": {}}
		shell._start(0)
		check(not shell.editor.visible and shell.running, "Gameplay after editor Back has no editor intercepting touch")
		shell.store.clear_files()
	shell.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: checkpoint recovery, semantic inputs, responsive LCD, pause-safe lifecycle")
	quit(0 if failures.is_empty() else 1)
