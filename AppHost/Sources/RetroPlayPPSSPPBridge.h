// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque PPSSPP host session (Swift: OpaquePointer).
void *rp_ppsspp_create(const char *saveDir, const char *cacheDir);
void rp_ppsspp_destroy(void *bridge);

/// Load an ISO/CSO/PBP/ELF. On failure, writes a message into `errorOut` (may be NULL).
bool rp_ppsspp_load(void *bridge, const char *gamePath, char *errorOut, size_t errorOutLen);

/// PSP button bitmask using upstream CTRL_* bits from sceCtrl.h.
void rp_ppsspp_set_buttons(void *bridge, uint32_t ctrlBits);

/// True once the emulated CPU hit an unrecoverable runtime error (CORE_RUNTIME_ERROR).
/// Frames no-op after that; a successful state load clears it.
bool rp_ppsspp_had_runtime_error(void *bridge);
/// PPSSPP paces itself to real time unless fast-forward is set on its CoreParameter.
void rp_ppsspp_set_fast_forward(void *bridge, bool enabled);

/// Left analog stick, -1…1, Y up-positive.
void rp_ppsspp_set_analog(void *bridge, float x, float y);

/// Drain interleaved stereo Int16 audio (44.1 kHz). Returns frames written.
int rp_ppsspp_read_audio(void *bridge, int16_t *out, int maxFrames);

/// Advance emulation roughly one frame (best-effort).
void rp_ppsspp_run_frame(void *bridge);

/// Hardware rendering: each finished frame is an IOSurface (BGRA8, the internal render size),
/// passed as `surface` (an IOSurfaceRef) on a background thread once the GPU is done with it.
/// Retain it to keep it. Set before `rp_ppsspp_load`.
typedef void (*rp_ppsspp_frame_callback)(void *context, void *surface);
void rp_ppsspp_set_frame_callback(void *bridge, rp_ppsspp_frame_callback callback, void *context);

/// Internal resolution as a multiple of the PSP's 480×272 (1…8). Takes effect between frames.
void rp_ppsspp_set_render_scale(void *bridge, int scale);

/// True when the loaded game renders on the GPU (frames come through the frame callback and
/// `rp_ppsspp_copy_rgba` returns false); false for the software renderer.
bool rp_ppsspp_uses_gpu(void *bridge);

/// Software renderer: copy current display as tightly packed RGBA8888 into malloc'd buffer.
/// Caller frees with free(). Returns false if no frame yet.
bool rp_ppsspp_copy_rgba(void *bridge, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes);

/// Synchronous save/load (Save+Process, with SaveToRam/LoadFromRam fallback) into `path`.
bool rp_ppsspp_save_state(void *bridge, const char *path, char *errorOut, size_t errorOutLen);
bool rp_ppsspp_load_state(void *bridge, const char *path, char *errorOut, size_t errorOutLen);

/// Persist the GPU shader cache now (pausing, backgrounding, quitting).
void rp_ppsspp_save_caches(void *bridge);

void rp_ppsspp_pause(void *bridge);
void rp_ppsspp_resume(void *bridge);

#ifdef __cplusplus
}
#endif
