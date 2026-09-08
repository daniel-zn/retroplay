#import "RetroPlayPPSSPPBridge.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if RETROPLAY_HAS_PPSSPP

#include "Common/File/Path.h"
#include "Common/System/NativeApp.h"
#include "Core/Config.h"
#include "Core/ConfigValues.h"
#include "Core/CoreParameter.h"
#include "Core/System.h"

// Optional frame path — may not resolve on every PPSSPP revision.
#if __has_include("GPU/GPU.h")
#include "GPU/GPU.h"
#endif
#if __has_include("GPU/Common/GPUDebugInterface.h")
#include "GPU/Common/GPUDebugInterface.h"
#endif

struct RetroPlayPPSSPPBridge {
    bool inited = false;
    bool paused = false;
    uint32_t buttons = 0;
    std::string saveDir;
    std::string cacheDir;
};

static void rp_set_error(char *errorOut, size_t errorOutLen, const std::string &msg) {
    if (!errorOut || errorOutLen == 0) return;
    std::snprintf(errorOut, errorOutLen, "%s", msg.c_str());
}

RetroPlayPPSSPPBridge *rp_ppsspp_create(const char *saveDir, const char *cacheDir) {
    auto *b = new RetroPlayPPSSPPBridge();
    b->saveDir = saveDir ? saveDir : "";
    b->cacheDir = cacheDir ? cacheDir : "";
    return b;
}

void rp_ppsspp_destroy(RetroPlayPPSSPPBridge *bridge) {
    if (!bridge) return;
    if (bridge->inited) {
        PSP_Shutdown(true);
        NativeShutdown();
        bridge->inited = false;
    }
    delete bridge;
}

bool rp_ppsspp_load(RetroPlayPPSSPPBridge *bridge, const char *gamePath, char *errorOut, size_t errorOutLen) {
    if (!bridge || !gamePath) {
        rp_set_error(errorOut, errorOutLen, "null bridge or path");
        return false;
    }

    if (bridge->inited) {
        PSP_Shutdown(true);
        NativeShutdown();
        bridge->inited = false;
    }

    const char *argv[] = { "RetroPlay", gamePath };
    CommandLineOptions cmd{};
    NativeInit(2, argv, cmd, bridge->saveDir.c_str(), bridge->saveDir.c_str(), bridge->cacheDir.c_str());

    // App Store: IR interpreter only.
    g_Config.iCpuCore = (int)CPUCore::IR_INTERPRETER;

    CoreParameter param{};
    param.cpuCore = CPUCore::IR_INTERPRETER;
    // Software GPU preferred for headless RGBA capture; Metal comes later.
    param.gpuCore = GPUCORE_SOFTWARE;
    param.enableSound = false;
    param.fileToStart = Path(std::string(gamePath));
    param.startBreak = false;

    std::string error;
    BootState state = PSP_Init(param, &error);
    if (state != BootState::Complete) {
        NativeShutdown();
        rp_set_error(errorOut, errorOutLen, error.empty() ? "PSP_Init failed" : error);
        return false;
    }

    bridge->inited = true;
    bridge->paused = false;
    return true;
}

void rp_ppsspp_set_buttons(RetroPlayPPSSPPBridge *bridge, uint32_t ctrlBits) {
    if (!bridge) return;
    bridge->buttons = ctrlBits;
    (void)ctrlBits; // Wired to sceCtrl in a follow-up once symbols are confirmed on miniMac.
}

void rp_ppsspp_run_frame(RetroPlayPPSSPPBridge *bridge) {
    if (!bridge || !bridge->inited || bridge->paused) return;
    PSP_RunLoopFor(3333333 / 60);
}

bool rp_ppsspp_copy_rgba(RetroPlayPPSSPPBridge *bridge, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    if (!bridge || !bridge->inited || !outBytes || !outWidth || !outHeight || !outStrideBytes) {
        return false;
    }
    *outBytes = nullptr;

#if defined(GPU_DEBUG_INTERFACE_AVAILABLE) || 1
    // Try debug framebuffer when gpuDebug exists (linked from libPPSSPP).
    extern GPUDebugInterface *gpuDebug;
    if (!gpuDebug) {
        return false;
    }
    GPUDebugBuffer buf;
    if (!gpuDebug->GetOutputFramebuffer(buf) || buf.GetData() == nullptr) {
        return false;
    }
    const int w = (int)buf.GetStride();
    const int h = (int)buf.GetHeight();
    if (w <= 0 || h <= 0) return false;
    const size_t nbytes = (size_t)w * (size_t)h * 4;
    uint8_t *rgba = (uint8_t *)std::malloc(nbytes);
    if (!rgba) return false;
    std::memcpy(rgba, buf.GetData(), nbytes);
    *outBytes = rgba;
    *outWidth = w;
    *outHeight = h;
    *outStrideBytes = w * 4;
    return true;
#else
    return false;
#endif
}

void rp_ppsspp_pause(RetroPlayPPSSPPBridge *bridge) {
    if (bridge) bridge->paused = true;
}

void rp_ppsspp_resume(RetroPlayPPSSPPBridge *bridge) {
    if (bridge) bridge->paused = false;
}

#else

struct RetroPlayPPSSPPBridge { int unused; };

RetroPlayPPSSPPBridge *rp_ppsspp_create(const char *, const char *) { return nullptr; }
void rp_ppsspp_destroy(RetroPlayPPSSPPBridge *) {}
bool rp_ppsspp_load(RetroPlayPPSSPPBridge *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) {
        std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    }
    return false;
}
void rp_ppsspp_set_buttons(RetroPlayPPSSPPBridge *, uint32_t) {}
void rp_ppsspp_run_frame(RetroPlayPPSSPPBridge *) {}
bool rp_ppsspp_copy_rgba(RetroPlayPPSSPPBridge *, uint8_t **, int *, int *, int *) { return false; }
void rp_ppsspp_pause(RetroPlayPPSSPPBridge *) {}
void rp_ppsspp_resume(RetroPlayPPSSPPBridge *) {}

#endif
