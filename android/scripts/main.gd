extends Control

const SaveStore = preload("res://scripts/save_store.gd")
const Controls = preload("res://scripts/controls.gd")
const TouchLayout = preload("res://scripts/touch_layout.gd")
const TICK := 1.0 / 30.0
const INK := Color("edf4ea")
const MUTED := Color("a3b3bd")
const ACCENT := Color("f4bf4f")
const PANEL := Color("132634")

var store = SaveStore.new()
var controls = Controls.new()
var pack_codec: GDScript
var engine: RefCounted
var packs: Array[Dictionary] = []
var selected := 0
var stage := 0
var unlocked := 0
var checkpoint: Dictionary = {}
var screen: TextureRect
var texture: ImageTexture
var overlay: Control
var bar: HBoxContainer
var status: Label
var settings: Dictionary = {}
var running := false
var paused := true
var testing := false
var terminal := false
var accumulator := 0.0
var clock_accumulator := 0.0
var clock_last_usec := 0
var touch_regions: Array[Dictionary] = []
var pointer_positions: Dictionary = {}
var mouse_down := false
var import_dialog: FileDialog
var editor: Control
var notice := ""
var remap_action := ""
var touch_layout: Control
var fps_label: Label

func _ready() -> void:
	store.load_data()
	settings = store.settings()
	for entry in [["opacity", 0.75, 0.25, 1.0], ["size", 1.0, 0.7, 1.3]]:
		var value: Variant = settings.get(entry[0], entry[1])
		settings[entry[0]] = clampf(float(value), entry[2], entry[3]) if (value is int or value is float) and is_finite(float(value)) else entry[1]
	settings.secret_code = store._number(settings.get("secret_code"), 0, 0, 99999999)
	settings.touch_controls = settings.get("touch_controls", true) == true
	settings.mirrored = settings.get("mirrored", false) == true
	settings.alternate = settings.get("alternate", false) == true
	settings.show_fps = settings.get("show_fps", false) == true
	settings.target_fps = 30 if settings.get("target_fps", 60) == 30 else 60
	Engine.max_fps = int(settings.target_fps)
	controls.alternate = bool(settings.get("alternate", false))
	if settings.get("joy_buttons") is Dictionary:
		for action in ["jump", "run", "special"]:
			controls.joy_buttons[action] = store._number(settings.joy_buttons.get(action), controls.joy_buttons[action], 0, JOY_BUTTON_MAX - 1)
	add_child(controls)
	controls.pause_requested.connect(_toggle_pause)
	_build_theme()
	screen = TextureRect.new()
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	status = Label.new()
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.clip_text = true
	status.text = "OIRAM"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(status)
	var pause_button = _button("Ⅱ  PAUSE", _toggle_pause)
	bar.add_child(pause_button)
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_color_override("font_color", ACCENT)
	add_child(fps_label)
	_update_fps()
	touch_layout = TouchLayout.new()
	add_child(touch_layout)
	touch_layout.saved.connect(func(layouts: Dictionary): settings.touch_layouts = layouts; _save_settings(); _close_touch_layout())
	touch_layout.cancelled.connect(_close_touch_layout)
	touch_layout.layout_changed.connect(func():
		if touch_layout.editing: touch_regions = touch_layout.regions.duplicate(true))
	if ResourceLoader.exists("res://scripts/oiram_pack.gd"):
		pack_codec = load("res://scripts/oiram_pack.gd")
	if ClassDB.class_exists("OiramEngine"):
		engine = ClassDB.instantiate("OiramEngine")
	_load_packs()
	resized.connect(_layout)
	_layout()
	_menu()

