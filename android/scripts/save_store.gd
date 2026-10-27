extends RefCounted
## Checkpoints restart the current stage; the native engine has no mid-stage snapshot.

var path := "user://progress.json"
var data: Dictionary = {"version": 1, "packs": {}, "settings": {}}

func _valid_id(pack_id: String) -> bool:
	return pack_id.length() == 64 and pack_id.is_valid_hex_number(false)

func _number(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if not (value is int or value is float):
		return fallback
	if value is float and not is_finite(value):
		return fallback
	if value is float:
		return int(clampf(value, minimum, maximum))
	return clampi(int(value), minimum, maximum)

func _checkpoint(value: Dictionary) -> Dictionary:
	var lives = _number(value.get("lives"), 15, -1, 99)
	if lives < 1:
		return {"level": 0, "unlocked": 0, "lives": 15, "coins": 0, "score": 0, "flags": 0}
	return {"level": _number(value.get("level"), 0, 0, 255), "unlocked": _number(value.get("unlocked"), 0, 0, 255), "lives": lives, "coins": _number(value.get("coins"), 0, 0, 99), "score": _number(value.get("score"), 0, 0, 0xFFFFFF), "flags": _number(value.get("flags"), 0, 0, 255) & 19}

func _read_valid(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		return {}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed = parser.data
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("packs") is Dictionary or not parsed.get("settings") is Dictionary:
		return {}
	var packs: Dictionary = {}
	for pack_id in parsed.packs:
		if pack_id is String and _valid_id(pack_id) and parsed.packs[pack_id] is Dictionary:
			packs[pack_id] = _checkpoint(parsed.packs[pack_id])
	return {"version": 1, "packs": packs, "settings": parsed.settings}

func load_data() -> void:
	var loaded = _read_valid(path)
	if loaded.is_empty():
		loaded = _read_valid(path + ".bak")
	data = loaded if not loaded.is_empty() else {"version": 1, "packs": {}, "settings": {}}

func progress(pack_id: String) -> Dictionary:
	if not _valid_id(pack_id):
		return {}
	return data.packs.get(pack_id, {}).duplicate(true)

func set_progress(pack_id: String, value: Dictionary) -> void:
	if _valid_id(pack_id):
		data.packs[pack_id] = _checkpoint(value)

func reset_progress(pack_id: String) -> void:
	data.packs.erase(pack_id)
	flush()

func settings() -> Dictionary:
	return data.settings.duplicate(true)

func set_settings(value: Dictionary) -> void:
	data.settings = value.duplicate(true)

func flush() -> bool:
	var temp_path = path + ".tmp"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	if _read_valid(temp_path).is_empty():
		return false
	var absolute = ProjectSettings.globalize_path(path)
	var backup = absolute + ".bak"
	if FileAccess.file_exists(path) and not _read_valid(path).is_empty():
		DirAccess.remove_absolute(backup)
		if DirAccess.copy_absolute(absolute, backup) != OK:
			return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), absolute) == OK

func clear_files() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
