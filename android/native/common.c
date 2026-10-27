/* Portable, instruction-equivalent translations of src/common.s.
 * BSD-3-Clause, original algorithms Matt Waltz. No eZ80 execution/emulation.
 */
#include "platform.h"
#include "defines.h"
#include "oiram.h"
#include "images.h"
#include "tile_handlers.h"
extern uint8_t testing_side;
static uint8_t test(int x,int y,uint8_t side) {
    testing_side=side;
    if(x<0||x>=level_map.max_x)return 0;
    if(y<0||y>=level_map.max_y)return 1;
    test_x=x;test_y=y;
    uint8_t *tile=tilemap.map+(y>>4)*tilemap.width+(x>>4);
    return tile_handler[*tile](tile);
}
uint8_t moveable_tile(int x,int y){return test(x,y,TEST_NONE);}
uint8_t moveable_tile_left_bottom(int x,int y){return test(x,y,TEST_LEFT);}
uint8_t moveable_tile_right_bottom(int x,int y){return test(x,y,TEST_RIGHT);}
uint8_t solid_tile_handler(uint8_t *tile){(void)tile;return 0;}
uint8_t empty_tile_handler(uint8_t *tile){(void)tile;return 1;}
void tile_to_abs_xy_pos(uint8_t *tile,unsigned int *x,unsigned int *y) {
    /* NULL is the original temporary-object sentinel; callers replace x/y.
     * Avoid the original undefined subtraction from a null pointer. */
    if(!tile||!tilemap.map||!tilemap.width){*x=*y=0;return;}
    ptrdiff_t offset=tile-tilemap.map;
    ptrdiff_t row=offset/(ptrdiff_t)tilemap.width;
    ptrdiff_t column=offset%(ptrdiff_t)tilemap.width;
    if(column<0){column+=tilemap.width;row--;}
    *y=(unsigned)(row*16);
    *x=(unsigned)(column*16);
}
#define TOGGLE(var,a,b) var=(var==a)?b:a
void animate(void) {
    if(++tiles.animation_count!=4)return;
    TOGGLE(goomba_sprite,goomba_0,goomba_1);
    TOGGLE(koopa_red_left_sprite,koopa_red_left_0,koopa_red_left_1);
    TOGGLE(koopa_red_right_sprite,koopa_red_right_0,koopa_red_right_1);
    TOGGLE(koopa_green_left_sprite,koopa_green_left_0,koopa_green_left_1);
    TOGGLE(koopa_green_right_sprite,koopa_green_right_0,koopa_green_right_1);
    TOGGLE(koopa_bones_left_sprite,koopa_bones_left_0,koopa_bones_left_1);
    TOGGLE(koopa_bones_right_sprite,koopa_bones_right_0,koopa_bones_right_1);
    TOGGLE(fish_right_sprite,fish_right_0,fish_right_1);
    TOGGLE(fish_left_sprite,fish_left_0,fish_left_1);
    TOGGLE(chomper_sprite,chomper_0,chomper_1);
    TOGGLE(fireball_sprite,fire_0,fire_1);
    TOGGLE(flame_sprite_up,flame_fire_up_0,flame_fire_up_1);
    TOGGLE(flame_sprite_down,flame_fire_down_0,flame_fire_down_1);
    TOGGLE(wing_right_sprite,wing_right_0,wing_right_1);
    TOGGLE(wing_left_sprite,wing_left_0,wing_left_1);
    TOGGLE(spike_left_sprite,spike_left_0,spike_left_1);
    TOGGLE(spike_right_sprite,spike_right_0,spike_right_1);
    oiram.index^=1;
    ptrdiff_t d4=258;
    if(tiles.animation_4_count==3){tiles.animation_4_count=0;d4=-774;}
    else tiles.animation_4_count++;
    static const uint8_t four[]={0,4,126,118,122,132,150,146,224,233,234};
    for(unsigned i=0;i<sizeof four;i++){
        uint8_t n=four[i];
        /* Generated PNG arrays are independently allocated: advance via base
         * tiles instead of relying on contiguous AppVar pointer arithmetic. */
        (void)d4;
        extern gfx_sprite_t *native_tile_frames[252];
        tileset_tiles[n]=native_tile_frames[(n==234?247:n)+tiles.animation_4_count];
    }
    for(unsigned n=225;n<=230;n++)tileset_tiles[n]=tileset_tiles[0];
    if(tiles.animation_3_count==2)tiles.animation_3_count=0;else tiles.animation_3_count++;
    static const uint8_t three[]={8,94,108};
    extern gfx_sprite_t *native_tile_frames[252];
    for(unsigned i=0;i<sizeof three;i++)tileset_tiles[three[i]]=native_tile_frames[three[i]+tiles.animation_3_count];
    tiles.animation_count=0;
}
