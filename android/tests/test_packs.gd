extends SceneTree

const Pack = preload("res://scripts/oiram_pack.gd")
var checks := 0
var failures := 0
const EDITOR_HARNESS := """
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "level.h"
int main(int argc, char **argv) {
    char *description = NULL, *var = NULL, *author = NULL;
    if (argc != 3) return 2;
    initPack();
    if (!loadFilePack(argv[1], &description, &var, &author)) return 3;
    for (unsigned i = 0; i < pack.count; ++i) {
        level_t *level = &pack.level[i];
        unsigned spawns = 0;
        for (unsigned j = 0; j < (unsigned)level->width * level->height; ++j)
            spawns += level->data[j] == 240;
        if (spawns != 1) return 4;
    }
    if (!saveFilePack(argv[2], description, var, author, 0x12345678)) return 5;
    printf("Original editor C round-tripped %u levels\\n", pack.count);
    free(description); free(var); free(author); deletePack();
    return 0;
}
"""

func editor_interop(pack: Dictionary, source: String) -> void:
	var directory := OS.get_cache_dir().path_join("oiram-codec-interop")
	DirAccess.make_dir_recursive_absolute(directory)
	var harness_path := directory.path_join("pack_harness.c")
	var harness := FileAccess.open(harness_path, FileAccess.WRITE)
	harness.store_string(EDITOR_HARNESS)
	harness.close()
	var executable := directory.path_join("pack_harness")
	var output: Array = []
	var result := OS.execute("cc", PackedStringArray(["-O2", "-Wall", "-I" + source.path_join("src"), harness_path, source.path_join("src/level.c"), "-lm", "-o", executable]), output, true)
	check(result == 0, "Compile actual original editor C: " + str(output))
	if result != 0:
		return
	var ce := pack.duplicate(true)
	ce.version = 0xCE
	ce.password_hash = 0x12345678
	var input_path := directory.path_join("godot.8xv")
	var output_path := directory.path_join("editor.8xv")
	var file := FileAccess.open(input_path, FileAccess.WRITE)
	file.store_buffer(Pack.encode(ce))
	file.close()
	output.clear()
	result = OS.execute(executable, PackedStringArray([input_path, output_path]), output, true)
	check(result == 0, "Original editor loads and writes Godot CE output: " + str(output))
	if result != 0:
		return
	var loaded: Dictionary = Pack.load_bytes(FileAccess.get_file_as_bytes(output_path))
	check(loaded.ok and loaded.levels == pack.levels and loaded.password_hash == 0x12345678 and loaded.name == pack.name and loaded.author == pack.author, "Actual original editor round trip preserves all levels and metadata")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func fresh_level(width: int = 20, height: int = 8) -> Dictionary:
	var tiles := PackedByteArray()
	tiles.resize(width * height)
	tiles.fill(27)
	tiles[width + 1] = 240
	return {"width": width, "height": height, "tiles": tiles, "warps": PackedInt32Array(), "scroll": 0, "color": 0xD77E, "index": 0, "count": 1}

func wrap_pack(level: Dictionary) -> Dictionary:
	return {"name": "Test Pack", "author": "Tests", "levels": [level]}

func repair_checksum(bytes: PackedByteArray) -> PackedByteArray:
	var sum := 0
	for i in range(0x37, bytes.size() - 2):
		sum = (sum + bytes[i]) & 65535
	bytes[bytes.size() - 2] = sum & 255
	bytes[bytes.size() - 1] = sum >> 8
	return bytes

func expect_bad(bytes: PackedByteArray, label: String) -> void:
	var parsed: Dictionary = Pack.load_bytes(bytes)
	check(not parsed.get("ok", true) and not str(parsed.get("error", "")).is_empty() and parsed.get("levels", [1]).is_empty(), label)

