class_name OiramPack
extends RefCounted
## Bounded codec for the original Oiram CD/CE TI AppVar format.
## Never pass unvalidated imported bytes directly to the native engine.

const HEADER := [0x2A, 0x2A, 0x54, 0x49, 0x38, 0x33, 0x46, 0x2A, 0x1A, 0x0A, 0x00]
const PAYLOAD_START := 0x4A
const MAX_FILE_SIZE := 0x37 + 65535 + 2
const WARP_FLAGS := 0xF80000
const WARP_INDEX := 0x07FFFF
const VALID_FLAGS := [0, 0x800000, 0x400000, 0x200000, 0x100000, 0x080000]
const MAX_NAME := 26
const MAX_AUTHOR := 21

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message, "name": "", "author": "", "levels": []}

static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)

static func _u24(bytes: PackedByteArray, offset: int) -> int:
	return _u16(bytes, offset) | (bytes[offset + 2] << 16)

static func _put16(bytes: PackedByteArray, offset: int, value: int) -> void:
	bytes[offset] = value & 255
	bytes[offset + 1] = (value >> 8) & 255

static func _append24(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 255)
	bytes.append((value >> 8) & 255)
	bytes.append((value >> 16) & 255)

static func _single_byte_text(bytes: PackedByteArray, first: int, end: int) -> String:
	var result := ""
	for i in range(first, end):
		result += String.chr(bytes[i])
	return result

