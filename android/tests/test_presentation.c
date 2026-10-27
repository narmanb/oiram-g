#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "core.h"
#include "graphx.h"
#include "presentation.h"
#include "oiram.h"
static uint8_t tile_a[258]={16,16},tile_b[258]={16,16};
static uint8_t image[11]={3,3,7,7,7,7,7,7,7,7,7};
static uint8_t map[40*12],saved[320*240],expected[320*240];
static gfx_sprite_t *tile_frames[256];
static gfx_tilemap_t tm;
static int actor;
static void begin(unsigned scroll,int x){
    gfx_SetClipRegion(0,0,320,128);
    native_presentation_begin();
    gfx_Tilemap(&tm,scroll,0);
    native_presentation_entity(&actor,0);
    if(x>=0)gfx_TransparentSprite((gfx_sprite_t*)image,x,20);
    native_presentation_end();
}
int main(void){
    memset(tile_a+2,1,256);memset(tile_b+2,2,256);
    for(int i=0;i<256;i++)tile_frames[i]=(gfx_sprite_t*)tile_a;
    tile_frames[1]=(gfx_sprite_t*)tile_b;
    tm=(gfx_tilemap_t){.map=map,.tiles=tile_frames,.width=40,.height=12,.tile_width=16,.tile_height=16,.draw_width=21,.draw_height=9};
    gfx_FillScreen(255);native_presentation_reset();begin(0,10);begin(0,14);
    memcpy(saved,native_indexed_frame,sizeof saved);
    const uint8_t *p=native_presentation_frame(0.5);
    assert(p[20*320+12]==7&&p[20*320+14]==7&&p[20*320+10]==1&&p[20*320+15]==1);
    assert(!memcmp(saved,native_indexed_frame,sizeof saved));
    assert(!memcmp(native_presentation_frame(1.0),saved,sizeof saved));
    assert(native_presentation_frame(0.0)[20*320+10]==7);
    assert(!memcmp(native_presentation_frame(NAN),saved,sizeof saved));
    assert(!memcmp(native_presentation_frame(INFINITY),saved,sizeof saved));
    /* Replay snapshots the map and animation pointers before gameplay mutates them. */
    map[0]=1;tile_frames[1]=(gfx_sprite_t*)tile_a;
    assert(!memcmp(native_presentation_frame(1),saved,sizeof saved));
    map[0]=0;tile_frames[1]=(gfx_sprite_t*)tile_b;
    native_presentation_reset();begin(0,-1);begin(4,-1);
    for(int y=0;y<12;y++)for(int x=0;x<40;x++)map[y*40+x]=x&1;
    native_presentation_reset();begin(0,-1);begin(4,-1);
    memcpy(saved,native_indexed_frame,sizeof saved);
    gfx_Tilemap(&tm,2,0);memcpy(expected,native_indexed_frame,sizeof expected);
    memcpy(native_indexed_frame,saved,sizeof saved);
    assert(!memcmp(native_presentation_frame(0.5),expected,sizeof expected));
    native_presentation_reset();begin(0,10);begin(0,200);
    assert(native_presentation_frame(0.5)[20*320+200]==7); /* no interpolation through teleports */
    /* Allocation reuse is never a match for a destroyed entity. */
    void *first=oiram_native_calloc(1,8);uint64_t first_id=oiram_native_object_id(first);
    native_presentation_reset();native_presentation_begin();gfx_Tilemap(&tm,0,0);
    native_presentation_entity(first,0);gfx_TransparentSprite((gfx_sprite_t*)image,10,20);native_presentation_end();
    oiram_native_retire(first);void *second=oiram_native_calloc(1,8);
    assert(first_id!=oiram_native_object_id(second));
    native_presentation_begin();gfx_Tilemap(&tm,0,0);native_presentation_entity(second,0);
    gfx_TransparentSprite((gfx_sprite_t*)image,14,20);native_presentation_end();
    assert(native_presentation_frame(0.5)[20*320+14]==7&&native_presentation_frame(0.5)[20*320+12]==1);
    oiram_native_retire(second);
    /* Bounded command overflow falls back to the authentic current frame. */
    native_presentation_begin();gfx_Tilemap(&tm,0,0);
    for(int i=0;i<5000;i++)gfx_TransparentSprite((gfx_sprite_t*)image,14,20);
    native_presentation_end();assert(!memcmp(native_presentation_frame(0.5),native_indexed_frame,sizeof saved));
    /* Rendering between steps must not mutate original gameplay or its framebuffer. */
    memset(map,27,sizeof map);for(int x=0;x<40;x++)map[10*40+x]=52;map[9*40+2]=240;
    assert(oiram_native_configure(map,40,12,0,0,NULL,0,0,1,15,0,0,0));
    for(int tick=0;tick<100;tick++){
        oiram_native_step(2|32);
        oiram_native_state_t before=oiram_native_state();
        const uint8_t *frame=oiram_native_frame();
        static uint8_t rgba[320*240*4];memcpy(rgba,frame,sizeof rgba);
        oiram_native_frame_interpolated(0.25);oiram_native_frame_interpolated(0.5);oiram_native_frame_interpolated(0.75);
        oiram_native_state_t after=oiram_native_state();assert(!memcmp(&before,&after,sizeof before));
        assert(!memcmp(rgba,oiram_native_frame(),sizeof rgba));
        assert(!memcmp(rgba,oiram_native_frame_interpolated(1),sizeof rgba));
    }
    /* A short pipe warp is still a discontinuity; never glide between its endpoints. */
    memset(map,27,sizeof map);for(int x=0;x<40;x++)map[10*40+x]=52;map[9*40+2]=240;
    map[10*40+2]=14;map[10*40+4]=14;
    uint32_t warps[2]={10*40+2,0x800000u|(10*40+4)};
    assert(oiram_native_configure(map,40,12,0,0,warps,2,0,1,15,0,0,0));
    oiram.x=40;bool teleported=false;
    for(int i=0;i<40;i++){
        bool entering=warp.enter;oiram_native_step(8);
        if(entering&&!warp.enter){
            static uint8_t latest[320*240*4];memcpy(latest,oiram_native_frame(),sizeof latest);
            assert(!memcmp(latest,oiram_native_frame_interpolated(0.5),sizeof latest));teleported=true;break;
        }
    }
    assert(teleported);
    /* Door endpoints remain visible, even when their separation is below 64 pixels. */
    memset(map,27,sizeof map);for(int x=0;x<40;x++)map[10*40+x]=52;map[9*40+2]=240;
    map[8*40+2]=232;map[8*40+4]=232;
    warps[0]=0x100000u|(8*40+2);warps[1]=0x080000u|(8*40+4);
    assert(oiram_native_configure(map,40,12,0,0,warps,2,0,1,15,0,0,0));
    oiram.x=40;teleported=false;
    for(int i=0;i<12;i++){
        bool entering=warp.enter;oiram_native_step(16);
        if(entering&&!warp.enter){
            static uint8_t latest[320*240*4];memcpy(latest,oiram_native_frame(),sizeof latest);
            assert(!memcmp(latest,oiram_native_frame_interpolated(0.5),sizeof latest));teleported=true;break;
        }
    }
    assert(teleported);
    oiram_native_reset_interpolation();
    oiram_native_shutdown();puts("Presentation: midpoint motion, camera, snapshots, discontinuities and unchanged gameplay passed");
    return 0;
}
