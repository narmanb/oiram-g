/* Original pools can evict the object currently executing a collision callback.
 * Remove it from the original lists immediately, but reclaim its allocation only
 * after the tick's callbacks finish. This changes no pool limit or game rule.
 */
#include "platform.h"
typedef struct {void *pointer;uint64_t id;} object_id_t;
static object_id_t *objects;
static size_t object_count,object_capacity;
static uint64_t next_object_id=1;
void *oiram_native_calloc(size_t count,size_t size){
    void *p=calloc(count,size);if(!p)abort();
    if(object_count==object_capacity){
        size_t capacity=object_capacity?object_capacity*2:64;
        object_id_t *next=realloc(objects,capacity*sizeof *next);if(!next)abort();
        objects=next;object_capacity=capacity;
    }
    objects[object_count++]=(object_id_t){p,next_object_id++};return p;
}
uint64_t oiram_native_object_id(const void *p){
    if(!p)return 0;
    for(size_t i=0;i<object_count;i++)if(objects[i].pointer==p)return objects[i].id;
    return (uint64_t)(uintptr_t)p|((uint64_t)1<<63); /* permanent globals, such as the player */
}
static void reclaim(void *p){
    for(size_t i=0;i<object_count;i++)if(objects[i].pointer==p){objects[i]=objects[--object_count];break;}
    free(p);
}
static bool in_tick;
static void **retired;
static size_t retired_count,retired_capacity;
void oiram_native_memory_begin(void){in_tick=true;}
void oiram_native_retire(void *p){
    if(!p)return;
    if(!in_tick){reclaim(p);return;}
    if(retired_count==retired_capacity){
        size_t capacity=retired_capacity?retired_capacity*2:64;
        void **next=realloc(retired,capacity*sizeof *next);
        if(!next)abort();
        retired=next;retired_capacity=capacity;
    }
    retired[retired_count++]=p;
}
void oiram_native_memory_end(void){
    in_tick=false;
    for(size_t i=0;i<retired_count;i++)reclaim(retired[i]);
    retired_count=0;
}
void oiram_native_memory_release(void){
    oiram_native_memory_end();free(retired);retired=NULL;retired_capacity=0;
    free(objects);objects=NULL;object_count=object_capacity=0;
}
