// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MelonDSHandle MelonDSHandle;

/// All calls must come from one thread (RetroPlay's emulation thread).
MelonDSHandle* MelonDS_Create(void);
void MelonDS_Destroy(MelonDSHandle* h);
/// Load and boot a ROM. `savePath` (may be NULL) holds the cartridge battery save.
bool MelonDS_LoadROM(MelonDSHandle* h, const char* path, const char* savePath);
void MelonDS_SetKeyMask(MelonDSHandle* h, uint32_t mask);
void MelonDS_Touch(MelonDSHandle* h, uint16_t x, uint16_t y, bool pressed);
void MelonDS_RunFrame(MelonDSHandle* h);
void MelonDS_Reset(MelonDSHandle* h);
/// Copies stacked top+bottom screens as RGBA8 (256x384). Returns byte length or 0.
size_t MelonDS_CopyRGBA(MelonDSHandle* h, void* outRGBA, size_t outCapacity, int* outW, int* outH);
/// Drain interleaved stereo Int16 audio at MelonDS_SampleRate. Returns frames written.
int MelonDS_ReadAudio(MelonDSHandle* h, int16_t* out, int maxFrames);
double MelonDS_SampleRate(void);
/// Write the battery save to disk if the game changed it.
void MelonDS_FlushSave(MelonDSHandle* h);
bool MelonDS_SaveState(MelonDSHandle* h, const char* path);
bool MelonDS_LoadState(MelonDSHandle* h, const char* path);

#ifdef __cplusplus
}

/// Called from Platform::WriteNDSSave (Platform_ios.cpp) with the cart's userdata.
void MelonDS_OnNDSSaveWritten(void* userdata, const uint8_t* savedata, uint32_t savelen);
#endif
