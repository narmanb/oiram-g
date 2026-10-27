extends Control
## Mobile map editor using the same validated pack model as native gameplay.
signal test_level(level: Dictionary)
signal back_requested

const Pack = preload("res://scripts/oiram_pack.gd")
const Canvas = preload("res://editor/map_canvas.gd")
const Catalog = preload("res://editor/tile_catalog.gd")
const SAVE_PATH := "user://editor/current.8xv"
const MAX_HISTORY := 16

var pack: Dictionary = {}
var level_index := 0
var selected_tile := 4
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var stroke_before: Dictionary = {}
var stroke_changed := false
var syncing := false
var dirty := false
var canvas: Control
var status: Label
var brush_label: Label
var level_selector: OptionButton
var width_input: SpinBox
var height_input: SpinBox
var name_input: LineEdit
var author_input: LineEdit
var scroll_input: OptionButton
var color_input: ColorPickerButton
var palette: GridContainer
var palette_kind: OptionButton
var textures: Dictionary = {}
var file_dialog: FileDialog
var export_mode := false
var pan_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_build_ui()
	if pack.is_empty():
		_new_pack()
	else:
		_sync_ui()

func set_pack(value: Dictionary, index: int = 0) -> void:
	pack = value.duplicate(true)
	level_index = clampi(index, 0, maxi(0, pack.get("levels", []).size() - 1))
	undo_stack.clear()
	redo_stack.clear()
	dirty = false
	if is_node_ready():
		_sync_ui()

func _image_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	return texture

func _load_textures() -> void:
	var atlas := _image_texture("res://editor/tileset.png")
	for tile in range(240):
		var x: int = Catalog.REGIONS[tile * 2]
		var y: int = Catalog.REGIONS[tile * 2 + 1]
		if y >= 14:
			continue
		var texture := AtlasTexture.new()
		texture.atlas = atlas
		texture.region = Rect2(x * 16, y * 16, 16, 16)
		textures[tile] = texture
	# Animated base tiles have no desktop-palette location; show their first frame.
	for tile in [0, 1, 2, 3]:
		textures[tile] = textures[225]
	for tile in [5, 6, 7]:
		textures[tile] = textures[4]
	textures[9] = textures[8]
	textures[10] = textures[8]
	textures[233] = textures[238]
	textures[234] = textures[235]
	for tile in Catalog.MARKERS:
		textures[tile] = _image_texture("res://editor/markers/%s.png" % Catalog.MARKERS[tile])

