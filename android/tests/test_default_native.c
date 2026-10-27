#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "core.h"
static unsigned read8(FILE *f){int c=fgetc(f);assert(c!=EOF);return(unsigned)c;}
static unsigned read16(FILE *f){unsigned a=read8(f);return a|(read8(f)<<8);}
static unsigned read32(FILE *f){unsigned a=read16(f);return a|(read16(f)<<16);}
int main(int argc,char **argv){
    assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);
    unsigned count=read8(f);assert(count==12);
    for(unsigned stage=0;stage<count;stage++){
        unsigned width=read8(f),height=read8(f),scroll=read8(f),color=read16(f),nw=read16(f);
        uint32_t warps[510];assert(nw<=508);
        for(unsigned i=0;i<nw;i++)warps[i]=read32(f);
        uint8_t *tiles=malloc(width*height);assert(fread(tiles,1,width*height,f)==width*height);
        for(unsigned scenario=0;scenario<8;scenario++){
            int forms[]={0,1,3,17};
            fprintf(stderr,"Default stage %u scenario %u\n",stage+1,scenario);fflush(stderr);
            assert(oiram_native_configure(tiles,width,height,scroll,color,warps,nw,stage,count,15,forms[scenario%4],0,0));
            for(unsigned tick=0;tick<1800;tick++){
                uint32_t mask=scenario<4?2|32:1|32;
                if(tick%40<15)mask|=16;
                if(tick%11==0)mask|=64;
                if(tick%300>260)mask|=8;
                oiram_native_step(mask);
                if(tick%30==0){oiram_native_clock(1);oiram_native_frame();}
                if(oiram_native_state().exit)break;
            }
        }
        free(tiles);
    }
    fclose(f);oiram_native_shutdown();puts("All default-stage native sanitizer scenarios passed");return 0;
}
