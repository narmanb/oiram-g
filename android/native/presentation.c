/* Render-only interpolation of original draw commands. Never advances game logic.
 * Entity allocation lifetimes prevent matching new enemies to deleted objects.
 * Sprites remain crisp indexed pixels; no image blending or invented physics.
 */
#include "presentation.h"
#include <math.h>
#define MAX_COMMANDS 4096
#define HASH_SIZE 8192
#define MAX_MAPS 2
#define MAP_BYTES (255*255)
enum {SPRITE=1,TILEMAP=2};
typedef struct {
    uint64_t entity;
    unsigned slot;
    int type,x,y,clip[4],width,height;
    const gfx_sprite_t *sprite;
    bool transparent;
    unsigned map;
} command_t;
typedef struct {
    gfx_tilemap_t map;
    uint8_t data[MAP_BYTES];
    gfx_sprite_t *tiles[256];
} map_snapshot_t;
static command_t buffers[2][MAX_COMMANDS],*current=buffers[0],*previous=buffers[1];
static map_snapshot_t maps[MAX_MAPS];
static int count,previous_count,map_count,lookup[HASH_SIZE];
static bool capturing,overflow;
static uint64_t entity;
static unsigned ordinal,channel;
static uint8_t rendered[320*240];
static unsigned hash(uint64_t id,unsigned slot){return (unsigned)(id^(id>>32)^(slot*2654435761u))&(HASH_SIZE-1);}
static const command_t *match(const command_t *c){
    unsigned h=hash(c->entity,c->slot);
    for(unsigned probes=0;probes<HASH_SIZE;probes++,h=(h+1)&(HASH_SIZE-1)){
        int i=lookup[h];if(i<0)return NULL;
        if(previous[i].entity==c->entity&&previous[i].slot==c->slot)return &previous[i];
    }
    return NULL;
}
static void index_previous(void){
    for(int i=0;i<HASH_SIZE;i++)lookup[i]=-1;
    for(int i=0;i<previous_count;i++){
        unsigned h=hash(previous[i].entity,previous[i].slot);
        while(lookup[h]>=0&&!(previous[lookup[h]].entity==previous[i].entity&&previous[lookup[h]].slot==previous[i].slot))h=(h+1)&(HASH_SIZE-1);
        lookup[h]=i;
    }
}
void native_presentation_reset(void){
    count=previous_count=map_count=0;capturing=overflow=false;entity=0;ordinal=channel=0;
}
void native_presentation_begin(void){
    command_t *swap=previous;previous=current;current=swap;
    previous_count=overflow?0:count;index_previous();
    count=map_count=0;overflow=false;capturing=true;entity=0;ordinal=channel=0;
}
void native_presentation_end(void){capturing=false;}
bool native_presentation_capturing(void){return capturing;}
void native_presentation_capture(bool enabled){capturing=enabled;}
void native_presentation_entity(const void *object,unsigned part){entity=oiram_native_object_id(object);ordinal=0;channel=part;}
static command_t *next_command(const int clip[4]){
    if(count==MAX_COMMANDS){overflow=true;return NULL;}
    command_t *c=&current[count++];memset(c,0,sizeof *c);memcpy(c->clip,clip,sizeof c->clip);return c;
}
void native_presentation_sprite(const gfx_sprite_t *s,int x,int y,bool transparent,const int clip[4]){
    if(!capturing||!s)return;
    command_t *c=next_command(clip);if(!c)return;
    c->type=SPRITE;c->entity=entity;c->slot=channel*256+ordinal++;c->x=x;c->y=y;
    c->sprite=s;c->transparent=transparent;c->width=s->width;c->height=s->height;
}
void native_presentation_tilemap(const gfx_tilemap_t *t,unsigned sx,unsigned sy,const int clip[4]){
    if(!capturing)return;
    if(map_count==MAX_MAPS||t->width*t->height>MAP_BYTES){overflow=true;return;}
    command_t *c=next_command(clip);if(!c)return;
    c->type=TILEMAP;c->entity=0;c->slot=0xffff0000u+(unsigned)map_count;c->x=(int)sx;c->y=(int)sy;c->map=(unsigned)map_count;
    map_snapshot_t *snapshot=&maps[map_count++];snapshot->map=*t;
    memcpy(snapshot->data,t->map,t->width*t->height);memcpy(snapshot->tiles,t->tiles,sizeof snapshot->tiles);
    snapshot->map.map=snapshot->data;snapshot->map.tiles=snapshot->tiles;
}
static int lerp_pixel(int a,int b,double alpha){double x=a+(b-a)*alpha;return (int)(x+(x<0?-0.5:0.5));}
const uint8_t *native_presentation_frame(double alpha){
    if(capturing||overflow||!count||!previous_count)return native_indexed_frame;
    if(!isfinite(alpha))alpha=1;
    if(alpha<0)alpha=0;if(alpha>1)alpha=1;
    memcpy(rendered,native_indexed_frame,sizeof rendered);
    int old_clip[4];gfx_native_clip(old_clip);uint8_t *old_target=gfx_native_target(rendered);
    for(int i=0;i<count;i++){
        const command_t *c=&current[i],*p=match(c);
        int x=c->x,y=c->y,clip[4];memcpy(clip,c->clip,sizeof clip);
        bool interpolate=p&&p->type==c->type&&p->width==c->width&&p->height==c->height&&abs(p->x-c->x)<=64&&abs(p->y-c->y)<=64;
        if(interpolate){
            x=lerp_pixel(p->x,c->x,alpha);y=lerp_pixel(p->y,c->y,alpha);
            for(int j=0;j<4;j++)clip[j]=lerp_pixel(p->clip[j],c->clip[j],alpha);
        }
        gfx_SetClipRegion(clip[0],clip[1],clip[2],clip[3]);
        if(c->type==TILEMAP)gfx_Tilemap(&maps[c->map].map,(unsigned)x,(unsigned)y);
        else if(c->transparent)gfx_TransparentSprite(c->sprite,x,y);
        else gfx_Sprite(c->sprite,x,y);
    }
    gfx_native_target(old_target);gfx_SetClipRegion(old_clip[0],old_clip[1],old_clip[2],old_clip[3]);
    return rendered;
}
