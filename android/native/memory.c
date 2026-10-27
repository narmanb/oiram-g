/* Original pools can evict the object currently executing a collision callback.
 * Remove it from the original lists immediately, but reclaim its allocation only
 * after the tick's callbacks finish. This changes no pool limit or game rule.
 */
#include "platform.h"
static bool in_tick;
static void **retired;
static size_t retired_count,retired_capacity;
void oiram_native_memory_begin(void){in_tick=true;}
void oiram_native_retire(void *p){
    if(!p)return;
    if(!in_tick){free(p);return;}
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
    for(size_t i=0;i<retired_count;i++)free(retired[i]);
    retired_count=0;
}
void oiram_native_memory_release(void){
    oiram_native_memory_end();free(retired);retired=NULL;retired_capacity=0;
}
