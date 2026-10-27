# Oiram pack format and Android codec

`android/scripts/oiram_pack.gd` implements the original formats in
`src/loadscreen.c` and the desktop editor's `src/level.c`. The original files
remain unchanged. Import validates the complete file before giving a decoded
map to the native engine.

## API

```gdscript
var result: Dictionary = OiramPack.load_bytes(bytes)
if result.ok:
    var level: Dictionary = result.levels[0]
    # Configure the native engine with this dictionary.
var problem: String = OiramPack.validate_pack(result)
var exported: PackedByteArray = OiramPack.encode(result)
```

`load_bytes` always returns `ok`, `error`, `name`, `author`, and `levels`.
Failures return `ok=false`, a readable error, and an empty level array; no
partially decoded levels escape. Successful results additionally include
`version`, `password_hash`, and `var_name`. `encode` returns an empty byte array
for an invalid model or a pack too large for the original editor's file-size
budget. `validate_pack` and `validate_level` return an empty string on success.
The encoder never changes the supplied model. New packs default to CE, an
unlocked hash of zero, and TI variable name `OiramPK`. Imported CD packs retain
CD when re-encoded; CE password hashes are preserved as unsigned 32-bit integers.

Each decoded level contains:

| Key | Type | Meaning |
| --- | --- | --- |
| `width`, `height` | `int` | Map dimensions, 20..255 and 8..255 |
| `tiles` | `PackedByteArray` | Exactly width × height row-major tile IDs |
| `warps` | `PackedInt32Array` | Alternating raw 24-bit entry/exit values |
| `scroll` | `int` | 0 none, 1 right, 2 left, 3 down, 4 up |
| `color` | `int` | Raw 16-bit GraphX background color |
| `index`, `count` | `int` | Zero-based level index and pack level count |

## TI container

The codec supports one TI-83F AppVar per file, with the 13-byte variable header
used by the original editor. Integers below are little endian unless stated.

| Offset | Length | Field |
| --- | --- | --- |
| `0x00` | 11 | `**TI83F*`, `1A 0A 00` |
| `0x0B` | 42 | TI comment, preserved by original files but omitted in new exports |
| `0x35` | 2 | Data-section size, bytes from `0x37` through payload end |
| `0x37` | 2 | Variable-header size: 13 |
| `0x39` | 2 | Variable data size, payload size + 2 |
| `0x3B` | 1 | Variable type: `0x15`, AppVar |
| `0x3C` | 8 | Null-padded TI variable name |
| `0x44` | 1 | Variable version |
| `0x45` | 1 | Archive flag (`0x80` on export) |
| `0x46` | 2 | Duplicate variable data size |
| `0x48` | 2 | AppVar payload size |
| `0x4A` | n | Oiram payload |
| end − 2 | 2 | Sum of all bytes from `0x37` through payload end, modulo 65536 |

All three sizes, the duplicated size, signature, type, checksum, and exact file
length are checked. Group files and alternate TI variable-header layouts are
not accepted. Export checks the original editor's additional variable-name
budget below 64 KiB.

## Payload

The payload begins `AB CD` (legacy) or `AB CE` (password-aware). CE adds a
four-byte **big-endian** password hash. A null-terminated display name (up to
26 printable single-byte characters), a null-terminated author (up to 21 printable single-byte
characters), and a one-byte level count (1..255) follow. The limits match the actual
editor writer loops, which differ by one from its format comment. The Android
codec preserves these bytes using Latin-1 conversion (including accented
author names), rejects control bytes and characters above U+00FF, and does not
attempt a separate TI glyph-to-Unicode translation.

The level-offset table has **count − 1** 16-bit entries. The first level follows
the table immediately. Entry `i` gives the start of level `i+1` relative to the
first level, not relative to the table. Offsets must strictly increase and stay
inside the payload. Each stream must end exactly at the next level boundary.

Each level consists of:

1. A 16-bit GraphX background color.
2. Optional bytes `FF scroll`, where scroll is 0..4.
3. A one-byte warp-pair count, followed by six bytes per pair.
4. One-byte width and height.
5. RLE map data, including its `FF` terminator.

The scroll escape reserves warp count 255, so the maximum usable count is 254.
A level without the optional escape has scroll 0.

## RLE

Controls 1..128 repeat the following byte that many times. Controls 129..254
copy the following control − 128 literal bytes. Control 255 ends the stream.
Control zero, input truncation, output overrun, early or missing termination,
and trailing compressed bytes are rejected. Output is allocated once to the
validated map dimensions; compressed controls cannot grow it. The encoder uses
runs of at most 128 repeats or 126 literals. This avoids the original C
encoder's potential collision between long literal controls and the terminator.
A byte with value 255 can be literal data in the wire format, but is rejected
as a map tile because it is outside the tile/enemy palette.

## Warps and native limits

Warp integers are three little-endian bytes. The low 19 bits (`0x07FFFF`) are
the tile index. A single direction or door flag may occupy the remaining bits:

