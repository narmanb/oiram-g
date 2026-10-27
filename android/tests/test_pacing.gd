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
	root.size = Vector2i(960, 640)
	var shell = load("res://scenes/main.tscn").instantiate()
	shell.store.path = "user://pacing_test.json"
	shell.store.clear_files()
	root.add_child(shell)
	shell.set_process(false)
	await process_frame
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
	shell.pacing.add_interval(0.05)
	shell._pause("PAUSED")
	check(shell.pacing.summary(60).count == 0, "Pause clears active frame observations")
	shell._resume()
	check(shell.pacing.summary(60).count == 0, "Resume begins without a false background stall")
	shell.settings.show_fps = true
	shell.pacing.add_interval(0.020)
	shell._update_fps(true)
	check(shell.fps_label.text.contains("20.0 ms") and shell.fps_label.text.contains("p95"), "Optional FPS overlay includes observed timing")
	shell.store.clear_files()
	shell.queue_free()
	await process_frame
	print("Frame pacing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
