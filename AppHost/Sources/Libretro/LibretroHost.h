// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A software-rendered libretro core loaded from an embedded framework with dlopen.
/// Each core is its own image, so several cores' `retro_*` symbols never collide.
/// All calls must come from RetroPlay's emulation thread; one game runs at a time.
typedef struct LibretroHost LibretroHost;

/// `frameworkName` is the bundle name inside the app's Frameworks folder (e.g. "nestopia").
/// `systemDir` holds BIOS files; `saveDir` is where cores that write their own files put them.
LibretroHost* LibretroHost_Create(const char* frameworkName, const char* systemDir, const char* saveDir);
void LibretroHost_Destroy(LibretroHost* h);

/// A core option RetroPlay pins (key → value), applied over the core's defaults. Set before Load.
void LibretroHost_SetOption(LibretroHost* h, const char* key, const char* value);

/// Load a game. `sramPath` (may be NULL) is where the core's SAVE_RAM block is kept.
/// On failure `errorOut` (may be NULL) gets a short reason, valid until the next call.
bool LibretroHost_Load(LibretroHost* h, const char* path, const char* sramPath, const char** errorOut);

/// `joypad` is a libretro RetroPad mask (bit n = RETRO_DEVICE_ID_JOYPAD_n).
/// Sticks are −1…1 with Y up-positive.
void LibretroHost_SetInput(LibretroHost* h, uint32_t joypad, float leftX, float leftY);
void LibretroHost_RunFrame(LibretroHost* h);
void LibretroHost_Reset(LibretroHost* h);

/// Last frame as tightly packed RGBA8 (valid until the next RunFrame), or NULL.
const uint8_t* LibretroHost_Frame(LibretroHost* h, int* outW, int* outH);
/// Drain interleaved stereo Int16 audio. Returns frames written.
int LibretroHost_ReadAudio(LibretroHost* h, int16_t* out, int maxFrames);
double LibretroHost_FrameRate(LibretroHost* h);
double LibretroHost_SampleRate(LibretroHost* h);

/// Write the SAVE_RAM block to disk if it changed.
void LibretroHost_FlushSaveData(LibretroHost* h);
bool LibretroHost_SaveState(LibretroHost* h, const char* path);
bool LibretroHost_LoadState(LibretroHost* h, const char* path);

#ifdef __cplusplus
}
#endif
