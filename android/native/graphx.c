/* Portable graphx subset. Clipped pixel rendering, original palette and HUD font. */
#include "graphx.h"
#include "presentation.h"
#include "font.h"
#include <stdio.h>
uint16_t gfx_palette[256];
uint8_t native_indexed_frame[320*240];
static uint8_t *draw_target=native_indexed_frame;
uint8_t *gfx_native_target(uint8_t *p){uint8_t *old=draw_target;draw_target=p;return old;}
static uint8_t color,fg=254,bg=252,text_transparent=255;
static int clip_x0,clip_y0,clip_x1=320,clip_y1=240,text_x,text_y;
static uint8_t outside_tile=27;
void gfx_native_clip(int out[4]){out[0]=clip_x0;out[1]=clip_y0;out[2]=clip_x1;out[3]=clip_y1;}
uint16_t gfx_RGBTo1555(unsigned r,unsigned g,unsigned b){
    return ((r>>3)<<10)|((g>>3)<<5)|(b>>3);
}
void gfx_SetPalette(const void *p,unsigned size,unsigned offset){
    if(offset>=512)return;if(size>512-offset)size=512-offset;
    memcpy((uint8_t*)gfx_palette+offset,p,size);
}
void gfx_SetColor(uint8_t c){color=c;}
void gfx_SetClipRegion(int x0,int y0,int x1,int y1){
    clip_x0=x0<0?0:x0;clip_y0=y0<0?0:y0;
    clip_x1=x1>320?320:x1;clip_y1=y1>240?240:y1;
}
void gfx_SetPixel(int x,int y){if(x>=0&&x<320&&y>=0&&y<240)draw_target[y*320+x]=color;}
void gfx_FillScreen(uint8_t c){memset(draw_target,c,sizeof native_indexed_frame);}
void gfx_FillRectangle_NoClip(int x,int y,int w,int h){
    if(w<=0||h<=0)return;
    int x0=x<0?0:x,y0=y<0?0:y,x1=x+w>320?320:x+w,y1=y+h>240?240:y+h;
    for(int yy=y0;yy<y1;yy++)if(x1>x0)memset(draw_target+yy*320+x0,color,x1-x0);
}
void gfx_FillRectangle(int x,int y,int w,int h){
    int x0=x<clip_x0?clip_x0:x,y0=y<clip_y0?clip_y0:y;
    int x1=x+w>clip_x1?clip_x1:x+w,y1=y+h>clip_y1?clip_y1:y+h;
    gfx_FillRectangle_NoClip(x0,y0,x1-x0,y1-y0);
}
void gfx_Rectangle_NoClip(int x,int y,int w,int h){
    gfx_FillRectangle_NoClip(x,y,w,1);gfx_FillRectangle_NoClip(x,y+h-1,w,1);
    gfx_FillRectangle_NoClip(x,y,1,h);gfx_FillRectangle_NoClip(x+w-1,y,1,h);
}
static void sprite(const gfx_sprite_t *s,int x,int y,bool transparent){
    if(!s)return;
    int clip[4];gfx_native_clip(clip);native_presentation_sprite(s,x,y,transparent,clip);
    for(int yy=0;yy<s->height;yy++){
        int dy=y+yy;if(dy<clip_y0||dy>=clip_y1)continue;
        for(int xx=0;xx<s->width;xx++){
            int dx=x+xx;if(dx<clip_x0||dx>=clip_x1)continue;
            uint8_t p=s->data[yy*s->width+xx];
            if(p||!transparent)draw_target[dy*320+dx]=p;
        }
    }
}
void gfx_Sprite(const gfx_sprite_t *s,int x,int y){sprite(s,x,y,false);}
void gfx_TransparentSprite(const gfx_sprite_t *s,int x,int y){sprite(s,x,y,true);}
void gfx_RLETSprite(const gfx_rletsprite_t *s,int x,int y){sprite(s,x,y,true);}
void gfx_FlipSpriteY(const gfx_sprite_t *a,gfx_sprite_t *b){
    b->width=a->width;b->height=a->height;
    for(unsigned y=0;y<a->height;y++)for(unsigned x=0;x<a->width;x++)
        b->data[y*a->width+x]=a->data[y*a->width+(a->width-x-1)];
}
bool gfx_CheckRectangleHotspot(int x0,int y0,int w0,int h0,int x1,int y1,int w1,int h1){
    return x0<x1+w1&&x1<x0+w0&&y0<y1+h1&&y1<y0+h0;
}
uint8_t *gfx_TilePtr(const gfx_tilemap_t *t,int x,int y){
    if(x<0||y<0||x>=(int)t->width*16||y>=(int)t->height*16){outside_tile=27;return &outside_tile;}
    return t->map+(y>>4)*t->width+(x>>4);
}
void gfx_Tilemap(const gfx_tilemap_t *t,unsigned sx,unsigned sy){
    bool capturing=native_presentation_capturing();
    if(capturing){int clip[4];gfx_native_clip(clip);native_presentation_tilemap(t,sx,sy,clip);native_presentation_capture(false);}
    for(unsigned yy=0;yy<t->draw_height;yy++)for(unsigned xx=0;xx<t->draw_width;xx++){
        int tx=(int)(sx/16+xx),ty=(int)(sy/16+yy);
        uint8_t n=27;if(tx<(int)t->width&&ty<(int)t->height)n=t->map[ty*t->width+tx];
        gfx_Sprite(t->tiles[n],(int)(xx*16)-(int)(sx%16),(int)(yy*16)-(int)(sy%16));
    }
    if(capturing)native_presentation_capture(true);
}
void gfx_SetTextXY(int x,int y){text_x=x;text_y=y;}
void gfx_SetTextFGColor(uint8_t c){fg=c;}
void gfx_SetTextBGColor(uint8_t c){bg=c;}
void gfx_SetTextTransparentColor(uint8_t c){text_transparent=c;}
static void print(const char *s){
    while(*s){unsigned c=(unsigned char)*s++;if(c>127)c='?';
        unsigned w=spacing[c];
        for(unsigned y=0;y<8;y++)for(unsigned x=0;x<w;x++){
            uint8_t p=(font[c][y]&(128>>x))?fg:bg;
            if(p!=text_transparent){color=p;gfx_SetPixel(text_x+(int)x,text_y+(int)y);}
        }
        text_x+=(int)w;
    }
}
void gfx_PrintUInt(unsigned value,unsigned digits){
    char s[32];if(digits>20)digits=20;snprintf(s,sizeof s,"%0*u",(int)digits,value);print(s);
}
void gfx_PrintStringXY(const char *s,int x,int y){gfx_SetTextXY(x,y);print(s);}
void gfx_BlitLines(int buffer,unsigned y,unsigned count){(void)buffer;(void)y;(void)count;}
