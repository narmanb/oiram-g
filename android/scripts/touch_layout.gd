extends Control
## Four draggable anchors. Stored coordinates are normalized before mirroring.
signal saved(layouts: Dictionary)
signal cancelled
signal layout_changed

const Controls = preload("res://scripts/controls.gd")
const KEYS := ["dpad", "jump", "run", "special"]
const ACCENT := Color("f4bf4f")
var editing := false
var layouts: Dictionary = {}
var handles: Dictionary = {}
var regions: Array[Dictionary] = []
var usable := Rect2()
var orientation := "landscape"
var radius := 43.0
var mirrored := false
var opacity := 0.75
var drags: Dictionary = {}
var toolbar: HBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)
	var title = Label.new()
	title.text = "DRAG CONTROLS"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	for entry in [["Save", _save], ["Cancel", cancel], ["Reset", reset]]:
		var button = Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(88, 48)
		button.pressed.connect(entry[1])
		toolbar.add_child(button)
	toolbar.hide()

func configure(viewport_size: Vector2, settings: Dictionary) -> void:
	if not editing:
		layouts = settings.get("touch_layouts", {}).duplicate(true) if settings.get("touch_layouts") is Dictionary else {}
	var new_orientation = "portrait" if viewport_size.y > viewport_size.x else "landscape"
	if new_orientation != orientation:
		drags.clear()
	orientation = new_orientation
	usable = Rect2(Vector2(8, 66), Vector2(maxf(1, viewport_size.x - 16), maxf(1, viewport_size.y - 74)))
	mirrored = bool(settings.get("mirrored", false))
	opacity = clampf(float(settings.get("opacity", 0.75)), 0.25, 1.0)
	radius = minf(minf(43.0, viewport_size.x * 0.065) * float(settings.get("size", 1.0)), minf(usable.size.x, usable.size.y) / 3.7)
	if is_instance_valid(toolbar):
		toolbar.position = Vector2(12, 8)
		toolbar.size = Vector2(maxf(1, viewport_size.x - 24), 48)
		toolbar.visible = editing
		toolbar.get_child(0).visible = viewport_size.x >= 600
	_rebuild()

func begin(viewport_size: Vector2, settings: Dictionary) -> void:
	layouts = settings.get("touch_layouts", {}).duplicate(true) if settings.get("touch_layouts") is Dictionary else {}
	editing = true
	drags.clear()
	configure(viewport_size, settings)
	toolbar.get_child(1).grab_focus()

func _extent(key: String) -> float:
	return radius * {"dpad": 1.85, "jump": 1.0, "run": 0.85, "special": 0.65}[key]

func _clamp_center(key: String, center: Vector2) -> Vector2:
	var extent = Vector2.ONE * _extent(key)
	return center.clamp(usable.position + extent, usable.end - extent)

func _defaults() -> Dictionary:
	var viewport_size = usable.size + Vector2(16, 74)
	var center_y = viewport_size.y - (114 if orientation == "portrait" else 100)
	var right = Vector2(viewport_size.x - radius - 12, center_y)
	return {"dpad": Vector2(radius * 2.05 + 8, center_y), "jump": right + Vector2(0, -radius * 0.6), "run": right + Vector2(-radius * 1.55, radius * 0.8), "special": right + Vector2(-radius * 1.7, -radius * 1.35)}

func _rebuild() -> void:
	var defaults = _defaults()
	var positions: Variant = layouts.get(orientation, {})
	if not positions is Dictionary: positions = {}
	for key in KEYS:
		var center: Vector2 = defaults[key]
		var value: Variant = positions.get(key)
		if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
			if is_finite(float(value[0])) and is_finite(float(value[1])):
				center = usable.position + usable.size * Vector2(clampf(float(value[0]), 0, 1), clampf(float(value[1]), 0, 1))
		if mirrored: center.x = usable.position.x + usable.end.x - center.x
		handles[key] = _clamp_center(key, center)
	regions.clear()
	var spacing = radius * 1.15
	for entry in [[Controls.LEFT, Vector2(-spacing, 0), "◀"], [Controls.RIGHT, Vector2(spacing, 0), "▶"], [Controls.UP, Vector2(0, -spacing), "▲"], [Controls.DOWN, Vector2(0, spacing), "▼"]]:
		regions.append({"action": entry[0], "center": handles.dpad + entry[1], "radius": radius * 0.7, "label": entry[2]})
	for entry in [["jump", Controls.JUMP, "JUMP"], ["run", Controls.RUN, "RUN"], ["special", Controls.SPECIAL, "SP"]]:
		regions.append({"action": entry[1], "center": handles[entry[0]], "radius": _extent(entry[0]), "label": entry[2]})
	queue_redraw()
	layout_changed.emit()

func _record(key: String, center: Vector2) -> void:
	center = _clamp_center(key, center)
	if mirrored: center.x = usable.position.x + usable.end.x - center.x
	var normalized = (center - usable.position) / usable.size
	if not layouts.get(orientation) is Dictionary: layouts[orientation] = {}
	layouts[orientation][key] = [normalized.x, normalized.y]

func _save() -> void:
	for key in KEYS: _record(key, handles[key])
	editing = false
	drags.clear()
	toolbar.hide()
	queue_redraw()
	saved.emit(layouts.duplicate(true))

func cancel() -> void:
	editing = false
	drags.clear()
	toolbar.hide()
	queue_redraw()
	cancelled.emit()

func reset() -> void:
	drags.clear()
	layouts.erase(orientation)
	_rebuild()

func _start_drag(pointer: int, position_value: Vector2) -> bool:
	# Action circles win if the user intentionally overlaps handles.
	for key in ["special", "run", "jump", "dpad"]:
		var extent = _extent(key)
		var hit = Rect2(handles[key] - Vector2.ONE * extent, Vector2.ONE * extent * 2).has_point(position_value) if key == "dpad" else position_value.distance_to(handles[key]) <= extent
		if hit:
			for drag in drags.values():
				if drag.key == key: return false
			drags[pointer] = {"key": key, "offset": handles[key] - position_value}
			return true
	return false

func _move_drag(pointer: int, position_value: Vector2) -> void:
	if not drags.has(pointer): return
	var drag: Dictionary = drags[pointer]
	_record(drag.key, position_value + drag.offset)
	_rebuild()

func _input(event: InputEvent) -> void:
	if not editing: return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _start_drag(event.index, event.position): get_viewport().set_input_as_handled()
		else:
			if drags.has(event.index): get_viewport().set_input_as_handled()
			drags.erase(event.index)
	elif event is InputEventScreenDrag:
		if drags.has(event.index):
			_move_drag(event.index, event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _start_drag(-1, event.position): get_viewport().set_input_as_handled()
		else:
			drags.erase(-1)
	elif event is InputEventMouseMotion and drags.has(-1):
		_move_drag(-1, event.position)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not editing: return
	draw_rect(usable, Color(0.025, 0.04, 0.07, 0.28))
	var font = ThemeDB.fallback_font
	for region in regions:
		draw_circle(region.center, region.radius, Color(0.16, 0.27, 0.34, opacity))
		draw_arc(region.center, region.radius, 0, TAU, 40, ACCENT, 2, true)
		var font_size = 16 if int(region.action) >= Controls.JUMP else 23
		var text_size = font.get_string_size(region.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, region.center + Vector2(-text_size.x * 0.5, font_size * 0.35), region.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("edf4ea"))
	var extent = Vector2.ONE * _extent("dpad")
	draw_rect(Rect2(handles.dpad - extent, extent * 2), ACCENT, false, 2)
	draw_string(font, handles.dpad + Vector2(-22, 5), "DRAG", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)
