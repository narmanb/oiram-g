#ifndef OIRAM_PLATFORM_H
#define OIRAM_PLATFORM_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
typedef uint32_t uint24_t;
typedef int32_t int24_t;
void *oiram_native_calloc(size_t count,size_t size);
uint64_t oiram_native_object_id(const void *p);
void oiram_native_retire(void *p);
void oiram_native_memory_begin(void);
void oiram_native_memory_end(void);
void oiram_native_memory_release(void);
#define LCD_WIDTH 320
#define LCD_HEIGHT 240
#endif