func _build_theme() -> void:
	var ui_theme = Theme.new()
	ui_theme.default_font_size = 20
	ui_theme.set_color("font_color", "Label", INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = PANEL.lightened(0.12 if state == "hover" else 0.0)
		box.border_color = ACCENT if state in ["focus", "pressed"] else Color("355062")
		box.set_border_width_all(2)
		box.set_corner_radius_all(9)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		ui_theme.set_stylebox(state, "Button", box)
		ui_theme.set_stylebox(state, "OptionButton", box)
	ui_theme.set_color("font_color", "Button", INK)
	theme = ui_theme

func _button(text_value: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	return button

func _label(text_value: String, font_size: int = 20, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _card(title: String, subtitle: String = "") -> VBoxContainer:
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim = ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.045, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	overlay.add_child(margin)
	var center = CenterContainer.new()
	margin.add_child(center)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(620, size.x - 44), maxf(100, size.y - 44))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 13)
	scroll.add_child(column)
	column.add_child(_label(title, 40, ACCENT))
	_focus_first.call_deferred(overlay)
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, 17, MUTED))
	return column

func _focus_first(parent: Node) -> bool:
	if not is_instance_valid(parent) or parent.is_queued_for_deletion(): return false
	for child in parent.get_children():
		if child is BaseButton and not child.disabled and child.is_visible_in_tree():
			child.grab_focus()
			return true
		if _focus_first(child): return true
	return false

func _load_packs() -> void:
	packs.clear()
	if pack_codec == null:
		notice = "Pack decoder is unavailable. Rebuild the application."
		return
	_read_pack("res://assets/OiramPK.8xv", false)
	_read_pack("user://editor/current.8xv", false)
	DirAccess.make_dir_recursive_absolute("user://packs")
	var directory = DirAccess.open("user://packs")
	if directory != null:
		for filename in directory.get_files():
			if filename.to_lower().ends_with(".8xv"):
				_read_pack("user://packs/" + filename, false)
	var saved_id = str(settings.get("selected_pack", ""))
	for index in packs.size():
		if packs[index].id == saved_id:
			selected = index
	selected = clampi(selected, 0, maxi(0, packs.size() - 1))

func _read_pack(path: String, imported: bool) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		notice = "This file is too large or cannot be opened."
		return false
	var bytes = file.get_buffer(file.get_length())
	var decoded: Dictionary = pack_codec.load_bytes(bytes)
	if not decoded.get("ok", false):
		notice = "Cannot import pack: " + str(decoded.get("error", "invalid Oiram pack"))
		return false
	var hash_context = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	var pack_id = hash_context.finish().hex_encode()
	for index in packs.size():
		if packs[index].id == pack_id:
			selected = index
			return true
	decoded["id"] = pack_id
	decoded["path"] = path
	if imported:
		var destination = "user://packs/" + pack_id + ".8xv"
		var output = FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			notice = "The validated pack could not be saved."
			return false
		output.store_buffer(bytes)
		output.close()
		decoded.path = destination
	packs.append(decoded)
	if imported:
		selected = packs.size() - 1
	return true

