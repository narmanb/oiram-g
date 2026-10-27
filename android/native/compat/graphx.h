#ifndef OIRAM_GRAPHX_H
#define OIRAM_GRAPHX_H
#include "platform.h"
typedef struct {uint8_t width,height,data[];} gfx_sprite_t;
typedef gfx_sprite_t gfx_rletsprite_t;
typedef struct {
    uint8_t *map;
    gfx_sprite_t **tiles;
    unsigned type_width,type_height,tile_width,tile_height,draw_width,draw_height,width,height;
    int x_loc,y_loc;
} gfx_tilemap_t;
#define gfx_tile_16_pixel 4
#define gfx_buffer 0
extern uint16_t gfx_palette[256];
extern uint8_t native_indexed_frame[320*240];
uint16_t gfx_RGBTo1555(unsigned r,unsigned g,unsigned b);
void gfx_SetPalette(const void *p,unsigned size,unsigned offset);
void gfx_SetColor(uint8_t c);
void gfx_SetClipRegion(int x0,int y0,int x1,int y1);
void gfx_FillScreen(uint8_t c);
void gfx_FillRectangle(int x,int y,int w,int h);
void gfx_FillRectangle_NoClip(int x,int y,int w,int h);
void gfx_Rectangle_NoClip(int x,int y,int w,int h);
void gfx_SetPixel(int x,int y);
void gfx_Sprite(const gfx_sprite_t *s,int x,int y);
void gfx_TransparentSprite(const gfx_sprite_t *s,int x,int y);
#define gfx_TransparentSprite_NoClip gfx_TransparentSprite
void gfx_RLETSprite(const gfx_rletsprite_t *s,int x,int y);
void gfx_FlipSpriteY(const gfx_sprite_t *a,gfx_sprite_t *b);
bool gfx_CheckRectangleHotspot(int x0,int y0,int w0,int h0,int x1,int y1,int w1,int h1);
void gfx_Tilemap(const gfx_tilemap_t *t,unsigned sx,unsigned sy);
uint8_t *gfx_TilePtr(const gfx_tilemap_t *t,int x,int y);
void gfx_SetTextXY(int x,int y);
void gfx_PrintUInt(unsigned value,unsigned digits);
void gfx_PrintStringXY(const char *s,int x,int y);
void gfx_SetTextFGColor(uint8_t c);
void gfx_SetTextBGColor(uint8_t c);
void gfx_SetTextTransparentColor(uint8_t c);
void gfx_BlitLines(int buffer,unsigned y,unsigned count);
#endif
