// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct N64HostHandle N64HostHandle;

/// All calls must come from the same thread (RetroPlay's emulation thread):
/// the GLES context is made current on the calling thread.
N64HostHandle* N64Host_Create(void);
void N64Host_Destroy(N64HostHandle* h);

/// Load a .z64/.n64/.v64. `sramPath` (may be NULL) is where battery saves are kept.
bool N64Host_LoadROM(N64HostHandle* h, const char* path, const char* sramPath);

/// Buttons use mupen BUTTON bits; stick is -1…1 with Y up-positive.
void N64Host_SetKeys(N64HostHandle* h, uint32_t n64Bitmask, float stickX, float stickY);
void N64Host_RunFrame(N64HostHandle* h);
void N64Host_Reset(N64HostHandle* h);

/// Last frame as tightly packed RGBA8 (valid until the next RunFrame), or NULL.
const uint8_t* N64Host_Frame(N64HostHandle* h, int* outW, int* outH);

/// Drain interleaved stereo Int16 audio. Returns frames written.
int N64Host_ReadAudio(N64HostHandle* h, int16_t* out, int maxFrames);
double N64Host_FrameRate(N64HostHandle* h);
double N64Host_SampleRate(N64HostHandle* h);

/// Write battery save RAM to disk if it changed.
void N64Host_FlushSaveData(N64HostHandle* h);

bool N64Host_SaveState(N64HostHandle* h, const char* path);
bool N64Host_LoadState(N64HostHandle* h, const char* path);

#ifdef __cplusplus
}
#endif
