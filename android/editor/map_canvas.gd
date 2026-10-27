extends Control
## A bounded map viewport: dragging paints, Pan tool/middle mouse moves the view.
signal stroke_started
signal paint_tile(cell: Vector2i)
signal stroke_ended
signal hovered(cell: Vector2i)

var level: Dictionary = {}
var tile_textures: Dictionary = {}
var zoom := 2.0
var pan := Vector2(12, 12)
var pan_tool := false
var painting := false
var panning := false
var pointer_id := -1
var previous_cell := Vector2i(-1, -1)
var pointer_cell := Vector2i(-1, -1)
var selected_tile := 4

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(240, 160)
	focus_mode = Control.FOCUS_ALL

func set_level(value: Dictionary) -> void:
	level = value
	queue_redraw()

func set_zoom(value: float) -> void:
	var next := clampf(value, 0.05, 5.0)
	var center := size * 0.5
	pan = center - (center - pan) * next / zoom
	zoom = next
	queue_redraw()

func fit_map() -> void:
	if level.is_empty():
		return
	zoom = clampf(minf((size.x - 24.0) / (level.width * 16.0), (size.y - 24.0) / (level.height * 16.0)), 0.05, 3.0)
	pan = Vector2(12, 12)
	queue_redraw()

func cell_at(position: Vector2) -> Vector2i:
	return Vector2i(floori((position.x - pan.x) / (16.0 * zoom)), floori((position.y - pan.y) / (16.0 * zoom)))

func _inside(cell: Vector2i) -> bool:
	return not level.is_empty() and cell.x >= 0 and cell.y >= 0 and cell.x < level.width and cell.y < level.height

func _paint_at(position: Vector2) -> void:
	var cell := cell_at(position)
	pointer_cell = cell
	hovered.emit(cell)
	if not _inside(cell):
		previous_cell = Vector2i(-1, -1)
		return
	if previous_cell == cell:
		return
	# Fill gaps between pointer samples so quick strokes remain continuous.
	if _inside(previous_cell):
		var steps := maxi(absi(cell.x - previous_cell.x), absi(cell.y - previous_cell.y))
		for i in range(1, steps + 1):
			paint_tile.emit(Vector2i(Vector2(previous_cell).lerp(Vector2(cell), float(i) / steps).round()))
	else:
		paint_tile.emit(cell)
	previous_cell = cell
	queue_redraw()

func _start(position: Vector2, as_pan: bool) -> void:
	grab_focus()
	panning = as_pan
	painting = not as_pan
	previous_cell = Vector2i(-1, -1)
	if painting:
		stroke_started.emit()
		_paint_at(position)

func _finish() -> void:
	if painting:
		stroke_ended.emit()
	painting = false
	panning = false
	pointer_id = -1
	previous_cell = Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			set_zoom(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8))
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_start(event.position, pan_tool or event.button_index != MOUSE_BUTTON_LEFT)
			else:
				_finish()
		accept_event()
	elif event is InputEventMouseMotion:
		pointer_cell = cell_at(event.position)
		hovered.emit(pointer_cell)
		if panning:
			pan += event.relative
		elif painting:
			_paint_at(event.position)
		queue_redraw()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and pointer_id == -1:
			pointer_id = event.index
			_start(event.position, pan_tool)
		elif not event.pressed and event.index == pointer_id:
			_finish()
		accept_event()
	elif event is InputEventScreenDrag and event.index == pointer_id:
		if panning:
			pan += event.relative
		elif painting:
			_paint_at(event.position)
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom * event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		pan -= event.delta * 10
		queue_redraw()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111b2b"))
	if level.is_empty():
		return
	var tile_size := 16.0 * zoom
	var c := int(level.get("color", 0xD77E))
	var background := Color(float((c >> 10) & 31) / 31.0, float(((c >> 4) & 62) | ((c >> 15) & 1)) / 63.0, float(c & 31) / 31.0)
	draw_rect(Rect2(pan, Vector2(level.width, level.height) * tile_size), background)
	var from_x := clampi(floori(-pan.x / tile_size), 0, level.width)
	var from_y := clampi(floori(-pan.y / tile_size), 0, level.height)
	var to_x := clampi(ceili((size.x - pan.x) / tile_size), 0, level.width)
	var to_y := clampi(ceili((size.y - pan.y) / tile_size), 0, level.height)
	for y in range(from_y, to_y):
		for x in range(from_x, to_x):
			var tile: int = level.tiles[y * level.width + x]
			var rect := Rect2(pan + Vector2(x, y) * tile_size, Vector2.ONE * tile_size)
			if tile != 27 and tile_textures.has(tile):
				draw_texture_rect(tile_textures[tile], rect, false)
			if tile >= 240:
				draw_rect(rect.grow(-1), Color("f8d775") if tile == 240 else Color("ef7d9a"), false, maxf(1.0, zoom))
	if zoom >= 1.0:
		var grid_color := Color(0.05, 0.1, 0.2, 0.28)
		for x in range(from_x, to_x + 1):
			draw_line(pan + Vector2(x, from_y) * tile_size, pan + Vector2(x, to_y) * tile_size, grid_color)
		for y in range(from_y, to_y + 1):
			draw_line(pan + Vector2(from_x, y) * tile_size, pan + Vector2(to_x, y) * tile_size, grid_color)
	var warps: PackedInt32Array = level.get("warps", PackedInt32Array())
	for i in range(warps.size()):
		var position := warps[i] & 0x07FFFF
		var cell := Vector2(position % int(level.width), position / int(level.width))
		var center := pan + (cell + Vector2.ONE * 0.5) * tile_size
		draw_circle(center, tile_size * 0.3, Color("5fffd7") if i % 2 == 0 else Color("b8a5ff"), false, maxf(1.0, zoom))
		draw_string(ThemeDB.fallback_font, center + Vector2(-tile_size * 0.2, tile_size * 0.15), str(i / 2 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(tile_size * 0.4)), Color.WHITE)
	if _inside(pointer_cell) and not pan_tool:
		draw_rect(Rect2(pan + Vector2(pointer_cell) * tile_size, Vector2.ONE * tile_size), Color.WHITE, false, 2.0)