static func _single_byte_buffer(value: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	for i in range(value.length()):
		bytes.append(value.unicode_at(i))
	return bytes

static func _text(bytes: PackedByteArray, offset: int, end: int, maximum: int) -> Dictionary:
	var cursor := offset
	while cursor < end and cursor - offset <= maximum:
		if bytes[cursor] == 0:
			return {"ok": true, "value": _single_byte_text(bytes, offset, cursor), "next": cursor + 1}
		# Preserve original single-byte text, including Latin-1 author names.
		if bytes[cursor] < 32 or bytes[cursor] == 127:
			return {"ok": false}
		cursor += 1
	return {"ok": false}

static func load_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < PAYLOAD_START + 2 + 2 + 1 + 5 + 1 + 2 or bytes.size() > MAX_FILE_SIZE:
		return _error("Invalid TI AppVar file size")
	for i in range(HEADER.size()):
		if bytes[i] != HEADER[i]:
			return _error("Invalid TI AppVar signature")
	var section_size := _u16(bytes, 0x35)
	var end := bytes.size() - 2
	if section_size != end - 0x37:
		return _error("TI data section length does not match the file")
	if _u16(bytes, 0x37) != 13 or bytes[0x3B] != 0x15:
		return _error("Expected a single TI AppVar with a 13 byte variable header")
	var data_size := _u16(bytes, 0x39)
	if data_size != _u16(bytes, 0x46) or data_size != end - 0x48:
		return _error("TI variable data lengths do not match")
	if _u16(bytes, 0x48) != end - PAYLOAD_START:
		return _error("TI AppVar payload length does not match")
	var checksum := 0
	for i in range(0x37, end):
		checksum = (checksum + bytes[i]) & 65535
	if checksum != _u16(bytes, end):
		return _error("TI checksum mismatch")
	if bytes[PAYLOAD_START] != 0xAB or bytes[PAYLOAD_START + 1] not in [0xCD, 0xCE]:
		return _error("Unknown Oiram pack version (expected AB CD or AB CE)")
	var version := int(bytes[PAYLOAD_START + 1])
	var cursor := PAYLOAD_START + 2
	var password_hash := 0
	if version == 0xCE:
		if cursor + 4 > end:
			return _error("Truncated CE password hash")
		for i in range(4):
			password_hash = (password_hash << 8) | bytes[cursor + i]
		cursor += 4
	var name_text := _text(bytes, cursor, end, MAX_NAME)
	if not name_text.ok:
		return _error("Pack name is not bounded printable text (maximum 26 bytes)")
	cursor = name_text.next
	var author_text := _text(bytes, cursor, end, MAX_AUTHOR)
	if not author_text.ok:
		return _error("Author is not bounded printable text (maximum 21 bytes)")
	cursor = author_text.next
	if cursor >= end:
		return _error("Missing level count")
	var count := int(bytes[cursor])
	cursor += 1
	if count < 1:
		return _error("A pack must contain 1 to 255 levels")
	var base := cursor + (count - 1) * 2
	if base >= end:
		return _error("Truncated level offset table")
	var offsets: Array[int] = [base]
	for i in range(count - 1):
		var offset := base + _u16(bytes, cursor + i * 2)
		if offset <= offsets[-1] or offset >= end:
			return _error("Level offsets must increase and remain inside the payload")
		offsets.append(offset)
	offsets.append(end)
	var levels: Array[Dictionary] = []
	for index in range(count):
		cursor = offsets[index]
		var limit := offsets[index + 1]
		if cursor + 5 >= limit:
			return _error("Level %d: truncated level header" % (index + 1))
		var color := _u16(bytes, cursor)
		cursor += 2
		var scroll := 0
		if bytes[cursor] == 255:
			if cursor + 2 >= limit:
				return _error("Level %d: truncated scroll header" % (index + 1))
			scroll = bytes[cursor + 1]
			cursor += 2
		var warp_count := int(bytes[cursor])
		cursor += 1
		if cursor + warp_count * 6 + 2 >= limit:
			return _error("Level %d: truncated warps or dimensions" % (index + 1))
		var warps := PackedInt32Array()
		for i in range(warp_count * 2):
			warps.append(_u24(bytes, cursor))
			cursor += 3
		var width := int(bytes[cursor])
		var height := int(bytes[cursor + 1])
		cursor += 2
		if width < 20 or height < 8:
			return _error("Level %d: dimensions must be 20..255 by 8..255" % (index + 1))
		var tile_count := width * height
		var tiles := PackedByteArray()
		tiles.resize(tile_count)
		var written := 0
		var terminated := false
		while cursor < limit:
			var control := int(bytes[cursor])
			cursor += 1
			if control == 255:
				terminated = true
				break
			if control == 0:
				return _error("Level %d: zero length RLE run" % (index + 1))
			var run := control if control <= 128 else control - 128
			var input_size := 1 if control <= 128 else run
			if cursor + input_size > limit or written + run > tile_count:
				return _error("Level %d: RLE exceeds input or map bounds" % (index + 1))
			for i in range(run):
				tiles[written + i] = bytes[cursor] if control <= 128 else bytes[cursor + i]
			written += run
			cursor += input_size
		if not terminated or written != tile_count or cursor != limit:
			return _error("Level %d: RLE must end exactly at the map and level boundary" % (index + 1))
		var level := {"width": width, "height": height, "tiles": tiles, "warps": warps, "scroll": scroll, "color": color, "index": index, "count": count}
		var problem := validate_level(level)
		if not problem.is_empty():
			return _error("Level %d: %s" % [index + 1, problem])
		levels.append(level)
	var var_end := 0x3C
	while var_end < 0x44 and bytes[var_end] != 0:
		var_end += 1
	var var_name := _single_byte_text(bytes, 0x3C, var_end)
	if var_name.is_empty() or not _valid_text(var_name, 8):
		return _error("Invalid TI variable name")
	return {"ok": true, "error": "", "name": name_text.value, "author": author_text.value, "levels": levels, "version": version, "password_hash": password_hash, "var_name": var_name}

static func validate_level(level: Dictionary) -> String:
	for key in ["width", "height"]:
		if typeof(level.get(key)) != TYPE_INT:
			return "Missing integer " + key
	var width: int = level.width
	var height: int = level.height
	if width < 20 or width > 255 or height < 8 or height > 255:
		return "Dimensions must be 20..255 by 8..255"
	if typeof(level.get("tiles")) != TYPE_PACKED_BYTE_ARRAY or level.tiles.size() != width * height:
		return "Tile byte count must equal width times height"
	if typeof(level.get("warps", PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return "Warps must be a PackedInt32Array"
	var warps: PackedInt32Array = level.get("warps", PackedInt32Array())
	if warps.size() % 2 != 0 or warps.size() > 508:
		# 255 is the optional scroll escape, so 254 pairs is the wire maximum.
		return "Warps must contain up to 254 complete entry/exit pairs"
	for i in range(warps.size()):
		var value := int(warps[i])
		var flags := value & WARP_FLAGS
		var position := value & WARP_INDEX
		if value < 0 or value > 0xFFFFFF or flags not in VALID_FLAGS:
			return "Warp flags must specify one direction or one door marker"
		if position >= width * height:
			return "Warp tile is outside the map"
		if flags in [0x400000, 0x200000] and position < width:
			return "Horizontal warp needs a row above its encoded tile"
		if flags == 0x080000 and position + width >= width * height:
			return "Door exit needs a row below its encoded tile"
		if (i % 2 == 0 and flags == 0x080000) or (i % 2 == 1 and flags == 0x100000):
			return "Door enter/exit flags are on the wrong end of a warp"
	if typeof(level.get("scroll", 0)) != TYPE_INT or int(level.get("scroll", 0)) not in range(5):
		return "Scroll direction must be 0..4"
	if typeof(level.get("color", 0xD77E)) != TYPE_INT or int(level.get("color", 0xD77E)) < 0 or int(level.get("color", 0xD77E)) > 65535:
		return "Background color must be a 16 bit GraphX color"
	var spawn_count := 0
	var counts := [0, 0, 0, 0, 0, 0]
	for tile in level.tiles:
		if tile == 240:
			spawn_count += 1
		elif tile == 241 or tile == 242 or (tile >= 244 and tile <= 249):
			counts[0] += 1
		elif tile == 243 or tile in [0x61, 0x53, 0x46]:
			counts[1] += 1
		elif tile == 250:
			counts[2] += 1
		elif tile == 251:
			counts[3] += 1
		elif tile == 252 or tile == 253:
			counts[4] += 1
		elif tile == 254:
			counts[5] += 1
		elif tile == 255:
			return "Tile 255 is reserved; use empty tile 27 to erase"
	if spawn_count != 1:
		return "Exactly one player spawn marker (tile 240) is required"
	if counts[0] > 252:
		return "Too many initial simple movers (maximum 252)"
	for i in range(1, counts.size()):
		if counts[i] > 64:
			return "Too many initial enemies in one native pool (maximum 64)"
	return ""

static func _valid_text(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_STRING or value.length() > maximum:
		return false
	for i in range(value.length()):
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127 or value.unicode_at(i) > 255:
			return false
	return true

static func validate_pack(pack: Dictionary) -> String:
	if not _valid_text(pack.get("name", ""), MAX_NAME):
		return "Pack name must be printable single-byte text, up to 26 bytes"
	if not _valid_text(pack.get("author", ""), MAX_AUTHOR):
		return "Author must be printable single-byte text, up to 21 bytes"
	if typeof(pack.get("levels")) != TYPE_ARRAY or pack.levels.is_empty() or pack.levels.size() > 255:
		return "A pack must contain 1..255 levels"
	if typeof(pack.get("version", 0xCE)) != TYPE_INT or int(pack.get("version", 0xCE)) not in [0xCD, 0xCE]:
		return "Unknown pack version"
	if typeof(pack.get("password_hash", 0)) != TYPE_INT or int(pack.get("password_hash", 0)) < 0 or int(pack.get("password_hash", 0)) > 0xFFFFFFFF:
		return "Password hash must be an unsigned 32 bit integer"
	var var_name: Variant = pack.get("var_name", "OiramPK")
	if not _valid_text(var_name, 8) or var_name.is_empty():
		return "TI variable name must contain 1..8 printable single-byte text characters"
	for i in range(pack.levels.size()):
		if typeof(pack.levels[i]) != TYPE_DICTIONARY:
			return "Level %d is not a dictionary" % (i + 1)
		var problem := validate_level(pack.levels[i])
		if not problem.is_empty():
			return "Level %d: %s" % [i + 1, problem]
	return ""

static func _compress(tiles: PackedByteArray) -> PackedByteArray:
	var output := PackedByteArray()
	var cursor := 0
	while cursor < tiles.size():
		var repeat := 1
		while repeat < 128 and cursor + repeat < tiles.size() and tiles[cursor + repeat] == tiles[cursor]:
			repeat += 1
		if repeat >= 2:
			output.append(repeat)
			output.append(tiles[cursor])
			cursor += repeat
		else:
			var first := cursor
			cursor += 1
			# 255 is a terminator, limiting literal runs to 126 bytes.
			while cursor - first < 126 and cursor < tiles.size():
				if cursor + 1 < tiles.size() and tiles[cursor] == tiles[cursor + 1]:
					break
				cursor += 1
			output.append(128 + cursor - first)
			output.append_array(tiles.slice(first, cursor))
	output.append(255)
	return output

static func encode(pack: Dictionary) -> PackedByteArray:
	if not validate_pack(pack).is_empty():
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(PAYLOAD_START)
	bytes.fill(0)
	for i in range(HEADER.size()):
		bytes[i] = HEADER[i]
	var var_name: PackedByteArray = _single_byte_buffer(str(pack.get("var_name", "OiramPK")))
	for i in range(var_name.size()):
		bytes[0x3C + i] = var_name[i]
	bytes[0x37] = 13
	bytes[0x3B] = 0x15
	bytes[0x45] = 0x80
	bytes.append(0xAB)
	var version := int(pack.get("version", 0xCE))
	bytes.append(version)
	if version == 0xCE:
		var hash_value := int(pack.get("password_hash", 0))
		for shift in [24, 16, 8, 0]:
			bytes.append((hash_value >> shift) & 255)
	bytes.append_array(_single_byte_buffer(str(pack.get("name", ""))))
	bytes.append(0)
	bytes.append_array(_single_byte_buffer(str(pack.get("author", ""))))
	bytes.append(0)
	bytes.append(pack.levels.size())
	var table := bytes.size()
	bytes.resize(table + (pack.levels.size() - 1) * 2)
	var base := bytes.size()
	for i in range(pack.levels.size()):
		var level: Dictionary = pack.levels[i]
		if bytes.size() - base > 65535:
			return PackedByteArray()
		if i > 0:
			_put16(bytes, table + (i - 1) * 2, bytes.size() - base)
		var color := int(level.get("color", 0xD77E))
		bytes.append(color & 255)
		bytes.append(color >> 8)
		var scroll := int(level.get("scroll", 0))
		if scroll != 0:
			bytes.append(255)
			bytes.append(scroll)
		var warps: PackedInt32Array = level.get("warps", PackedInt32Array())
		bytes.append(warps.size() / 2)
		for value in warps:
			_append24(bytes, value)
		bytes.append(level.width)
		bytes.append(level.height)
		bytes.append_array(_compress(level.tiles))
		# Original editor additionally budgets variable-name overhead below 64 KiB.
		if bytes.size() - PAYLOAD_START + 2 + var_name.size() + 7 > 65535 - 30:
			return PackedByteArray()
	_put16(bytes, 0x35, bytes.size() - 0x37)
	_put16(bytes, 0x39, bytes.size() - 0x48)
	_put16(bytes, 0x46, bytes.size() - 0x48)
	_put16(bytes, 0x48, bytes.size() - PAYLOAD_START)
	var checksum := 0
	for i in range(0x37, bytes.size()):
		checksum = (checksum + bytes[i]) & 65535
	bytes.append(checksum & 255)
	bytes.append(checksum >> 8)
	return bytes
