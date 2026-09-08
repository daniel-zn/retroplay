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

#if __has_include("GPU/GPU.h")
#include "GPU/GPU.h"
#endif
#if __has_include("GPU/Common/GPUDebugInterface.h")
#include "GPU/Common/GPUDebugInterface.h"
#endif

namespace {
struct BridgeState {
    bool inited = false;
    bool paused = false;
    uint32_t buttons = 0;
    std::string saveDir;
    std::string cacheDir;
};

BridgeState *asBridge(void *p) { return static_cast<BridgeState *>(p); }

void setError(char *errorOut, size_t errorOutLen, const std::string &msg) {
    if (!errorOut || errorOutLen == 0) return;
    std::snprintf(errorOut, errorOutLen, "%s", msg.c_str());
}
}  // namespace

void *rp_ppsspp_create(const char *saveDir, const char *cacheDir) {
    auto *b = new BridgeState();
    b->saveDir = saveDir ? saveDir : "";
    b->cacheDir = cacheDir ? cacheDir : "";
    return b;
}

void rp_ppsspp_destroy(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge) return;
    if (bridge->inited) {
        PSP_Shutdown(true);
        NativeShutdown();
        bridge->inited = false;
    }
    delete bridge;
}

bool rp_ppsspp_load(void *bridgePtr, const char *gamePath, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !gamePath) {
        setError(errorOut, errorOutLen, "null bridge or path");
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

    g_Config.iCpuCore = (int)CPUCore::IR_INTERPRETER;

    CoreParameter param{};
    param.cpuCore = CPUCore::IR_INTERPRETER;
    param.gpuCore = GPUCORE_SOFTWARE;
    param.enableSound = false;
    param.fileToStart = Path(std::string(gamePath));
    param.startBreak = false;

    std::string error;
    BootState state = PSP_Init(param, &error);
    if (state != BootState::Complete) {
        NativeShutdown();
        setError(errorOut, errorOutLen, error.empty() ? "PSP_Init failed" : error);
        return false;
    }

    bridge->inited = true;
    bridge->paused = false;
    return true;
}

void rp_ppsspp_set_buttons(void *bridgePtr, uint32_t ctrlBits) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge) return;
    bridge->buttons = ctrlBits;
    (void)ctrlBits;
}

void rp_ppsspp_run_frame(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || bridge->paused) return;
    PSP_RunLoopFor(3333333 / 60);
}

bool rp_ppsspp_copy_rgba(void *bridgePtr, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || !outBytes || !outWidth || !outHeight || !outStrideBytes) {
        return false;
    }
    *outBytes = nullptr;

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
}

void rp_ppsspp_pause(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) bridge->paused = true;
}

void rp_ppsspp_resume(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) bridge->paused = false;
}

#else

void *rp_ppsspp_create(const char *, const char *) { return nullptr; }
void rp_ppsspp_destroy(void *) {}
bool rp_ppsspp_load(void *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) {
        std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    }
    return false;
}
void rp_ppsspp_set_buttons(void *, uint32_t) {}
void rp_ppsspp_run_frame(void *) {}
bool rp_ppsspp_copy_rgba(void *, uint8_t **, int *, int *, int *) { return false; }
void rp_ppsspp_pause(void *) {}
void rp_ppsspp_resume(void *) {}

#endif
