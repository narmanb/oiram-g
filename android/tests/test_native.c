#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "core.h"
#include "oiram.h"
#include "tile_handlers.h"
#include "simple_mover.h"
#include "powerups.h"
#include "enemies.h"
#include "images.h"
#include "lower.h"
static uint8_t map[40*12];
static void reset(void) {
    memset(map,TILE_EMPTY,sizeof map);
    for(int x=0;x<40;x++) map[10*40+x]=52;
    map[9*40+2]=240;
    assert(oiram_native_configure(map,40,12,0,0xD77E,NULL,0,0,12,15,0,0,0));
    assert(oiram.x==32 && oiram.y==144 && oiram.hitbox.height==15);
}
int main(void) {
    reset();
    oiram_native_step(0);assert(oiram.y==144 && oiram.vy==0);
    oiram_native_step(2);assert(oiram.x==34 && oiram.momentum==1 && oiram.vx==2);
    reset();for(int i=0;i<30;i++)oiram_native_step(2|32);
    fprintf(stderr,"sprint: x=%d vx=%d momentum=%d\n",oiram.x,oiram.vx,oiram.momentum);
    assert(oiram.momentum==30 && oiram.vx==5 && oiram.x==144);
    reset();oiram_native_step(16);assert(oiram.vy==-11 && oiram.y==133);
    oiram_native_step(0);assert(oiram.vy==-4 && oiram.y==129);
    reset();for(int i=0;i<12;i++)oiram_native_step(16);
    assert(oiram.y==78 && oiram.vy==0);
    for(int i=0;i<18;i++)oiram_native_step(0);assert(oiram.y==144);
    reset();map[9*40+4]=52;
    assert(oiram_native_configure(map,40,12,0,0,NULL,0,0,12,15,0,0,0));
    for(int i=0;i<20;i++)oiram_native_step(2|32);assert(oiram.x==48);
    reset();move_side=TILE_SOLID;assert(!moveable_tile(-1,0));assert(!moveable_tile(640,0));
    assert(moveable_tile(1,-1));assert(moveable_tile(1,192));
    unsigned int x,y;tile_to_abs_xy_pos(tilemap.map+81,&x,&y);assert(x==16&&y==32);
    tile_to_abs_xy_pos(NULL,&x,&y);assert(x==0&&y==0);
    reset();add_coin(0,0);assert(game.coins==1&&game.score==200);
    for(int i=1;i<100;i++)add_coin(0,0);assert(game.coins==0&&oiram.lives==16);
    reset();eat_mushroom();assert(oiram.flags==1&&oiram.y==132&&oiram.hitbox.height==26);
    eat_fire_flower();assert(oiram.flags==3);
    shrink_oiram();assert(oiram.flags==1);oiram.shrink_count=0;
    shrink_oiram();assert(oiram.flags==0&&oiram.hitbox.height==15);
    oiram.shrink_count=0;shrink_oiram();assert(oiram.failed);
    reset();eat_leaf();assert(oiram.flags==17);oiram_native_step(64);assert(oiram.spin_count==2);
    reset();eat_fire_flower();oiram_native_step(64);assert(oiram.fireballs==1);
    oiram_native_step(64);assert(oiram.fireballs==1);
    oiram_native_step(0);oiram_native_step(64);assert(oiram.fireballs==2);
    reset();eat_star();assert(oiram.invincible==250&&oiram.flags&4);
    assert(!shrink_oiram());
    reset();map[9*40+8]=244;
    assert(oiram_native_configure(map,40,12,0,0,NULL,0,0,12,15,0,0,0));
    assert(num_simple_movers==1&&simple_mover[0]->vx==-1);
    oiram_native_step(0);assert(simple_mover[0]->x==127);
    reset();oiram_native_clock(600);assert(game.seconds==0&&!oiram.failed);
    oiram_native_clock(1);assert(oiram.failed);
    reset();for(int i=0;i<64;i++)add_simple_enemy(NULL,SCORE_TYPE);
    while(num_simple_enemies)remove_simple_enemy(0);
    reset();for(int i=0;i<252;i++)add_simple_mover(NULL);
    while(num_simple_movers)remove_simple_mover(0);
    reset();const uint8_t *pixels=oiram_native_frame();assert(pixels&&pixels[3]==255);
    int varied=0;for(int i=4;i<320*128*4;i+=4)if(memcmp(pixels,pixels+i,3))varied++;
    assert(varied>100);
    assert(!oiram_native_configure(map,1,1,0,0,NULL,0,0,1,15,0,0,0));
    assert(oiram_native_state().lives==15);
    oiram_native_shutdown();puts("Native gameplay regression checks passed");return 0;
}