func _menu() -> void:
	if is_instance_valid(editor):
		editor.hide()
	running = false
	paused = true
	controls.enabled = false
	controls.pause_enabled = false
	controls.release_all()
	bar.visible = false
	screen.visible = false
	var column = _card("OIRAM", "A pocket-sized adventure, faithfully powered by the original C game.")
	if ResourceLoader.exists("res://assets/oiram_start.png"):
		var art = TextureRect.new()
		art.texture = load("res://assets/oiram_start.png")
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var keyed_shader = Shader.new()
		keyed_shader.code = "shader_type canvas_item; void fragment(){ vec4 c=texture(TEXTURE,UV); if(distance(c.rgb,vec3(1.0,0.0,0.50196))<0.01){c.a=0.0;} COLOR=c;}"
		var keyed_material = ShaderMaterial.new()
		keyed_material.shader = keyed_shader
		art.material = keyed_material
		art.custom_minimum_size.y = 58
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(art)
	if not notice.is_empty():
		column.add_child(_label(notice, 17, ACCENT))
	if not packs.is_empty():
		var picker = OptionButton.new()
		for pack in packs:
			picker.add_item(str(pack.get("name", "Untitled pack")) + "  ·  " + str(pack.levels.size()) + " stages")
		picker.selected = selected
		picker.item_selected.connect(func(index: int): selected = index; notice = ""; _save_settings(); _menu())
		column.add_child(picker)
		var pack = packs[selected]
		var progress = store.progress(pack.id)
		var level = clampi(int(progress.get("level", 0)), 0, pack.levels.size() - 1)
		column.add_child(_label("By " + str(pack.get("author", "Unknown")) + "  /  Stage %d of %d" % [level + 1, pack.levels.size()], 17, MUTED))
		var play = _button("CONTINUE  →" if not progress.is_empty() else "PLAY  →", func(): _start(level))
		play.disabled = engine == null
		column.add_child(play)
		column.add_child(_button("Choose a stage", _level_menu))
	else:
		column.add_child(_label("No valid level packs are installed.", 18, ACCENT))
	if engine == null:
		column.add_child(_label("The native game engine is unavailable. Rebuild with the Oiram GDExtension.", 17, ACCENT))
	var tools = HBoxContainer.new()
	column.add_child(tools)
	for item in [["Import pack", _import_pack], ["Editor", _open_editor], ["Settings", _settings_menu]]:
		var button = _button(item[0], item[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(button)
	column.add_child(_button("Credits & controls", _credits))
	queue_redraw()

func _level_menu() -> void:
	var pack = packs[selected]
	var progress = store.progress(pack.id)
	var limit = clampi(int(progress.get("unlocked", 0)), 0, pack.levels.size() - 1)
	var column = _card("CHOOSE A STAGE", "Completed stages remain available. Selecting a stage restarts it.")
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for index in pack.levels.size():
		var button = _button(str(index + 1), _start.bind(index))
		button.custom_minimum_size.x = 78
		button.disabled = index > limit or engine == null
		grid.add_child(button)
	column.add_child(_button("Back", _menu))

func _start(level_index: int) -> void:
	if engine == null or packs.is_empty():
		return
	testing = false
	var pack = packs[selected]
	checkpoint = store.progress(pack.id)
	if checkpoint.is_empty():
		checkpoint = {"lives": 15, "coins": 0, "score": 0, "flags": 0, "level": 0, "unlocked": 0}
	unlocked = int(checkpoint.get("unlocked", 0))
	stage = clampi(level_index, 0, pack.levels.size() - 1)
	_begin_level(pack.levels[stage])

func _begin_level(level: Dictionary) -> void:
	# Restart checkpoints preserve form, while timed/animation-only bonuses reset.
	checkpoint.flags = int(checkpoint.get("flags", 0)) & 19
	engine.set_easter_egg(clampi(int(settings.get("secret_code", 0)), 0, 99999999))
	if not engine.configure(level, checkpoint):
		notice = "The native engine rejected this stage."
		_menu()
		return
	if is_instance_valid(editor):
		editor.hide()
	running = true
	terminal = false
	paused = false
	accumulator = 0.0
	clock_accumulator = 0.0
	clock_last_usec = Time.get_ticks_usec()
	controls.enabled = true
	controls.pause_enabled = true
	controls.release_all()
	pointer_positions.clear()
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	screen.visible = true
	bar.visible = true
	_layout()
	_render_frame()
	_checkpoint()

func _process(delta: float) -> void:
	_update_fps()
	if not running or paused or engine == null:
		return
	# Countdown follows real elapsed foreground time, independently of simulation ticks.
	var clock_now = Time.get_ticks_usec()
	clock_accumulator += maxf(0.0, float(clock_now - clock_last_usec) / 1000000.0)
	clock_last_usec = clock_now
	var elapsed = int(clock_accumulator)
	if elapsed > 0:
		engine.advance_clock(elapsed)
		clock_accumulator -= elapsed
	# Bound recovery after a long foreground stall to avoid a spiral of death.
	accumulator = minf(accumulator + delta, TICK * 6)
	while accumulator + 0.0000001 >= TICK:
		engine.step(controls.mask())
		accumulator = maxf(0.0, accumulator - TICK)
		var state: Dictionary = engine.state()
		if state.get("exit", false):
			_finish_level(state)
			break
	if running:
		_render_frame()

func _render_frame() -> void:
	var pixels: PackedByteArray
	if int(settings.get("target_fps", 60)) == 60 and engine.has_method("frame_interpolated"):
		pixels = engine.frame_interpolated(clampf(accumulator / TICK, 0.0, 1.0))
	else:
		pixels = engine.frame()
	if pixels.size() != 320 * 240 * 4:
		return
	var image = Image.create_from_data(320, 240, false, Image.FORMAT_RGBA8, pixels)
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		screen.texture = texture
	else:
		texture.update(image)
	var state: Dictionary = engine.state()
	status.text = ("TEST STAGE" if testing else "%s  ·  %d / %d" % [packs[selected].name, stage + 1, packs[selected].levels.size()])

func _finish_level(state: Dictionary) -> void:
	if testing:
		terminal = true
		_pause("TEST COMPLETE" if state.get("completed", false) else "TRY AGAIN", "Return to the editor to keep building.")
		return
	for key in ["lives", "coins", "score", "flags"]:
		checkpoint[key] = int(state.get(key, checkpoint.get(key, 0)))
	if state.get("completed", false):
		stage += 1
		unlocked = maxi(unlocked, stage)
		if stage >= packs[selected].levels.size():
			terminal = true
			stage = 0
			unlocked = packs[selected].levels.size() - 1
			_checkpoint(false)
			_pause("PACK COMPLETE!", "Every stage cleared. Your unlocked stages are saved.", false)
		else:
			_begin_level(packs[selected].levels[stage])
	elif state.get("failed", false):
		checkpoint.lives = int(checkpoint.get("lives", 15)) - 1
		checkpoint.flags = 0
		if checkpoint.lives < 1:
			terminal = true
			stage = 0
			unlocked = 0
			checkpoint = {"lives": 15, "coins": 0, "score": 0, "flags": 0}
			_checkpoint(false)
			_pause("GAME OVER", "Your next adventure begins at stage one with 15 lives.", false)
		else:
			_begin_level(packs[selected].levels[stage])
	else:
		_pause("PAUSED")

func _checkpoint(capture: bool = true) -> void:
	if testing or packs.is_empty():
		return
	if capture and running and not terminal and engine != null:
		var state: Dictionary = engine.state()
		for key in ["lives", "coins", "score", "flags"]:
			checkpoint[key] = int(state.get(key, checkpoint.get(key, 0)))
	checkpoint.level = stage
	checkpoint.unlocked = unlocked
	store.set_progress(packs[selected].id, checkpoint)
	store.flush()

func _toggle_pause() -> void:
	if is_instance_valid(touch_layout) and touch_layout.editing: return
	if not running:
		return
	if paused:
		_resume()
	else:
		_pause("PAUSED")

func _pause(title: String, message: String = "", capture: bool = true) -> void:
	paused = true
	controls.enabled = false
	controls.pause_enabled = title == "PAUSED" and not terminal
	controls.release_all()
	pointer_positions.clear()
	mouse_down = false
	accumulator = 0.0
	clock_accumulator = 0.0
	_checkpoint(capture)
	var column = _card(title, message)
	if title == "PAUSED":
		column.add_child(_button("RESUME  →", _resume))
	if testing:
		column.add_child(_button("Return to editor", _return_editor))
	else:
		column.add_child(_button("Restart stage", func(): _start(stage)))
		column.add_child(_button("Settings", _settings_menu))
		column.add_child(_button("Save & return to menu", _menu))
	column.add_child(_label("Progress is saved. After closing the app, the current stage restarts with your saved stats. Temporary bonuses reset when a stage restarts.", 16, MUTED))
	queue_redraw()

func _resume() -> void:
	if is_instance_valid(touch_layout) and touch_layout.editing: return
	if not running or terminal:
		return
	paused = false
	controls.enabled = true
	controls.pause_enabled = true
	controls.release_all()
	accumulator = 0.0
	clock_accumulator = 0.0
	clock_last_usec = Time.get_ticks_usec()
	if engine != null and engine.has_method("reset_interpolation"): engine.reset_interpolation()
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_instance_valid(touch_layout) and touch_layout.editing:
			touch_layout.drags.clear()
			controls.release_all()
		if running and not paused:
			_pause("PAUSED", "Welcome back. Resume when you are ready.")
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(touch_layout) and touch_layout.editing:
			touch_layout.cancel()
		elif is_instance_valid(editor) and editor.visible:
			editor._back()
		elif running:
			_toggle_pause()
		else:
			_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_checkpoint()
		_save_settings()

func _save_settings() -> void:
	settings.alternate = controls.alternate
	settings.joy_buttons = controls.joy_buttons.duplicate()
	if not packs.is_empty(): settings.selected_pack = packs[selected].id
	store.set_settings(settings)
	store.flush()

func _set_touch_controls(enabled: bool) -> void:
	settings.touch_controls = enabled
	controls.touch_actions.clear()
	pointer_positions.clear()
	mouse_down = false
	_save_settings()
	_layout()

func _settings_menu() -> void:
	if running and not paused: _pause("PAUSED")
	controls.pause_enabled = false
	var column = _card("SETTINGS", "Touch controls and gamepad preferences are saved on this device.")
	for entry in [["show_fps", "Show FPS"], ["touch_controls", "Show touch controls"], ["mirrored", "Left-handed layout (mirror controls)"], ["alternate", "Original alternate keys (C jump / Z run / X special)"]]:
		var toggle = CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = bool(settings.get(entry[0], false))
		var setting_key: String = entry[0]
		toggle.toggled.connect(func(value: bool):
			if setting_key == "touch_controls":
				_set_touch_controls(value)
			else:
				settings[setting_key] = value
				controls.alternate = bool(settings.get("alternate", false))
				_save_settings()
				_layout()
				_update_fps())
		column.add_child(toggle)
	column.add_child(_button("Edit touch layout", _edit_touch_layout))
	var presentation = OptionButton.new()
	presentation.add_item("30 FPS classic", 30)
	presentation.add_item("60 FPS smooth", 60)
	presentation.selected = 0 if int(settings.get("target_fps", 60)) == 30 else 1
	presentation.item_selected.connect(func(index: int):
		settings.target_fps = presentation.get_item_id(index)
		Engine.max_fps = int(settings.target_fps)
		accumulator = 0.0
		if engine != null and engine.has_method("reset_interpolation"): engine.reset_interpolation()
		_save_settings())
	column.add_child(presentation)
	column.add_child(_label("60 FPS smooths motion without changing game speed.", 16, MUTED))
	for entry in [["opacity", "Touch opacity", 0.25, 1.0, 0.05, 0.75], ["size", "Touch size", 0.7, 1.3, 0.05, 1.0]]:
		column.add_child(_label(entry[1], 18, MUTED))
		var slider = HSlider.new()
		slider.min_value = entry[2]
		slider.max_value = entry[3]
		slider.step = entry[4]
		slider.value = float(settings.get(entry[0], entry[5]))
		slider.custom_minimum_size.y = 32
		var setting_key: String = entry[0]
		slider.value_changed.connect(func(value: float): settings[setting_key] = value; _save_settings(); _layout())
		column.add_child(slider)
	var mapping = HBoxContainer.new()
	column.add_child(mapping)
	for action in ["jump", "run", "special"]:
		var button = _button("Map " + action, _begin_remap.bind(action))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mapping.add_child(button)
	column.add_child(_label("Original secret code", 18, MUTED))
	var secret = LineEdit.new()
	secret.placeholder_text = "Enter a code (0 clears it)"
	secret.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	secret.max_length = 8
	secret.text = str(int(settings.get("secret_code", 0)))
	secret.text_changed.connect(func(value: String):
		if value.is_empty() or value.is_valid_int():
			settings.secret_code = clampi(int(value) if not value.is_empty() else 0, 0, 99999999)
			_save_settings())
	column.add_child(secret)
	column.add_child(_label("Codes apply when you restart a stage.", 16, MUTED))
	column.add_child(_button("Reset selected pack progress…", _reset_dialog))
	column.add_child(_button("Back", func(): _pause("PAUSED") if running else _menu()))

func _begin_remap(action: String) -> void:
	remap_action = action
	var column = _card("MAP " + action.to_upper(), "Press a gamepad button. Start is reserved for pause.")
	column.add_child(_button("Cancel", func(): remap_action = ""; _settings_menu()))

func _reset_dialog() -> void:
	if packs.is_empty(): return
	var column = _card("RESET PROGRESS?", "This clears the selected pack's saved stats and unlocked stages. Imported packs and settings stay on this device.")
	column.add_child(_button("Reset this pack", func(): store.reset_progress(packs[selected].id); running = false; _menu()))
	column.add_child(_button("Cancel", _settings_menu))

func _credits() -> void:
	var column = _card("MADE FOR ADVENTURE", "Oiram by Matt \"MateoConLechuga\" Waltz, 2016–2019. Native Android port for private testing.")
	column.add_child(_label("Nintendo artwork and characters belong to Nintendo. This build is intended for private testing; it is not an official Nintendo product.", 18, MUTED))
	column.add_child(_label("TOUCH  ·  Direction pad + JUMP / RUN / SPECIAL\nKEYBOARD  ·  Arrows, Z jump, X run, C special, Esc pause\nGAMEPAD  ·  D-pad or left stick, A jump, B run, X special, Start pause\nUp also activates doors and the original jump action. Hold Run to move faster. Gameplay is silent.", 18))
	column.add_child(_label("Timing uses a 30 Hz simulation baseline with a separate real-time countdown. Calculator timing has not been hardware calibrated.", 16, MUTED))
	column.add_child(_label("The original Oiram source is distributed under its included license. The CE Programming graphx default font uses LGPL-3.0; see the accompanying licenses/graphx-LGPL-3.0.txt.", 16, MUTED))
	column.add_child(_button("Back", _menu))

func _import_pack() -> void:
	if is_instance_valid(import_dialog): import_dialog.queue_free()
	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.use_native_dialog = true
	import_dialog.filters = PackedStringArray(["*.8xv ; Oiram level packs"])
	import_dialog.title = "Import an Oiram level pack"
	add_child(import_dialog)
	import_dialog.file_selected.connect(func(path: String): notice = ""; _read_pack(path, true); _save_settings(); _menu())
	import_dialog.popup_centered_ratio(0.8)

func _open_editor() -> void:
	controls.pause_enabled = false
	if not ResourceLoader.exists("res://editor/oiram_editor.gd"):
		notice = "The level editor is unavailable in this build."
		_menu()
		return
	if is_instance_valid(overlay): overlay.queue_free(); overlay = null
	bar.visible = false
	screen.visible = false
	if not is_instance_valid(editor):
		editor = load("res://editor/oiram_editor.gd").new()
		add_child(editor)
		if not packs.is_empty() and editor.has_method("set_pack"): editor.set_pack(packs[selected])
		if editor.has_signal("test_level"): editor.connect("test_level", _test_level)
		if editor.has_signal("back_requested"): editor.connect("back_requested", func(): editor.hide(); _load_packs(); _menu())
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.show()

func _test_level(level: Dictionary) -> void:
	if engine == null:
		notice = "The native engine is required to test a stage."
		return
	editor.hide()
	testing = true
	checkpoint = {"lives": 15, "coins": 0, "score": 0, "flags": 0}
	_begin_level(level)

func _return_editor() -> void:
	running = false
	paused = true
	controls.enabled = false
	controls.release_all()
	if is_instance_valid(overlay): overlay.queue_free(); overlay = null
	_open_editor()

func _layout() -> void:
	if not is_instance_valid(screen): return
	bar.position = Vector2(18, 10)
	bar.size = Vector2(maxf(0, size.x - 36), 48)
	var portrait = size.y > size.x
	var control_scale = clampf(float(settings.get("size", 1.0)), 0.7, 1.3)
	var radius = minf(43.0, size.x * 0.065) * control_scale
	var show_touch = bool(settings.get("touch_controls", true)) or touch_layout.editing
	var side_margin = radius * 4.2 + 16 if show_touch else 12.0
	var available = Rect2(Vector2(side_margin, 66), Vector2(maxf(100, size.x - side_margin * 2), maxf(100, size.y - 80)))
	if portrait:
		available = Rect2(Vector2(12, 68), Vector2(size.x - 24, maxf(100, size.y - (280 if show_touch else 80))))
	var scale_factor = minf(available.size.x / 320.0, available.size.y / 240.0)
	screen.size = Vector2(320, 240) * scale_factor
	screen.position = available.position + (available.size - screen.size) * 0.5
	touch_layout.configure(size, settings)
	touch_regions.clear()
	if show_touch: touch_regions.assign(touch_layout.regions)
	fps_label.position = Vector2(maxf(12, size.x - 135), 68)
	fps_label.move_to_front()
	queue_redraw()

func _update_fps() -> void:
	if not is_instance_valid(fps_label): return
	fps_label.visible = bool(settings.get("show_fps", false))
	fps_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())

func _edit_touch_layout() -> void:
	if running and not paused: _pause("PAUSED")
	paused = true
	controls.enabled = false
	controls.pause_enabled = false
	controls.release_all()
	pointer_positions.clear()
	mouse_down = false
	accumulator = 0.0
	clock_accumulator = 0.0
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	bar.hide()
	# The title preview configures the first stage without advancing native logic.
	if not running and engine != null and not packs.is_empty():
		engine.configure(packs[selected].levels[0], {"lives": 15, "coins": 0, "score": 0, "flags": 0})
		_render_frame()
	screen.show()
	touch_layout.move_to_front()
	touch_layout.begin(size, settings)
	_layout()

func _close_touch_layout() -> void:
	_layout()
	bar.visible = running
	screen.visible = running
	_settings_menu()

func _draw() -> void:
	if not running: return
	if is_instance_valid(screen):
		draw_style_box(_frame_style(), Rect2(screen.position - Vector2(3, 3), screen.size + Vector2(6, 6)))
	if paused or not bool(settings.get("touch_controls", true)): return
	var opacity = clampf(float(settings.get("opacity", 0.75)), 0.25, 1.0)
	var font = ThemeDB.fallback_font
	for region in touch_regions:
		var active = (controls.mask() & int(region.action)) != 0
		var color = ACCENT if active else Color("284556")
		color.a = opacity
		draw_circle(region.center, region.radius, color)
		draw_arc(region.center, region.radius, 0, TAU, 40, Color(0.7, 0.82, 0.85, opacity), 2, true)
		var font_size = 16 if int(region.action) >= Controls.JUMP else 23
		var text_size = font.get_string_size(region.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, region.center + Vector2(-text_size.x * 0.5, font_size * 0.35), region.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("0b1d27") if active else INK)

func _frame_style() -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color.BLACK
	box.border_color = Color("426070")
	box.set_border_width_all(2)
	return box

func _touch_action(position_value: Vector2) -> int:
	# Later controls are drawn on top and win when customized layouts overlap.
	for index in range(touch_regions.size() - 1, -1, -1):
		var region = touch_regions[index]
		if position_value.distance_to(region.center) <= region.radius * 1.2:
			return int(region.action)
	return 0

func _input(event: InputEvent) -> void:
	if is_instance_valid(touch_layout) and touch_layout.editing: return
	if not remap_action.is_empty() and event is InputEventJoypadButton and event.pressed and event.button_index != JOY_BUTTON_START:
		controls.joy_buttons[remap_action] = event.button_index
		remap_action = ""
		_save_settings()
		_settings_menu()
		get_viewport().set_input_as_handled()
		return
	if not running or paused or not bool(settings.get("touch_controls", true)): return
	# UI widgets need synthesized mouse events; gameplay already handles each finger.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_positions[event.index] = event.position
			controls.set_touch(event.index, _touch_action(event.position))
		else:
			pointer_positions.erase(event.index)
			controls.set_touch(event.index, 0)
	elif event is InputEventScreenDrag:
		pointer_positions[event.index] = event.position
		controls.set_touch(event.index, _touch_action(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_down = event.pressed
		controls.set_touch(-1, _touch_action(event.position) if mouse_down else 0)
	elif event is InputEventMouseMotion and mouse_down:
		controls.set_touch(-1, _touch_action(event.position))
	queue_redraw()
