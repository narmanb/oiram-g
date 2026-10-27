extends SceneTree
## Send touch through Input's real event path, including UI mouse emulation.
const Main = preload("res://scripts/main.gd")
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
	event.position = position
	event.index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(button: BaseButton) -> void:
	check(button != null, "Touch target button exists")
	if button == null: return
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	var position = root.get_final_transform() * button.get_global_rect().get_center()
	touch(position, 0, true)
	await process_frame
	touch(position, 0, false)
	await process_frame
	await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 640)
	var shell = load("res://scenes/main.tscn").instantiate()
	shell.store.path = "user://touch_test.json"
	shell.store.clear_files()
	root.add_child(shell)
	shell.set_process(false)
	await process_frame
	await process_frame
	check(Input.emulate_mouse_from_touch, "Native UI widgets must receive touch-generated mouse events")
	await tap(find_button(shell, "Settings"))
	check(find_button(shell, "Map jump") != null, "A real finger tap reaches the Settings menu")
	var toggle = find_button(shell, "Show touch controls")
	check(toggle != null, "A finger tap opens Settings and exposes the touch-control toggle")
	if toggle == null:
		shell.store.clear_files()
		shell.queue_free()
		await process_frame
		print("Touch input: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(toggle.button_pressed, "Touch controls are on by default")
	await tap(toggle)
	check(not shell.settings.touch_controls, "Tapping the toggle disables gameplay touch controls")
	var reopened = SaveStore.new()
	reopened.path = shell.store.path
	reopened.load_data()
	check(reopened.settings().get("touch_controls", true) == false, "Touch-control preference persists")
	await tap(find_button(shell, "Back"))
	check(find_button(shell, "Settings") != null, "Menus remain touchable with gameplay touch controls off")
	await tap(find_button(shell, "PLAY  →"))
	check(shell.running and not shell.paused, "A finger tap starts the default native level")
	check(shell.touch_regions.is_empty(), "Disabled touch controls have no visible or active gameplay regions")
	var press = InputEventKey.new()
	press.keycode = KEY_X
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	check(shell.controls.mask() & shell.Controls.RUN, "Physical controls remain enabled when touchscreen controls are hidden")
	press.pressed = false
	Input.parse_input_event(press.duplicate())
	Input.flush_buffered_events()
	var start = InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	Input.parse_input_event(start)
	Input.flush_buffered_events()
	check(shell.paused, "Gamepad Start still pauses with touch controls hidden")
	await tap(find_button(shell, "RESUME  →"))
	await tap(find_button(shell, "Ⅱ  PAUSE"))
	check(shell.paused, "Touch Pause works with the gameplay overlay hidden")
	await tap(find_button(shell, "Settings"))
	await tap(find_button(shell, "Show touch controls"))
	await tap(find_button(shell, "Back"))
	await tap(find_button(shell, "RESUME  →"))
	check(not shell.paused and shell.touch_regions.size() == 7, "Touch gameplay controls can be enabled again from pause")
	var centers: Dictionary = {}
	for region in shell.touch_regions: centers[region.action] = region.center
	touch(root.get_final_transform() * centers[shell.Controls.RIGHT], 0, true)
	touch(root.get_final_transform() * centers[shell.Controls.RUN], 1, true)
	touch(root.get_final_transform() * centers[shell.Controls.JUMP], 2, true)
	check(shell.controls.mask() == (shell.Controls.RIGHT | shell.Controls.RUN | shell.Controls.JUMP), "Three fingers can steer, run and jump together")
	check(shell.controls.touch_actions.size() == 3, "Synthesized mouse input does not duplicate a gameplay finger")
	touch(root.get_final_transform() * centers[shell.Controls.RIGHT], 0, false)
	check(shell.controls.mask() == (shell.Controls.RUN | shell.Controls.JUMP), "Releasing one finger preserves the other held buttons")
	touch(root.get_final_transform() * centers[shell.Controls.RUN], 1, false)
	touch(root.get_final_transform() * centers[shell.Controls.JUMP], 2, false)
	check(shell.controls.mask() == 0, "Releasing all fingers clears gameplay input")
	await tap(find_button(shell, "Ⅱ  PAUSE"))
	await tap(find_button(shell, "Save & return to menu"))
	await tap(find_button(shell, "Editor"))
	check(shell.editor != null and shell.editor.visible, "Editor opens from a real menu tap")
	var editor = shell.editor
	var original_tiles: PackedByteArray = editor.pack.levels[editor.level_index].tiles.duplicate()
	editor._select_tile(244)
	var canvas = editor.canvas
	var cell = Vector2i(5, 2)
	var position = root.get_final_transform() * (canvas.global_position + canvas.pan + (Vector2(cell) + Vector2.ONE * 0.5) * 16.0 * canvas.zoom)
	touch(position, 0, true)
	await process_frame
	touch(position, 0, false)
	await process_frame
	check(editor.pack.levels[editor.level_index].tiles[cell.y * editor.canvas.level.width + cell.x] == 244, "Native touch paints the editor through Input's event path")
	check(editor.undo_stack.size() == 1 and not canvas.painting, "Synthetic mouse does not duplicate the editor stroke")
	await tap(find_button(editor, "Undo"))
	check(editor.pack.levels[editor.level_index].tiles == original_tiles, "One Undo button tap restores the entire finger stroke")
	shell.store.clear_files()
	shell.queue_free()
	await process_frame
	print("Touch input: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
