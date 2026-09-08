#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque PPSSPP host session for RetroPlay (IR interpreter / App Store path).
typedef struct RetroPlayPPSSPPBridge RetroPlayPPSSPPBridge;

/// Create a bridge. `saveDir` / `cacheDir` are UTF-8 sandbox paths (Documents).
RetroPlayPPSSPPBridge *rp_ppsspp_create(const char *saveDir, const char *cacheDir);

void rp_ppsspp_destroy(RetroPlayPPSSPPBridge *bridge);

/// Load an ISO/CSO/PBP/ELF. On failure, writes a message into `errorOut` (may be NULL).
bool rp_ppsspp_load(RetroPlayPPSSPPBridge *bridge, const char *gamePath, char *errorOut, size_t errorOutLen);

/// PSP button bitmask using upstream CTRL_* bits from sceCtrl.h.
void rp_ppsspp_set_buttons(RetroPlayPPSSPPBridge *bridge, uint32_t ctrlBits);

/// Advance emulation roughly one frame (best-effort).
void rp_ppsspp_run_frame(RetroPlayPPSSPPBridge *bridge);

/// Copy current display as tightly packed RGBA8888 into malloc'd buffer.
/// Caller frees with free(). Returns false if no frame yet.
bool rp_ppsspp_copy_rgba(RetroPlayPPSSPPBridge *bridge, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes);

void rp_ppsspp_pause(RetroPlayPPSSPPBridge *bridge);
void rp_ppsspp_resume(RetroPlayPPSSPPBridge *bridge);

#ifdef __cplusplus
}
#endif
