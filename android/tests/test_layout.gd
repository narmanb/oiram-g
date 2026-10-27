extends SceneTree
## Exercise layout editing through the real touch and mouse event pipeline.
const SaveStore = preload("res://scripts/save_store.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func find_button(node: Node, text: String) -> BaseButton:
	for child in node.get_children():
		if child is BaseButton and child.text == text and child.is_visible_in_tree(): return child
		var found = find_button(child, text)
		if found != null: return found
	return null

func touch(position: Vector2, index: int, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.position = root.get_final_transform() * position
	event.index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func drag(from: Vector2, to: Vector2, index: int = 0) -> void:
	touch(from, index, true)
	var event = InputEventScreenDrag.new()
	event.position = root.get_final_transform() * to
	event.relative = root.get_final_transform().basis_xform(to - from)
	event.index = index
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	touch(to, index, false)
	await process_frame

func tap(button: BaseButton) -> void:
	check(button != null, "Layout UI target exists")
	if button == null: return
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	var position = button.get_global_rect().get_center()
	touch(position, 0, true)
	await process_frame
	touch(position, 0, false)
	await process_frame
	await process_frame

func mouse(position: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.position = root.get_final_transform() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse_drag(from: Vector2, to: Vector2) -> void:
	mouse(from, true)
	var event = InputEventMouseMotion.new()
	event.position = root.get_final_transform() * to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	mouse(to, false)
	await process_frame

func key_press(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func find_presentation(node: Node) -> OptionButton:
	for child in node.get_children():
		if child is OptionButton and child.item_count == 2 and child.get_item_id(0) == 30: return child
		var found = find_presentation(child)
		if found != null: return found
	return null

func contained(shell: Control) -> void:
	for region in shell.touch_regions:
		var bounds = Rect2(region.center - Vector2.ONE * region.radius, Vector2.ONE * region.radius * 2)
		check(Rect2(Vector2(0, 66), shell.size - Vector2(0, 66)).encloses(bounds), "Entire control stays below toolbar and within viewport")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(960, 640)
	var shell = load("res://scenes/main.tscn").instantiate()
	shell.store.path = "user://layout_test.json"
	shell.store.clear_files()
	root.add_child(shell)
	shell.set_process(false)
	await process_frame
	await process_frame
	await tap(find_button(shell, "Settings"))
	check(find_button(shell, "Edit touch layout") != null, "Settings exposes layout editor")
	check(find_button(shell, "Show FPS") != null, "Settings exposes measured FPS preference")
	check(Engine.max_fps == 60, "Presentation defaults to 60 FPS")
	check(shell.engine != null and shell.engine.has_method("frame_interpolated") and shell.engine.has_method("reset_interpolation"), "Loaded native extension supplies smooth presentation APIs")
	if find_button(shell, "Edit touch layout") == null:
		shell.store.clear_files()
		shell.queue_free()
		await process_frame
		print("Touch layout: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	await tap(find_button(shell, "Edit touch layout"))
	check(shell.touch_layout.editing and shell.paused, "Editor opens a paused preview from title")
	check(shell.touch_layout.handles.size() == 4, "D-pad and three actions have separate drag handles")
	var layout = shell.touch_layout
	var before: Array = shell.touch_regions.duplicate(true)
	var old_dpad: Vector2 = layout.handles.dpad
	await drag(old_dpad, old_dpad + Vector2(100, -150))
	var shift: Vector2 = layout.handles.dpad - old_dpad
	check(shift.distance_to(Vector2(100, -150)) < 0.1, "Real finger drags the D-pad as a group")
	for index in 4:
		check((shell.touch_regions[index].center - before[index].center).distance_to(shift) < 0.1, "Every D-pad direction keeps its relative offset")
	check(shell.touch_regions[4].center == before[4].center, "Dragging D-pad leaves Jump fixed")
	for key in ["jump", "run", "special"]:
		var old: Dictionary = layout.handles.duplicate()
		await drag(old[key], old[key] + Vector2(-150, -80))
		check(layout.handles[key] != old[key], "Real finger independently moves " + key)
		for other in old:
			if other != key: check(layout.handles[other] == old[other], "Dragging " + key + " leaves " + other + " fixed")
	var special_before: Vector2 = layout.handles.special
	await drag(special_before, layout.handles.jump)
	check(shell._touch_action(layout.handles.jump) == shell.Controls.SPECIAL, "Overlapping controls activate the visually topmost button")
	await drag(layout.handles.special, special_before)
	var mouse_before: Vector2 = layout.handles.dpad
	await mouse_drag(mouse_before, mouse_before + Vector2(40, -40))
	check(layout.handles.dpad.distance_to(mouse_before + Vector2(40, -40)) < 0.1, "Desktop mouse also drags the D-pad")
	touch(layout.handles.dpad, 0, true)
	check(layout.drags.size() == 1 and not layout.drags.has(-1), "Synthetic mouse does not duplicate the editing finger")
	touch(layout.handles.dpad, 0, false)
	check(shell.controls.mask() == 0, "Editing sends no gameplay action")
	await tap(find_button(shell, "Save"))
	var reopened = SaveStore.new()
	reopened.path = shell.store.path
	reopened.load_data()
	check(reopened.settings().get("touch_layouts", {}).has("landscape"), "Saved normalized layout survives reopening")
	var saved = shell.settings.touch_layouts.duplicate(true)
	var restored = load("res://scripts/touch_layout.gd").new()
	root.add_child(restored)
	restored.configure(shell.size, reopened.settings())
	for handle in layout.handles:
		check(restored.handles[handle].distance_to(layout.handles[handle]) < 0.01, "Reopening restores " + handle + " position")
	restored.free()
	var original: Dictionary = layout.handles.duplicate()
	await tap(find_button(shell, "Left-handed layout (mirror controls)"))
	for handle in original:
		check(absf(layout.handles[handle].x - (shell.size.x - original[handle].x)) < 0.01, "Mirror reflects saved " + handle + " position")
	await tap(find_button(shell, "Left-handed layout (mirror controls)"))
	await tap(find_button(shell, "Edit touch layout"))
	var saved_jump: Vector2 = layout.handles.jump
	await drag(saved_jump, saved_jump + Vector2(40, -40))
	await tap(find_button(shell, "Cancel"))
	check(shell.settings.touch_layouts == saved, "Cancel discards draft layout")
	await tap(find_button(shell, "Edit touch layout"))
	await tap(find_button(shell, "Reset"))
	check(layout.handles.jump != saved_jump, "Reset restores orientation defaults in preview")
	shell._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(not layout.editing and shell.settings.touch_layouts == saved, "Android Back cancels reset without saving")
	await tap(find_button(shell, "Edit touch layout"))
	shell.settings.size = 1.3
	for dimensions in [Vector2(480, 320), Vector2(320, 480), Vector2(640, 960), Vector2(960, 640)]:
		shell.size = dimensions
		shell._layout()
		await process_frame
		for button in layout.toolbar.get_children():
			if button is BaseButton: check(Rect2(Vector2.ZERO, dimensions).encloses(button.get_global_rect()), "Editing toolbar stays reachable on small screens")
		contained(shell)
		await drag(layout.handles.dpad, Vector2(-1000, -1000))
		contained(shell)
	check(layout.layouts.has("portrait") and layout.layouts.has("landscape"), "Portrait and landscape drafts retain separate positions")
	shell.size = Vector2(960, 640)
	shell._layout()
	await tap(find_button(shell, "Cancel"))
	await tap(find_button(shell, "Edit touch layout"))
	shell.size = Vector2(640, 960)
	shell._layout()
	await drag(layout.handles.jump, layout.handles.jump + Vector2(-100, -120))
	var portrait_jump: Vector2 = layout.handles.jump
	await tap(find_button(shell, "Save"))
	check(shell.settings.touch_layouts.landscape == saved.landscape, "Saving portrait preserves the landscape layout")
	reopened.load_data()
	restored = load("res://scripts/touch_layout.gd").new()
	root.add_child(restored)
	restored.configure(Vector2(640, 960), reopened.settings())
	check(restored.handles.jump.distance_to(portrait_jump) < 0.01, "Portrait positions survive saving and reopening")
	for positions in reopened.settings().touch_layouts.values():
		for normalized in positions.values():
			check(normalized[0] >= 0 and normalized[0] <= 1 and normalized[1] >= 0 and normalized[1] <= 1, "Persisted positions are viewport-normalized")
	restored.free()
	shell.size = Vector2(960, 640)
	shell._layout()
	shell._settings_menu()
	await process_frame
	await tap(find_button(shell, "Show FPS"))
	check(shell.settings.show_fps and shell.fps_label.visible, "FPS toggle displays measured label")
	check(shell.fps_label.text == "%d FPS" % roundi(Engine.get_frames_per_second()), "FPS label reports the actual measured rate")
	var presentation = find_presentation(shell)
	await tap(presentation)
	await key_press(KEY_UP)
	await key_press(KEY_UP)
	await key_press(KEY_ENTER)
	check(shell.settings.target_fps == 30 and Engine.max_fps == 30, "Presentation selector applies 30 FPS classic")
	reopened.load_data()
	check(reopened.settings().target_fps == 30 and reopened.settings().show_fps, "FPS target and display preference persist")
	await tap(presentation)
	await key_press(KEY_DOWN)
	await key_press(KEY_DOWN)
	await key_press(KEY_ENTER)
	check(shell.settings.target_fps == 60 and Engine.max_fps == 60, "Presentation selector restores 60 FPS smooth")
	await tap(find_button(shell, "Show touch controls"))
	await tap(find_button(shell, "Edit touch layout"))
	check(shell.touch_regions.size() == 7, "Layout preview shows controls while the gameplay overlay is disabled")
	await tap(find_button(shell, "Reset"))
	await tap(find_button(shell, "Save"))
	check(shell.touch_regions.is_empty() and not shell.settings.touch_controls, "Saving layout preserves the hidden-controls preference")
	check(shell.settings.touch_layouts.landscape != saved.landscape, "Saving Reset replaces custom positions with defaults")
	await tap(find_button(shell, "Show touch controls"))
	await tap(find_button(shell, "Back"))
	await tap(find_button(shell, "PLAY  →"))
	check(shell.running, "Gameplay remains available after layout editing")
	var state: Dictionary = shell.engine.state()
	shell._pause("PAUSED")
	shell._settings_menu()
	await tap(find_button(shell, "Edit touch layout"))
	shell._process(1.0)
	check(shell.engine.state() == state, "Layout preview cannot advance native simulation")
	var key = InputEventKey.new()
	key.keycode = KEY_Z
	key.pressed = true
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	check(shell.controls.mask() == 0, "Physical gameplay keys are disabled during editing")
	shell._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(shell.paused and shell.controls.mask() == 0, "Focus loss keeps layout editing pause-safe")
	shell._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(shell.paused and not layout.editing, "Back from in-game editing stays paused")
	await tap(find_button(shell, "Back"))
	await tap(find_button(shell, "RESUME  →"))
	check(not shell.paused and shell.controls.enabled, "Resume restores physical controls after editing")
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	check(shell.controls.mask() == shell.Controls.JUMP, "Physical jump works after cancelling layout editing")
	key.pressed = false
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	for tick in 10:
		shell.controls.set_touch(3, shell.Controls.RIGHT | shell.Controls.RUN)
		shell._process(shell.TICK)
	shell.controls.release_all()
	shell.accumulator = shell.TICK * 0.5
	var presentation_state: Dictionary = shell.engine.state()
	# The headless dummy renderer retains creation data but does not update textures.
	shell.texture = null
	shell._render_frame()
	check(shell.texture.get_image().get_data() == shell.engine.frame_interpolated(0.5), "Smooth mode displays native interpolation at accumulator alpha")
	shell.settings.target_fps = 30
	shell.texture = null
	shell._render_frame()
	check(shell.texture.get_image().get_data() == shell.engine.frame(), "Classic mode displays the unmodified native framebuffer")
	check(shell.engine.state() == presentation_state, "Changing presentation mode does not advance native state")
	shell.store.clear_files()
	shell.queue_free()
	await process_frame
	print("Touch layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
