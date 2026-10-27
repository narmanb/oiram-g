#!/usr/bin/env python3
"""Lossless palette indexing of original PNGs, then original LCD RGB1555 output.
This replaces AppVar sprite storage only. Sprites are padded for original fixed-size
434-byte player form copies. RLET PNGs are stored unpacked, with identical pixels.
"""
from pathlib import Path
from PIL import Image
import re
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'android/native/generated'
OUT.mkdir(parents=True,exist_ok=True)
files=sorted((ROOT/'src/gfx').glob('*.png'))
colors={(255,0,128)}
for f in files: colors.update(Image.open(f).convert('RGB').getdata())
colors=[(255,0,128)]+sorted(colors-{(255,0,128)})
assert len(colors)<252
palette={c:i for i,c in enumerate(colors)}
def rgb1555(c):
    r,g,b=[int(v*m/255+0.5) for v,m in zip(c,(31,63,31))]
    return ((g&1)<<15)|(r<<10)|((g>>1)<<5)|b
# Keep original declarations and buffers, replace only TI AppVar extraction.
original=(ROOT/'src/images.c').read_text().split('void extract_tiles(void)')[0]
parts=[original]
def arr(name,im):
    w,h=im.size
    data=[w,h]+[palette[p] for p in im.convert('RGB').getdata()]
    data += [0]*max(0,434-len(data))
    parts.append(f'static uint8_t png_{name}[]={{'+','.join(map(str,data))+'};\n')
for f in files:
    if f.stem!='orig_tileset':arr(f.stem,Image.open(f))
tiles=Image.open(ROOT/'src/gfx/orig_tileset.png')
assert tiles.size==(224,288)
for y in range(18):
    for x in range(14):arr(f'tile_{y*14+x}',tiles.crop((x*16,y*16,x*16+16,y*16+16)))
parts.append('static const uint16_t png_palette[256]={'+','.join(str(rgb1555(c)) for c in colors)+'};\n')
# Original tile remapping is retained verbatim after initialization.
fixup=(ROOT/'src/images.c').read_text().split('    // extract common sprite tiles')[1].split('void extract_sprites')[0]
parts.append('gfx_sprite_t *native_tile_frames[252];\n')
parts.append('void extract_tiles(void) {\n gfx_sprite_t **tiles=tileset_tiles;\n gfx_sprite_t *tile_question_box=(gfx_sprite_t*)png_tile_0;\n gfx_SetPalette(png_palette,sizeof png_palette,0);\n')
for i in range(256):parts.append(f'tiles[{i}]=(gfx_sprite_t*)png_tile_{i if i<252 else 0};\n')
parts.append('for(unsigned i=0;i<252;i++)native_tile_frames[i]=tiles[i];\n')
parts.append(' // extract common sprite tiles'+fixup)
parts.append('void extract_sprites(void) {\n')
text=(ROOT/'src/images.c').read_text().split('void extract_sprites(void)')[1]
# Use original chain assignments to maintain every sprite alias exactly.
for lhs in re.findall(r'([^\n;{}]+)= \(gfx_(?:rlet)?sprite_t\*\)spr_ptr;',text):
    lhs=lhs.strip()
    dest=lhs.split('=')[-1].strip()
    mapping={'thwomp_0':'thwomp','cannonball_sprite':'cannonball_0'}
    # sprite chains' final RHS name maps directly to PNG, score and 1up aliases too.
    name=mapping.get(dest,dest)
    assert ROOT.joinpath(f'src/gfx/{name}.png').exists(),(lhs,name)
    cast='gfx_rletsprite_t' if dest.startswith('reswob_') else 'gfx_sprite_t'
    parts.append(f' {lhs}=({cast}*)png_{name};\n')
parts.append('}\n')
(OUT/'images.c').write_text(''.join(parts))
print(f'Generated 252 tiles and {len(files)-1} sprites; {len(colors)} original colors')
