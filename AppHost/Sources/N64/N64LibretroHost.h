#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct N64HostHandle N64HostHandle;

N64HostHandle* N64Host_Create(void);
void N64Host_Destroy(N64HostHandle* h);

/// Load a .z64/.n64/.v64 from path. Creates GLES context + FBO (call on a thread that will run frames).
bool N64Host_LoadROM(N64HostHandle* h, const char* path);

void N64Host_SetKeys(N64HostHandle* h, uint32_t n64Bitmask, int8_t stickX, int8_t stickY);
void N64Host_RunFrame(N64HostHandle* h);

/// Copies last HW frame as RGBA8. Returns byte length or 0.
size_t N64Host_CopyRGBA(N64HostHandle* h, void* outRGBA, size_t outCapacity, int* outW, int* outH);

bool N64Host_SaveState(N64HostHandle* h, const char* path);
bool N64Host_LoadState(N64HostHandle* h, const char* path);

#ifdef __cplusplus
}
#endif
