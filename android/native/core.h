#ifndef OIRAM_NATIVE_CORE_H
#define OIRAM_NATIVE_CORE_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    int32_t x,y,vy,vx,momentum,flags,lives,coins,score,seconds;
    int32_t exit,completed,failed,level;
} oiram_native_state_t;
bool oiram_native_configure(const uint8_t *tiles,int width,int height,int scroll,uint16_t color,
    const uint32_t *warps,int warp_values,int level,int count,int lives,int flags,int coins,int score);
void oiram_native_step(uint32_t mask);
void oiram_native_clock(unsigned seconds);
const uint8_t *oiram_native_frame(void);
const uint8_t *oiram_native_frame_interpolated(double alpha);
/* Render-only 640x480 RGBA; original gameplay coordinates are unchanged. */
const uint8_t *oiram_native_frame_smooth(double alpha);
/* Render-only RGBA at 320*scale by 240*scale; scale is normalized to 2 or 4. */
const uint8_t *oiram_native_frame_scaled(double alpha,unsigned scale);
void oiram_native_reset_interpolation(void);
oiram_native_state_t oiram_native_state(void);
void oiram_native_shutdown(void);
void oiram_native_set_easter_egg(int code);
#ifdef __cplusplus
}
#endif
#endif