| Flag | Meaning |
| --- | --- |
| `0` | Down pipe |
| `0x800000` | Up pipe |
| `0x400000` | Left pipe |
| `0x200000` | Right pipe |
| `0x100000` | Door entry |
| `0x080000` | Door exit |

Entries/exits must reference existing tiles and use a single valid flag. Door
flags must occur at their correct end of a pair. Horizontal pipe indices are
stored **one row below** the editor's visible marker and require a row above.
Door exits require a row below, since the native engine places a small player
there. Raw encoded indices are preserved without translation.

Every map must contain exactly one spawn marker, tile 240. Tile 27 is empty.
IDs 241..254 identify the original enemies. Initial map counts are bounded by
the source's arrays: 252 simple movers; 64 each for simple enemies (including
fish and cannon/bullet generators), thwomps, flames, combined chomper variants,
and boos. Dynamic spawns still need the native engine's pool safeguards.

The desktop editor UI permits 20..253 × 10..253. The on-disk fields are bytes;
the native viewport is 20 × 8 tiles, so Android safely accepts 20..255 × 8..255.
Smaller maps are rejected: the original unsigned camera-scroll arithmetic would
underflow. Height 8 and dimensions 254/255 round-trip successfully in the codec;
this does not extend the desktop editor's resize UI.

## Verification

Run with Godot 4.6.3:

```sh
godot --headless --path android -s tests/test_packs.gd
```

The suite checks the complete 12-level bundled CD pack, a CE conversion,
all 10,682 truncated prefixes, every single-byte corruption with a repaired
checksum, malformed headers, RLE limits, literal boundaries, dimensions,
spawn uniqueness, warp flags/indices, and the largest compressible map.
The exhaustive mutation pass takes several minutes in headless GDScript.

Cross-language verification was also performed by compiling the actual original
`/workspace/oiram-editor/src/level.c` with a small C harness. Godot encoded all
12 default levels as CE, the original editor's `loadFilePack` loaded them and
`saveFilePack` saved them, and Godot loaded that output. All 12 decoded level
dictionaries, every tile, warp, scroll and color, and the CE hash matched.
This tests the actual desktop writer and reader rather than a second port of
the format. No Qt or calculator runtime was needed for the harness.

For a reproducible cross-language check, clone the original editor at the tested
revision and pass its source directory to the same committed test script. The
script embeds the minimal C harness, compiles the unmodified `src/level.c`, and
checks the resulting CE file through the Godot decoder:

```sh
git clone https://github.com/mateoconlechuga/oiram-editor.git /tmp/oiram-editor
git -C /tmp/oiram-editor checkout a11353c39d1e958aa2bdfd31760a1ce98c52720b
godot --headless --path android -s tests/test_packs.gd -- --quick --editor-source=/tmp/oiram-editor
```

`--quick` retains all truncated-prefix tests and the structured malformed-input
cases, and samples every 31st mutation offset. Omit it for the full mutation
pass. The test suite does not require the desktop editor clone unless
`--editor-source=` is supplied.

## Built-in editor

`android/editor/oiram_editor.gd` provides the bounded editor. Terrain and object
buttons use the original desktop editor atlas and its exact tile-coordinate
catalog; all 15 player/enemy marker buttons use its original sprites. Select a
brush and drag to paint. Erase uses tile 27. Spawn moves the unique player
marker; painting over the current spawn is blocked until it is moved. Pan uses
a separate touch tool (or middle/right mouse drag); zoom buttons, wheel, and Fit
control the map view. Each painting drag is one Undo/Redo step. History retains
16 pack snapshots.

Width/height resize preserves the overlapping map area, recreates a cropped
spawn, remaps existing warp indices by their original X/Y coordinates, and drops
cropped warp pairs. Undo restores the previous map. Existing warps are displayed
as paired colored circles. Creating new warp pairs is outside the current editor
tools. Level addition/removal, display name, author, background color, and all
five scroll settings are supported. The desktop editor's password lock is not
enforced by this built-in editor; imported CE hashes are preserved on export.

Save writes `user://editor/current.8xv` by temporary-file rename and retains the
previous save as `.bak`. Load saved falls back to the backup if needed. Import
and Export use Godot's native file dialog when supported. Import opens a file
and checks its length against the TI container limit before allocating a byte
array, so oversized files preserve the current unsaved model. Export preserves
Android `content://` document URIs exactly; Android document-picker
behavior still needs device verification. Test emits a validated standalone map
through `test_level(level)` for the shell's native gameplay view. Back saves
pending changes first. `set_pack(pack, index=0)` takes an independent deep copy,
so editing never modifies the imported library entry.

Run the editor's functional and touch-routing checks with:

```sh
godot --headless --path android -s editor/test_editor.gd
```

These verify painting/erasing, spawn uniqueness, Undo/Redo, resize and warp
remapping, level addition/removal, save/load, the native-test signal, source-pack
independence, landscape layout bounds, and actual viewport-routed touch
press/drag/release and touch panning. Headless checks do not establish visual
quality or on-device Android document-picker behavior.
