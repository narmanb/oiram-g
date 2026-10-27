extends SceneTree
const Editor = preload("res://editor/oiram_editor.gd")
const Pack = preload("res://scripts/oiram_pack.gd")
var failures := 0
var checks := 0
func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	check(Editor.export_destination("content://com.android.providers.downloads.documents/document/123") == "content://com.android.providers.downloads.documents/document/123", "SAF export preserves granted document URI")
	check(Editor.export_destination("/tmp/MyOiram") == "/tmp/MyOiram.8xv", "Filesystem export appends .8xv")
	check(Editor.export_destination("/tmp/MyOiram.8XV") == "/tmp/MyOiram.8XV", "Existing extension is retained")
	var editor := Editor.new()
	root.add_child(editor)
	await process_frame
	check(Pack.validate_pack(editor.pack).is_empty(), "New editor pack is valid")
	var before_import: Dictionary = editor.pack.duplicate(true)
	var oversized_path := OS.get_cache_dir().path_join("oiram-editor-overlimit.8xv")
	var oversized_file := FileAccess.open(oversized_path, FileAccess.WRITE)
	oversized_file.seek(Pack.MAX_FILE_SIZE)
	oversized_file.store_8(0)
	oversized_file.close()
	check(not editor.import_pack(oversized_path), "Oversized file import is rejected before reading bytes")
	check(editor.pack == before_import and editor.dirty, "Rejected oversized import preserves unsaved editor model")
	DirAccess.remove_absolute(oversized_path)
	check(editor.palette.get_child_count() > 150, "Terrain palette contains original tile choices")
	editor.palette_kind.select(1)
	editor._populate_palette()
	check(editor.palette.get_child_count() == 15, "All enemy markers and spawn are available")
	var original: Dictionary = editor.pack.duplicate(true)
	editor._select_tile(244)
	editor._begin_stroke()
	editor.paint_at(Vector2i(6, 8))
	editor.paint_at(Vector2i(7, 8))
	editor._end_stroke()
	check(editor.pack.levels[0].tiles[326] == 244 and editor.pack.levels[0].tiles[327] == 244, "Painting mutates model")
	check(editor.undo_stack.size() == 1, "Drag is a single undo step")
	editor.undo()
	check(editor.pack == original, "Undo restores exact pack")
	editor.redo()
	check(editor.pack.levels[0].tiles[326] == 244, "Redo restores painted tiles")
	editor._select_tile(240)
	editor._begin_stroke()
	editor.paint_at(Vector2i(5, 7))
	editor._end_stroke()
	check(Pack.validate_pack(editor.pack).is_empty() and editor.pack.levels[0].tiles[285] == 240 and editor.pack.levels[0].tiles[322] == 27, "Spawn moves uniquely")
	editor._select_tile(27)
	editor._begin_stroke()
	editor.paint_at(Vector2i(6, 8))
	editor._end_stroke()
	check(editor.pack.levels[0].tiles[326] == 27, "Erase paints empty tile")
	var level: Dictionary = editor.pack.levels[0]
	level.warps = PackedInt32Array([0x400051, 0x80008C])
	editor.width_input.value = 25
	editor.height_input.value = 8
	editor.resize_level()
	check(editor.pack.levels[0].width == 25 and editor.pack.levels[0].height == 8, "Resize changes dimensions")
	check(editor.pack.levels[0].warps == PackedInt32Array([0x400033, 0x80005F]), "Resize relocates warps by XY")
	check(Pack.validate_pack(editor.pack).is_empty(), "Resize keeps map valid")
	editor.undo()
	check(editor.pack.levels[0].width == 40 and editor.pack.levels[0].height == 10, "Resize can be undone")
	editor._add_level()
	check(editor.pack.levels.size() == 2 and editor.level_index == 1 and editor.pack.levels[1].count == 2, "Add level updates indices")
	editor._delete_level()
	check(editor.pack.levels.size() == 1, "Remove level works")
	editor.undo()
	check(editor.pack.levels.size() == 2, "Remove level can be undone")
	editor.save_pack()
	check(not editor.dirty and FileAccess.file_exists(Editor.SAVE_PATH), "Save writes .8xv in app storage")
	var expected: Dictionary = editor.pack.duplicate(true)
	editor._new_pack()
	editor.load_saved()
	check(editor.pack.levels == expected.levels, "Load saved restores all levels")
	check(Pack.load_bytes(FileAccess.get_file_as_bytes(Editor.SAVE_PATH)).ok, "Saved file passes independent codec validation")
	var signal_seen := [false]
	editor.test_level.connect(func(value: Dictionary): signal_seen[0] = value.index == 0 and value.count == 1 and Pack.validate_level(value).is_empty())
	editor._test()
	check(signal_seen[0], "Test emits a validated standalone native level")
	# Test importing the full bundled pack while keeping source data independent.
	var imported := Pack.load_bytes(FileAccess.get_file_as_bytes("res://assets/OiramPK.8xv"))
	editor.set_pack(imported, 5)
	check(editor.level_index == 5 and editor.canvas.level.height == 100, "Import opens requested level")
	editor._select_tile(27)
	editor._begin_stroke()
	editor.paint_at(Vector2i(0, 0))
	editor._end_stroke()
	check(imported.levels == Pack.load_bytes(FileAccess.get_file_as_bytes("res://assets/OiramPK.8xv")).levels, "Editing does not mutate imported source")
	# Route real touch events through the viewport and GUI hit testing.
	editor._new_pack()
	editor._select_tile(244)
	await process_frame
	await process_frame
	var touch_position: Vector2 = editor.canvas.global_position + editor.canvas.pan + Vector2(10.5, 8.5) * 16.0 * editor.canvas.zoom
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = touch_position
	press.pressed = true
	root.push_input(press, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = touch_position + Vector2(32, 0)
	drag.relative = Vector2(32, 0)
	root.push_input(drag, true)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	check(editor.pack.levels[0].tiles[330] == 244 and editor.pack.levels[0].tiles[331] == 244, "Viewport touch press and drag paint tiles")
	check(not editor.canvas.painting and editor.canvas.pointer_id == -1, "Touch release finishes painting and clears pointer ownership")
	var old_pan: Vector2 = editor.canvas.pan
	editor.pan_button.button_pressed = true
	editor._toggle_pan()
	root.push_input(press, true)
	root.push_input(drag, true)
	root.push_input(release, true)
	await process_frame
	check(editor.canvas.pan == old_pan + Vector2(32, 0), "Touch Pan tool moves viewport")
	check(editor.canvas.size.x >= 240 and editor.canvas.size.y >= 160 and editor.canvas.global_position.x + editor.canvas.size.x <= 960, "Editor map fits landscape viewport")
	editor.pack.levels[0] = editor._blank_level(255, 255)
	editor._sync_ui()
	editor.canvas.fit_map()
	check(editor.canvas.zoom * 255 * 16 <= minf(editor.canvas.size.x, editor.canvas.size.y), "Fit includes largest allowed map")
	editor.queue_free()
	await process_frame
	print("Editor: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
