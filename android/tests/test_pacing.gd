extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func press_key(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event.duplicate())
	Input.flush_buffered_events()
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func tap(button: BaseButton) -> void:
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	var event = InputEventScreenTouch.new()
	event.position = root.get_final_transform() * button.get_global_rect().get_center()
	event.index = 0
	event.pressed = true
	Input.parse_input_event(event.duplicate())
	Input.flush_buffered_events()
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _run() -> void:
	check(ResourceLoader.exists("res://scripts/frame_pacing.gd"), "Foreground frame pacing diagnostics exist")
	if failures:
		print("Frame pacing: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var pacing = load("res://scripts/frame_pacing.gd").new()
	check(pacing.summary(60).count == 0, "Empty observations have no fabricated timing")
	for index in 120: pacing.add_interval(1.0 / 60.0)
	var steady: Dictionary = pacing.summary(60)
	check(steady.count == 120 and absf(steady.mean_ms - 1000.0 / 60.0) < 0.001, "Steady 60 FPS has measured 16.67 ms intervals")
	check(absf(steady.p95_ms - 1000.0 / 60.0) < 0.001 and steady.late_percent == 0, "Steady pacing has no late intervals")
	pacing.reset()
	for index in 120: pacing.add_interval(1.0 / 120.0 if index % 2 == 0 else 1.0 / 40.0)
	var uneven: Dictionary = pacing.summary(60)
	check(absf(uneven.mean_ms - steady.mean_ms) < 0.001, "Uneven delivery can have the same mean as steady 60 FPS")
	check(absf(uneven.p95_ms - 25.0) < 0.001, "P95 distinguishes uneven timing despite the same FPS")
	pacing.add_interval(0.050)
	check(pacing.summary(60).late_percent > 0, "A 50 ms stall is counted as late at 60 FPS")
	pacing.reset()
	for index in 60: pacing.add_interval(1.0 / 30.0)
	check(pacing.summary(30).late_percent == 0 and pacing.summary(60).late_percent == 100, "Late threshold follows the selected presentation target")
	var count: int = pacing.summary(60).count
	for value in [0.0, -1.0, NAN, INF]: pacing.add_interval(value)
	check(pacing.summary(60).count == count, "Nonfinite and nonpositive intervals are rejected")
	for index in 1000: pacing.add_interval(1.0 / 60.0)
	check(pacing.summary(60).count == 180 and pacing.summary(60).late_percent == 0, "Rolling window is bounded and evicts old stalls")
	pacing.reset()
	pacing.record(1000000)
	check(pacing.summary(60).count == 0, "First foreground callback establishes a baseline")
	pacing.record(1016667)
	check(absf(pacing.summary(60).mean_ms - 16.667) < 0.001, "Monotonic callbacks produce observed intervals")
	pacing.reset()
	pacing.record(100000000)
	check(pacing.summary(60).count == 0, "Resume baseline excludes time spent backgrounded")
	# Check the integration uses the new rendering path and safely switches texture size.
	root.gui_embed_subwindows = true
	root.size = Vector2i(960, 640)
	var shell = load("res://scenes/main.tscn").instantiate()
	shell.store.path = "user://pacing_test.json"
	shell.store.clear_files()
	root.add_child(shell)
	shell.set_process(false)
	await process_frame
	check(shell.has_method("_smooth_scale"), "Screen-aware smooth resolution selection exists")
	if not shell.has_method("_smooth_scale"):
		shell.store.clear_files()
		shell.queue_free()
		await process_frame
		print("Frame pacing: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(shell.engine.has_method("frame_smooth"), "Native extension exposes finer smooth frames")
	shell._start(0)
	for index in 10: shell.engine.step(2 | 32)
	shell.accumulator = shell.TICK * 0.5
	var state: Dictionary = shell.engine.state()
	shell.settings.target_fps = 60
	shell.texture = null
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(640, 480), "Smooth mode uses a finer canvas")
	check(shell.texture.get_image().get_data() == shell.engine.frame_smooth(0.5), "Smooth mode displays the independently positioned native frame")
	shell.settings.target_fps = 30
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(320, 240), "Switching to classic recreates the smaller texture safely")
	check(shell.texture.get_image().get_data() == shell.engine.frame(), "Classic mode retains the authentic original image")
	shell.settings.target_fps = 60
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(640, 480) and shell.engine.state() == state, "Returning to smooth changes no game state")
	check(shell.settings.render_resolution == 0 and shell._smooth_scale() == 2, "Existing saves default to Auto with the lighter canvas for small output")
	for request in [-1, 0, 1, 3, 5, 9999999999]:
		check(shell.engine.frame_smooth(0.5, request).size() == 640 * 480 * 4, "Unsupported native scale is bounded to 2x")
	shell._set_render_resolution(4)
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(1280, 960), "Higher preference creates the larger texture")
	check(shell.texture.get_image().get_data() == shell.engine.frame_smooth(0.5, 4), "High mode uses native quarter-pixel replay")
	shell.settings.target_fps = 30
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(320, 240) and shell.settings.render_resolution == 4, "Classic ignores but retains the smooth-resolution preference")
	shell.settings.target_fps = 60
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(1280, 960), "Smooth restores the selected high resolution")
	shell._set_render_resolution(0)
	root.size = Vector2i(1920, 1280)
	await process_frame
	await process_frame
	check(root.get_final_transform().x.length() > 1.9, "Auto test uses a real stretched window")
	check(shell._smooth_scale() == 4, "Auto accounts for physical window scaling beyond virtual UI size")
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(1280, 960), "Auto renders at the larger canvas when the display needs it")
	shell._set_render_resolution(2)
	shell._render_frame()
	check(shell.texture.get_size() == Vector2(640, 480), "Lighter override works even on a large physical window")
	shell._set_render_resolution(0)
	root.size = Vector2i(1080, 1920)
	await process_frame
	await process_frame
	check(shell._smooth_scale() == 4, "Auto also chooses high resolution after portrait rotation")
	root.size = Vector2i(960, 640)
	await process_frame
	await process_frame
	check(shell._smooth_scale() == 2 and shell.engine.state() == state, "Smaller output returns to 2x without advancing game state")
	shell._render_frame()
	shell.pacing.add_interval(0.05)
	shell._pause("PAUSED")
	check(shell.pacing.summary(60).count == 0, "Pause clears active frame observations")
	shell._resume()
	check(shell.pacing.summary(60).count == 0, "Resume begins without a false background stall")
	shell.settings.show_fps = true
	shell.pacing.add_interval(0.020)
	shell._update_fps(true)
	check(shell.fps_label.text.contains("20.0 ms") and shell.fps_label.text.contains("p95"), "Optional FPS overlay includes observed timing")
	check(shell.fps_label.text.contains("640×480"), "FPS overlay reports actual rendering dimensions")
	shell._pause("PAUSED")
	shell._settings_menu()
	await process_frame
	await process_frame
	var resolution = shell.find_child("RenderResolution", true, false) as OptionButton
	check(resolution != null and resolution.item_count == 3, "Settings exposes Auto and both rendering resolutions")
	if resolution != null:
		await tap(resolution)
		# Touch opens the popup without keyboard focus; first Down focuses Auto.
		await press_key(KEY_DOWN)
		await press_key(KEY_DOWN)
		await press_key(KEY_ENTER)
		check(shell.settings.render_resolution == 2, "Actual touch and keyboard selection applies the lighter setting")
		var saved = load("res://scripts/save_store.gd").new()
		saved.path = shell.store.path
		saved.load_data()
		check(saved.settings().render_resolution == 2, "Rendering preference survives save/reopen")
	shell.store.clear_files()
	shell.queue_free()
	await process_frame
	print("Frame pacing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