func _button(parent: Node, text: String, action: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(48, 40)
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("132036")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var tools := HBoxContainer.new()
	root.add_child(tools)
	_button(tools, "Back", _back)
	_button(tools, "New", _new_pack, "Create a new one-level pack")
	_button(tools, "Save", save_pack, "Save to app storage; an earlier save is kept as a backup")
	_button(tools, "Load saved", load_saved)
	_button(tools, "Import", _choose_import, "Open an original .8xv pack")
	_button(tools, "Export .8xv", _choose_export, "Write an original-editor-compatible pack")
	_button(tools, "Test ▶", _test, "Play this level in the native engine")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	_label(tools, "MAP EDITOR")
	var meta := HBoxContainer.new()
	root.add_child(meta)
	_label(meta, "Name")
	name_input = LineEdit.new()
	name_input.max_length = 26
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.custom_minimum_size.x = 90
	name_input.text_changed.connect(_metadata_changed)
	meta.add_child(name_input)
	_label(meta, "Author")
	author_input = LineEdit.new()
	author_input.max_length = 21
	author_input.custom_minimum_size.x = 90
	author_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	author_input.text_changed.connect(_metadata_changed)
	meta.add_child(author_input)
	level_selector = OptionButton.new()
	level_selector.custom_minimum_size.x = 95
	level_selector.item_selected.connect(_select_level)
	meta.add_child(level_selector)
	_button(meta, "+", _add_level, "Add a blank level")
	_button(meta, "−", _delete_level, "Remove current level (Undo restores it)")
	_label(meta, "W")
	width_input = SpinBox.new()
	width_input.min_value = 20
	width_input.max_value = 255
	width_input.custom_minimum_size.x = 70
	meta.add_child(width_input)
	_label(meta, "H")
	height_input = SpinBox.new()
	height_input.min_value = 8
	height_input.max_value = 255
	height_input.custom_minimum_size.x = 70
	meta.add_child(height_input)
	_button(meta, "Resize", resize_level, "Preserves tiles; adjusts existing warp indices, drops cropped warps")
	var brush_row := HBoxContainer.new()
	root.add_child(brush_row)
	_button(brush_row, "Paint", func(): _select_tile(selected_tile))
	_button(brush_row, "Erase", func(): _select_tile(27))
	_button(brush_row, "Spawn", func(): _select_tile(240))
	pan_button = _button(brush_row, "Pan", _toggle_pan, "Drag to move the map; middle/right mouse also pans")
	pan_button.toggle_mode = true
	_button(brush_row, "Undo", undo)
	_button(brush_row, "Redo", redo)
	_button(brush_row, "− zoom", func(): canvas.set_zoom(canvas.zoom * 0.8))
	_button(brush_row, "+ zoom", func(): canvas.set_zoom(canvas.zoom * 1.25))
	_button(brush_row, "Fit", func(): canvas.fit_map())
	scroll_input = OptionButton.new()
	for title in ["No scroll", "Scroll right", "Scroll left", "Scroll down", "Scroll up"]:
		scroll_input.add_item(title)
	scroll_input.item_selected.connect(_scroll_changed)
	brush_row.add_child(scroll_input)
	color_input = ColorPickerButton.new()
	color_input.custom_minimum_size = Vector2(40, 40)
	color_input.edit_alpha = false
	color_input.tooltip_text = "Background color"
	color_input.color_changed.connect(_color_changed)
	brush_row.add_child(color_input)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 212
	body.add_child(sidebar)
	palette_kind = OptionButton.new()
	for title in ["Terrain & objects", "Enemies & spawn"]:
		palette_kind.add_item(title)
	palette_kind.item_selected.connect(func(_index): _populate_palette())
	sidebar.add_child(palette_kind)
	brush_label = _label(sidebar, "Brick · tile 4")
	brush_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var palette_scroll := ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(palette_scroll)
	palette = GridContainer.new()
	palette.columns = 4
	palette_scroll.add_child(palette)
	canvas = Canvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.tile_textures = textures
	canvas.stroke_started.connect(_begin_stroke)
	canvas.paint_tile.connect(paint_at)
	canvas.stroke_ended.connect(_end_stroke)
	canvas.hovered.connect(_hovered)
	body.add_child(canvas)
	status = _label(root, "Paint by dragging. Pan tool moves the map. Save keeps a local .8xv copy.")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 36
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.8xv ; Oiram TI AppVar pack"])
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	_populate_palette()

func _populate_palette() -> void:
	for child in palette.get_children():
		palette.remove_child(child)
		child.queue_free()
	for tile in range(255):
		if not textures.has(tile):
			continue
		if (tile >= 240) != (palette_kind.selected == 1):
			continue
		# Base animation frames are shown as their explicit editable variants.
		if tile in [0, 1, 2, 3, 5, 6, 7, 9, 10, 233, 234]:
			continue
		var button := Button.new()
		button.icon = textures[tile]
		button.expand_icon = true
		button.custom_minimum_size = Vector2(46, 46)
		button.add_theme_constant_override("icon_max_width", 32)
		button.tooltip_text = "%s · tile %d" % [Catalog.NAMES.get(tile, "Terrain"), tile]
		button.pressed.connect(_select_tile.bind(tile))
		palette.add_child(button)

func _blank_level(width: int = 40, height: int = 10) -> Dictionary:
	var tiles := PackedByteArray()
	tiles.resize(width * height)
	tiles.fill(27)
	for x in range(width):
		tiles[(height - 1) * width + x] = 13
	tiles[(height - 2) * width + 2] = 240
	# Include the original paired end-pipe tiles, so the blank map is finishable.
	tiles[(height - 2) * width + width - 4] = 109
	tiles[(height - 2) * width + width - 3] = 110
	return {"width": width, "height": height, "tiles": tiles, "warps": PackedInt32Array(), "scroll": 0, "color": 0xD77E, "index": 0, "count": 1}

func _new_pack() -> void:
	if not pack.is_empty():
		_push_undo()
	pack = {"name": "My Oiram Pack", "author": "", "version": 0xCE, "password_hash": 0, "var_name": "OiramPK", "levels": [_blank_level()]}
	level_index = 0
	dirty = true
	if is_node_ready():
		_sync_ui()
		canvas.pan = Vector2(12, 12)
		canvas.zoom = 2.0
		_set_status("New pack. Paint tiles, place enemies, then Test or Save.")

func _current() -> Dictionary:
	return pack.levels[level_index]

func _sync_ui() -> void:
	if pack.is_empty() or not is_instance_valid(canvas):
		return
	syncing = true
	for i in range(pack.levels.size()):
		pack.levels[i].index = i
		pack.levels[i].count = pack.levels.size()
	level_index = clampi(level_index, 0, pack.levels.size() - 1)
	name_input.text = pack.get("name", "")
	author_input.text = pack.get("author", "")
	level_selector.clear()
	for i in range(pack.levels.size()):
		level_selector.add_item("Level %d" % (i + 1))
	level_selector.select(level_index)
	width_input.value = _current().width
	height_input.value = _current().height
	scroll_input.select(_current().get("scroll", 0))
	var c := int(_current().get("color", 0xD77E))
	color_input.color = Color(float((c >> 10) & 31) / 31.0, float(((c >> 4) & 62) | ((c >> 15) & 1)) / 63.0, float(c & 31) / 31.0)
	canvas.set_level(_current())
	syncing = false

func _select_tile(tile: int) -> void:
	selected_tile = tile
	canvas.selected_tile = tile
	canvas.pan_tool = false
	pan_button.set_pressed_no_signal(false)
	brush_label.text = "%s · %d" % [Catalog.NAMES.get(tile, "Terrain"), tile]
	_set_status("Drag on the map to paint %s." % Catalog.NAMES.get(tile, "tile %d" % tile))

func _toggle_pan() -> void:
	canvas.pan_tool = pan_button.button_pressed
	_set_status("Drag the map to pan." if canvas.pan_tool else "Drag the map to paint.")

func _select_level(index: int) -> void:
	_end_stroke()
	level_index = index
	_sync_ui()
	canvas.pan = Vector2(12, 12)

func _snapshot() -> Dictionary:
	return {"pack": pack.duplicate(true), "index": level_index}

func _push_undo(snapshot: Dictionary = {}) -> void:
	undo_stack.append(_snapshot() if snapshot.is_empty() else snapshot)
	if undo_stack.size() > MAX_HISTORY:
		undo_stack.pop_front()
	redo_stack.clear()

func _begin_stroke() -> void:
	stroke_before = _snapshot()
	stroke_changed = false

func paint_at(cell: Vector2i) -> void:
	var level := _current()
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	var position: int = cell.y * level.width + cell.x
	if level.tiles[position] == selected_tile:
		return
	if stroke_before.is_empty():
		_begin_stroke()
	if selected_tile == 240:
		for i in range(level.tiles.size()):
			if level.tiles[i] == 240:
				level.tiles[i] = 27
	elif level.tiles[position] == 240:
		_set_status("Move the player spawn with the Spawn tool before painting this tile.")
		return
	level.tiles[position] = selected_tile
	stroke_changed = true
	dirty = true
	canvas.queue_redraw()

func _end_stroke() -> void:
	if stroke_changed and not stroke_before.is_empty():
		_push_undo(stroke_before)
	stroke_before = {}
	stroke_changed = false

func undo() -> void:
	_end_stroke()
	if undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	redo_stack.append(_snapshot())
	var previous: Dictionary = undo_stack.pop_back()
	pack = previous.pack
	level_index = previous.index
	dirty = true
	_sync_ui()
	_set_status("Undid the last change.")

func redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nothing to redo.")
		return
	undo_stack.append(_snapshot())
	var next: Dictionary = redo_stack.pop_back()
	pack = next.pack
	level_index = next.index
	dirty = true
	_sync_ui()
	_set_status("Redid the last change.")

func resize_level() -> void:
	_end_stroke()
	var old := _current()
	var width := int(width_input.value)
	var height := int(height_input.value)
	if width == old.width and height == old.height:
		return
	_push_undo()
	var tiles := PackedByteArray()
	tiles.resize(width * height)
	tiles.fill(27)
	var found_spawn := false
	for y in range(mini(height, old.height)):
		for x in range(mini(width, old.width)):
			var tile: int = old.tiles[y * old.width + x]
			tiles[y * width + x] = tile
			found_spawn = found_spawn or tile == 240
	if not found_spawn:
		tiles[width + 1] = 240
	var warps := PackedInt32Array()
	var old_warps: PackedInt32Array = old.get("warps", PackedInt32Array())
	for i in range(0, old_warps.size(), 2):
		var pair := PackedInt32Array()
		for j in range(2):
			var position := old_warps[i + j] & 0x07FFFF
			var x: int = position % int(old.width)
			var y: int = position / int(old.width)
			var flag := old_warps[i + j] & 0xF80000
			if x >= width or y >= height or (flag == 0x080000 and y + 1 >= height):
				break
			pair.append((y * width + x) | flag)
		if pair.size() == 2:
			warps.append_array(pair)
	old.width = width
	old.height = height
	old.tiles = tiles
	old.warps = warps
	dirty = true
	_sync_ui()
	_set_status("Resized to %d × %d. Cropped tiles and warp pairs can be restored with Undo." % [width, height])

func _add_level() -> void:
	if pack.levels.size() >= 255:
		_set_status("The original format supports at most 255 levels.")
		return
	_push_undo()
	pack.levels.append(_blank_level())
	level_index = pack.levels.size() - 1
	dirty = true
	_sync_ui()

func _delete_level() -> void:
	if pack.levels.size() <= 1:
		_set_status("A pack needs at least one level.")
		return
	_push_undo()
	pack.levels.remove_at(level_index)
	level_index = mini(level_index, pack.levels.size() - 1)
	dirty = true
	_sync_ui()

func _metadata_changed(_value: String) -> void:
	if syncing:
		return
	if pack.name == name_input.text and pack.author == author_input.text:
		return
	_push_undo()
	pack.name = name_input.text
	pack.author = author_input.text
	dirty = true

func _scroll_changed(value: int) -> void:
	if syncing:
		return
	_push_undo()
	_current().scroll = value
	dirty = true

func _color_changed(value: Color) -> void:
	if syncing:
		return
	var r := roundi(value.r * 31)
	var g := roundi(value.g * 63)
	var b := roundi(value.b * 31)
	var encoded := ((g & 1) << 15) | (r << 10) | ((g >> 1) << 5) | b
	if encoded == _current().color:
		return
	_push_undo()
	_current().color = encoded
	dirty = true
	canvas.queue_redraw()

func _set_status(message: String) -> void:
	if is_instance_valid(status):
		status.text = message

func _hovered(cell: Vector2i) -> void:
	if canvas.painting or canvas.panning:
		return
	if cell.x >= 0 and cell.y >= 0 and cell.x < _current().width and cell.y < _current().height:
		var tile: int = _current().tiles[cell.y * _current().width + cell.x]
		_set_status("%d, %d · tile %d · %s%s" % [cell.x, cell.y, tile, Catalog.NAMES.get(tile, "Terrain"), " · unsaved changes" if dirty else ""])

func _encoded() -> PackedByteArray:
	_end_stroke()
	var problem := Pack.validate_pack(pack)
	if not problem.is_empty():
		_set_status(problem)
		return PackedByteArray()
	var bytes := Pack.encode(pack)
	if bytes.is_empty():
		_set_status("The compressed pack is too large for a TI AppVar. Use fewer tiles or levels.")
	return bytes

func save_pack() -> void:
	var bytes := _encoded()
	if bytes.is_empty():
		return
	var path := ProjectSettings.globalize_path(SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		_set_status("Cannot write the local pack: " + error_string(FileAccess.get_open_error()))
		return
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_status("Saving failed: " + error_string(write_error))
		return
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			_set_status("Cannot preserve the previous save; the current file was kept.")
			return
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(path + ".bak", path)
		_set_status("Saving failed: " + error_string(result))
		return
	dirty = false
	_set_status("Saved to app storage. Export .8xv shares an original-compatible file.")

func load_saved() -> void:
	var result := _load_path(SAVE_PATH)
	if not result:
		_load_path(SAVE_PATH + ".bak")

func _load_path(path: String) -> bool:
	return import_pack(path)

func import_pack(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Cannot open pack: " + error_string(FileAccess.get_open_error()))
		return false
	var length := file.get_length()
	if length <= 0 or length > Pack.MAX_FILE_SIZE:
		file.close()
		_set_status("Pack file size must be 1..%d bytes." % Pack.MAX_FILE_SIZE)
		return false
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		_set_status("Cannot read the complete pack file.")
		return false
	var result := Pack.load_bytes(bytes)
	if not result.ok:
		_set_status(result.error)
		return false
	_push_undo()
	pack = result
	level_index = 0
	dirty = false
	_sync_ui()
	_set_status("Loaded %s · %d levels." % [pack.name, pack.levels.size()])
	return true

func _choose_import() -> void:
	export_mode = false
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Import Oiram .8xv pack"
	file_dialog.popup_centered_ratio(0.85)

func _choose_export() -> void:
	if _encoded().is_empty():
		return
	export_mode = true
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Export Oiram .8xv pack"
	file_dialog.current_file = "MyOiram.8xv"
	file_dialog.popup_centered_ratio(0.85)

static func export_destination(path: String) -> String:
	# SAF grants access to this exact content URI; its document ID is opaque.
	if path.begins_with("content://") or path.get_extension().to_lower() == "8xv":
		return path
	return path + ".8xv"

func _file_selected(path: String) -> void:
	if not export_mode:
		_load_path(path)
		return
	var bytes := _encoded()
	if bytes.is_empty():
		return
	path = export_destination(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Export failed: " + error_string(FileAccess.get_open_error()))
		return
	file.store_buffer(bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	_set_status("Exported " + path if result == OK else "Export failed: " + error_string(result))

func _test() -> void:
	_end_stroke()
	var problem := Pack.validate_level(_current())
	if not problem.is_empty():
		_set_status(problem)
		return
	var level := _current().duplicate(true)
	level.index = 0
	level.count = 1
	test_level.emit(level)

func _back() -> void:
	_end_stroke()
	if dirty:
		save_pack()
		if dirty:
			_set_status("Fix the pack before leaving so it can be saved. Undo can restore a valid map.")
			return
	back_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			redo()
		else:
			undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		redo()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		save_pack()
