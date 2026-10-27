/* CPU-only host benchmark. Does not measure Android display/compositor pacing. */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "core.h"
enum { FRAMES=1200 };
static uint8_t map[255*12];
static double samples[FRAMES];
static volatile unsigned checksum;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static int compare(const void *a,const void *b){double x=*(const double*)a,y=*(const double*)b;return (x>y)-(x<y);}
static oiram_native_state_t measure(unsigned scale){
    assert(oiram_native_configure(map,255,12,0,0,NULL,0,0,1,15,0,0,0));
    double total=0;
    for(int i=0;i<FRAMES;i++){
        if(!(i&1))oiram_native_step(2|32);
        double start=now();
        const uint8_t *pixels=scale==1?oiram_native_frame_interpolated((i&1)*0.5):oiram_native_frame_scaled((i&1)*0.5,scale);
        checksum+=pixels[0];samples[i]=(now()-start)*1000;total+=samples[i];
    }
    qsort(samples,FRAMES,sizeof samples[0],compare);
    printf("Host CPU %ux%u: mean %.3f ms, p95 %.3f ms (%d frames; excludes Godot upload/display)\n",
        320*scale,240*scale,total/FRAMES,samples[(FRAMES*95)/100-1],FRAMES);
    return oiram_native_state();
}
int main(void){
    memset(map,27,sizeof map);for(int x=0;x<255;x++)map[10*255+x]=52;map[9*255+2]=240;
    oiram_native_state_t original=measure(1),fine=measure(2),high=measure(4);
    assert(!memcmp(&original,&fine,sizeof original));assert(!memcmp(&original,&high,sizeof original));oiram_native_shutdown();
    puts("Benchmark ended at identical game states; host results are not phone FPS.");return 0;
}
