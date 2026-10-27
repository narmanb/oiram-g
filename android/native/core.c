/* Cooperative replacement for calculator main.c/loadscreen.c platform lifecycle.
 * Original C movement/events/tiles remain authoritative in generated build sources.
 */
#include "core.h"
#include "presentation.h"
#include "graphx.h"
#include "defines.h"
#include "oiram.h"
#include "enemies.h"
#include "tile_handlers.h"
#include "powerups.h"
#include "simple_mover.h"
#include "lower.h"
#include "images.h"
#include "events.h"
#include "loadscreen.h"
map_t level_map;
tiles_struct_t tiles;
gfx_tilemap_t tilemap;
oiram_t oiram;
game_t game;
bool easter_egg1,easter_egg2,easter_egg3,easter_egg4;
unsigned int *warp_info;
unsigned int warp_num;
char *pack_author;
static uint8_t *map_allocation;
static unsigned int warp_storage[508];
static bool configured,special_previous;
static uint32_t rgba[320*240],smooth_rgba[1280*960];
void missing_appvars(void){abort();}
void oiram_native_shutdown(void){
    configured=false;native_presentation_reset();oiram_native_memory_release();
    while(num_simple_enemies)remove_simple_enemy(0);
    while(num_simple_movers)remove_simple_mover(0);
    while(num_chompers)remove_chomper(0);
    while(num_thwomps)remove_thwomp(0);
    while(num_flames)remove_flame(0);
    while(num_boos)remove_boo(0);
    while(num_poofs)remove_poof(0);
    while(num_fireballs)remove_fireball(0);
    while(num_bumped_tiles)remove_bumped_tile(0);
    free(map_allocation);map_allocation=NULL;tilemap.map=NULL;
}
static void rectangle(int x,int y,int w,int h){
    gfx_SetColor(WHITE_INDEX);gfx_Rectangle_NoClip(x,y,w,h);
    gfx_Rectangle_NoClip(x+1,y+1,w-2,h-2);
    gfx_SetColor(DARK_BLUE_INDEX);gfx_FillRectangle_NoClip(x+2,y+2,w-4,h-4);
    gfx_SetColor(BLACK_INDEX);
    gfx_SetPixel(x,y);gfx_SetPixel(x+w-1,y);gfx_SetPixel(x+w-1,y+h-1);gfx_SetPixel(x,y+h-1);
    gfx_SetColor(WHITE_INDEX);
    gfx_SetPixel(x+2,y+2);gfx_SetPixel(x+w-3,y+2);gfx_SetPixel(x+w-3,y+h-3);gfx_SetPixel(x+2,y+h-3);
}
bool oiram_native_configure(const uint8_t *data,int width,int height,int scroll,uint16_t color,
 const uint32_t *warps,int warp_values,int level,int count,int lives,int flags,int coins,int score){
    if(!data||width<20||width>255||height<8||height>255||scroll<0||scroll>4||
        warp_values<0||warp_values>508||(warp_values&1)||(warp_values&&!warps)||
        count<1||count>255||level<0||level>=count||lives<1||lives>99||coins<0||coins>99||score<0)return false;
    int spawn=0;
    for(int i=0;i<width*height;i++)if(data[i]==240)spawn++;
    if(spawn!=1)return false;
    for(int i=0;i<warp_values;i++){
        unsigned loc=warps[i]&0x07ffff,style=warps[i]&0xf80000;
        if(warps[i]>0xffffff||loc>=(unsigned)(width*height)||
            (style!=0&&style!=0x800000&&style!=0x400000&&style!=0x200000&&style!=0x100000&&style!=0x080000))return false;
        if((style==0x400000||style==0x200000)&&loc<(unsigned)width)return false;
        if(style==0x080000&&loc+(unsigned)width>=(unsigned)(width*height))return false;
    }
    /* A row of addressable empty padding permits temporary bump/leaf origins
     * above the map. It does not participate in collision or camera bounds. */
    uint8_t *next=malloc((size_t)width*(height+2));if(!next)return false;
    memset(next,TILE_EMPTY,(size_t)width*(height+2));memcpy(next+width,data,(size_t)width*height);
    oiram_native_shutdown();map_allocation=next;
    memset(&game,0,sizeof game);memset(&oiram,0,sizeof oiram);
    memset(&tiles,0,sizeof tiles);memset(&warp,0,sizeof warp);
    memset(&tilemap,0,sizeof tilemap);memset(&level_map,0,sizeof level_map);
    tilemap.map=next+width;tilemap.width=width;tilemap.height=height;
    tilemap.tile_width=tilemap.tile_height=16;tilemap.draw_width=21;tilemap.draw_height=9;
    tilemap.type_width=tilemap.type_height=4;tilemap.tiles=tileset_tiles;
    level_map.width=width;level_map.height=height;level_map.data=tilemap.map;
    level_map.max_x=width*16;level_map.max_y=height*16;
    level_map.max_x_scroll=width*16-320;level_map.max_y_scroll=height*16-128;level_map.scroll=scroll;
    warp_num=(unsigned)warp_values;warp_info=warp_storage;
    for(int i=0;i<warp_values;i++)warp_storage[i]=warps[i];
    extract_tiles();extract_sprites();
    gfx_palette[255]=gfx_RGBTo1555(0,0,0);gfx_palette[254]=gfx_RGBTo1555(255,255,255);
    gfx_palette[252]=gfx_RGBTo1555(24,120,184);gfx_palette[0]=color;
    if(easter_egg3)for(unsigned i=1;i<256;i++)gfx_palette[i]=~gfx_palette[i];
    if(easter_egg1){oiram_0_small=easter_egg_0;oiram_1_small=easter_egg_1;}
    game.end_count=10;game.seconds=600;game.level=level;game.num_levels=count;game.coins=coins;game.score=score;
    oiram.fly_count=9;oiram.sprite=oiram_right[0];oiram.direction=FACE_RIGHT;
    oiram.flags=flags;oiram.lives=lives;
    set_normal_oiram_sprites();get_enemies();oiram_start_location();
    pressed_left=pressed_right=pressed_up=pressed_down=pressed_alpha=pressed_2nd=false;
    special_previous=false;allow_up_press=true;handling_events=false;something_died=false;
    force_jump=false;on_slope=TEST_NONE;in_quicksand=in_water=on_ice=false;
    for(int i=0;i<4;i++){tiles.animation_count=3;animate();}
    gfx_SetClipRegion(0,0,320,240);gfx_FillScreen(BLACK_INDEX);
    gfx_TransparentSprite(oiram_logo,116,55);gfx_TransparentSprite(oiram_start,165,55);
    gfx_SetTextFGColor(WHITE_INDEX);gfx_SetTextBGColor(DARK_BLUE_INDEX);gfx_SetTextTransparentColor(BLACK_INDEX);
    rectangle(4,133,312,48);rectangle(4,194,80,33);
    gfx_TransparentSprite(coin_sprite,10,140);gfx_TransparentSprite(oiram_lives,10,164);gfx_TransparentSprite(timer,270,143);
    gfx_SetColor(WHITE_INDEX);gfx_Rectangle_NoClip(118,145,81,4);
    draw_coins();draw_time();draw_score();draw_lives();draw_level();
    gfx_SetClipRegion(0,0,320,128);gfx_Tilemap(&tilemap,oiram.scrollx,oiram.scrolly);
    gfx_TransparentSprite(oiram.sprite,oiram.x-oiram.scrollx,oiram.y-oiram.scrolly);
    configured=true;return true;
}
void oiram_native_step(uint32_t mask){
    if(!configured||game.exit)return;
    pressed_left=mask&1;pressed_right=mask&2;pressed_down=mask&8;pressed_2nd=mask&32;
    bool jump=mask&(4|16),special=mask&64;
    if(allow_up_press)pressed_up=jump;
    else if(!jump){allow_up_press=true;if(oiram.vy< -5)oiram.vy=-5;}
    pressed_alpha=special&&!special_previous;special_previous=special;
    native_presentation_begin();
    oiram_native_memory_begin();
    bool was_entering=warp.enter;
    move_oiram();
    if(was_entering&&!warp.enter){native_presentation_reset();native_presentation_begin();}
    gfx_Tilemap(&tilemap,oiram.scrollx,oiram.scrolly);
    handle_pending_events();
    native_presentation_end();
    if(!easter_egg2)animate();
    game.score&=0xffffff;
    oiram_native_memory_end();
}
void oiram_native_clock(unsigned seconds){
    if(!configured||game.exit)return;
    /* Same original handler_clock semantics, including death one tick after 0. */
    if(seconds>601)seconds=601;
    for(unsigned i=0;i<seconds;i++){
        if(!game.seconds)oiram.failed=true;else game.seconds--;
        if(game.blue_item_count&&!--game.blue_item_count)show_blue_items(false);
    }
    draw_time();
}
static const uint8_t *convert_pixels(const uint8_t *indexed,uint32_t *output,unsigned count){
    uint32_t lookup[256];
    for(unsigned i=0;i<256;i++){
        uint16_t c=gfx_palette[i];unsigned r=(c>>10)&31,g=((c>>4)&62)|((c>>15)&1),b=c&31;
        uint8_t pixel[4]={(uint8_t)((r*255+15)/31),(uint8_t)((g*255+31)/63),(uint8_t)((b*255+15)/31),255};
        memcpy(&lookup[i],pixel,4);
    }
    for(unsigned i=0;i<count;i++)output[i]=lookup[indexed[i]];
    return (const uint8_t*)output;
}
const uint8_t *oiram_native_frame(void){return convert_pixels(native_indexed_frame,rgba,320*240);}
const uint8_t *oiram_native_frame_interpolated(double alpha){return convert_pixels(native_presentation_frame(alpha),rgba,320*240);}
const uint8_t *oiram_native_frame_smooth(double alpha){return oiram_native_frame_scaled(alpha,2);}
const uint8_t *oiram_native_frame_scaled(double alpha,unsigned scale){
    scale=scale==4?4:2;
    return convert_pixels(native_presentation_frame_scaled(alpha,scale),smooth_rgba,320*240*scale*scale);
}
void oiram_native_reset_interpolation(void){native_presentation_reset();}
oiram_native_state_t oiram_native_state(void){
    return (oiram_native_state_t){oiram.x,oiram.y,oiram.vy,oiram.vx,oiram.momentum,oiram.flags,oiram.lives,
        game.coins,game.score,game.seconds,game.exit,game.enter_end,oiram.failed,game.level};
}
void oiram_native_set_easter_egg(int code){
    easter_egg1=code==1337;easter_egg2=code==1202;easter_egg3=code==505;easter_egg4=code==101;
}