func _initialize() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var original := FileAccess.get_file_as_bytes("res://assets/OiramPK.8xv")
	if original.is_empty():
		original = FileAccess.get_file_as_bytes("res://../extra/OiramPK.8xv")
	var loaded: Dictionary = Pack.load_bytes(original)
	check(loaded.ok, "Original default pack loads: " + str(loaded.error))
	if loaded.ok:
		check(loaded.name == "Default Pack" and loaded.author == "Mateo", "Original metadata")
		check(loaded.levels.size() == 12, "All twelve original levels")
		check(loaded.levels[0].width == 157 and loaded.levels[0].height == 20, "Original first dimensions")
		check(loaded.levels[11].width == 29 and loaded.levels[11].height == 10, "Original last dimensions")
		check(loaded.levels[5].warps.size() == 20, "Original ten warp pairs")
		var again: Dictionary = Pack.load_bytes(Pack.encode(loaded))
		check(again.ok and again.levels == loaded.levels, "Whole default pack round trip")
		var ce: Dictionary = loaded.duplicate(true)
		ce.version = 0xCE
		ce.password_hash = 0x12345678
		var ce_loaded: Dictionary = Pack.load_bytes(Pack.encode(ce))
		check(ce_loaded.ok and ce_loaded.password_hash == 0x12345678 and ce_loaded.levels == loaded.levels, "CE version and big endian password round trip")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--editor-source=") and loaded.ok:
			editor_interop(loaded, argument.trim_prefix("--editor-source="))
	for prefix in range(original.size()):
		expect_bad(original.slice(0, prefix), "Reject original truncation at %d" % prefix)
	var changed := original.duplicate()
	changed[100] ^= 1
	expect_bad(changed, "Reject checksum damage")
	changed = original.duplicate()
	changed.append(0)
	expect_bad(changed, "Reject trailing file data")
	for header_index in [0, 8, 0x35, 0x37, 0x39, 0x3B, 0x46, 0x48, 0x4A, 0x4B]:
		changed = original.duplicate()
		changed[header_index] ^= 1
		expect_bad(repair_checksum(changed), "Reject malformed header %d" % header_index)
	# Keep the TI wrapper valid to exercise deeper metadata/table validation.
	changed = original.duplicate()
	for i in range(76, 103):
		changed[i] = 65
	expect_bad(repair_checksum(changed), "Reject unterminated or overlong pack name")
	changed = original.duplicate()
	for i in range(89, 111):
		changed[i] = 65
	expect_bad(repair_checksum(changed), "Reject unterminated or overlong author")
	changed = original.duplicate()
	changed[95] = 0
	expect_bad(repair_checksum(changed), "Reject zero level count")
	changed = original.duplicate()
	changed[96] = 0
	changed[97] = 0
	expect_bad(repair_checksum(changed), "Reject duplicate level offsets")
	changed = original.duplicate()
	changed[96] = 255
	changed[97] = 255
	expect_bad(repair_checksum(changed), "Reject out-of-file level offsets")
	var level := fresh_level()
	var bytes: PackedByteArray = Pack.encode(wrap_pack(level))
	check(not bytes.is_empty(), "Encode minimal viewport level")
	check(Pack.load_bytes(bytes).ok, "Load minimal viewport level")
	var accented := wrap_pack(fresh_level())
	accented.name = "Création"
	accented.author = "Matéo"
	var accented_loaded: Dictionary = Pack.load_bytes(Pack.encode(accented))
	check(accented_loaded.ok and accented_loaded.name == accented.name and accented_loaded.author == accented.author, "Original single-byte Latin-1 metadata retained")
	accented.author = "😀"
	check(Pack.encode(accented).is_empty(), "Reject metadata outside original single-byte character set")
	level = fresh_level(255, 255)
	for i in range(level.tiles.size()):
		level.tiles[i] = (i % 239)
	level.tiles[256] = 240
	bytes = Pack.encode(wrap_pack(level))
	check(bytes.is_empty(), "Oversize uncompressible pack is rejected")
	level.tiles.fill(27)
	level.tiles[256] = 240
	bytes = Pack.encode(wrap_pack(level))
	check(Pack.load_bytes(bytes).ok, "Largest map with long repeat runs")
	# Literal boundaries and control-byte values are data within literal runs.
	level = fresh_level(127, 8)
	for i in range(level.tiles.size()):
		level.tiles[i] = i % 240
	level.tiles[127] = 240
	bytes = Pack.encode(wrap_pack(level))
	check(Pack.load_bytes(bytes).levels[0].tiles == level.tiles, "Literal runs across 126-byte boundary")
	for dimensions in [Vector2i(19, 8), Vector2i(20, 7), Vector2i(256, 8), Vector2i(20, 256)]:
		level = fresh_level()
		level.width = dimensions.x
		level.height = dimensions.y
		check(Pack.encode(wrap_pack(level)).is_empty(), "Reject unsafe dimensions " + str(dimensions))
	level = fresh_level()
	level.tiles[21] = 27
	check(Pack.encode(wrap_pack(level)).is_empty(), "Missing spawn rejected")
	level.tiles[21] = 240
	level.tiles[22] = 240
	check(Pack.encode(wrap_pack(level)).is_empty(), "Duplicate spawn rejected")
	level = fresh_level()
	for warp in [PackedInt32Array([1]), PackedInt32Array([0xC00028, 40]), PackedInt32Array([160, 40]), PackedInt32Array([0x400001, 40]), PackedInt32Array([0x100001, 0x08009F])]:
		level.warps = warp
		check(Pack.encode(wrap_pack(level)).is_empty(), "Reject malformed warp " + str(warp))
	level.warps = PackedInt32Array([0x400028, 0x80003D, 0x100028, 0x08003D])
	level.scroll = 4
	bytes = Pack.encode(wrap_pack(level))
	var valid_warps: Dictionary = Pack.load_bytes(bytes)
	check(valid_warps.ok and valid_warps.levels[0].warps == level.warps and valid_warps.levels[0].scroll == 4, "Warp flags and all scroll directions retained")
	# Crafted valid container with an invalid stream. Single level starts at 100.
	level = fresh_level()
	bytes = Pack.encode(wrap_pack(level))
	var start := 0x50 + "Test Pack".length() + 1 + "Tests".length() + 1 + 1
	check(bytes[start + 3] == 20 and bytes[start + 4] == 8, "Fixture stream location")
	changed = bytes.duplicate()
	changed[start + 5] = 128
	expect_bad(repair_checksum(changed), "RLE output overrun rejected")
	changed = bytes.duplicate()
	changed[start + 5] = 255
	expect_bad(repair_checksum(changed), "Early RLE terminator rejected")
	changed = bytes.duplicate()
	changed[changed.size() - 3] = 128
	expect_bad(repair_checksum(changed), "Missing RLE terminator rejected")
	changed = bytes.duplicate()
	changed[start + 5] = 0
	expect_bad(repair_checksum(changed), "Zero length RLE control rejected")
	for enemy in [241, 242, 243, 244, 250, 251, 252, 253, 254]:
		level = fresh_level(40, 10)
		var amount := 253 if enemy in [241, 242, 244] else 65
		for i in range(amount):
			level.tiles[80 + i] = enemy
		check(Pack.encode(wrap_pack(level)).is_empty(), "Reject native pool overflow for tile %d" % enemy)
	# Every single-byte mutation with repaired checksum must terminate safely.
	# --quick samples mutation offsets for local editor checks; CI can run all.
	for offset in range(0, original.size() - 2, 31 if quick else 1):
		changed = original.duplicate()
		changed[offset] ^= 0xFF
		var result: Dictionary = Pack.load_bytes(repair_checksum(changed))
		check(result.has("ok") and result.has("error") and result.has("levels"), "Mutation result shape %d" % offset)
	print("Pack codec: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
