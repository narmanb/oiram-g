#ifndef OIRAM_PRESENTATION_H
#define OIRAM_PRESENTATION_H
#include "graphx.h"
void native_presentation_begin(void);
void native_presentation_end(void);
void native_presentation_reset(void);
void native_presentation_entity(const void *object,unsigned channel);
bool native_presentation_capturing(void);
void native_presentation_capture(bool enabled);
void native_presentation_sprite(const gfx_sprite_t *sprite,int x,int y,bool transparent,const int clip[4]);
void native_presentation_tilemap(const gfx_tilemap_t *map,unsigned sx,unsigned sy,const int clip[4]);
const uint8_t *native_presentation_frame(double alpha);
uint8_t *gfx_native_target(uint8_t *target);
void gfx_native_clip(int out[4]);
#endif
