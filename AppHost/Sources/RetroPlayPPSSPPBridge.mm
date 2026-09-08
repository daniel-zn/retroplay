#import "RetroPlayPPSSPPBridge.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if RETROPLAY_HAS_PPSSPP

#include "Common/File/Path.h"
#include "Common/System/NativeApp.h"
#include "Core/CmdLine.h"
#include "Core/Config.h"
#include "Core/ConfigValues.h"
#include "Core/Core.h"
#include "Core/CoreParameter.h"
#include "Core/MemMap.h"
#include "Core/Screenshot.h"
#include "Core/System.h"
#include "GPU/Common/GPUDebugInterface.h"
#include "GPU/GPUCommon.h"
#include "GPU/GPUState.h"
#include "GPU/ge_constants.h"

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

/// After a host frame, PPSSPP leaves coreState as CORE_NEXTFRAME. EmuScreen / libretro
/// reset it to CORE_RUNNING_CPU before the next RunLoop; without that, every later
/// PSP_RunLoop* returns immediately and the game never advances (no display framebuffer).
void resumeCPUIfNeeded() {
    if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN) {
        coreState = CORE_RUNNING_CPU;
    }
}

bool packRGBAFromDebugBuffer(const GPUDebugBuffer &buf, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    if (!buf.GetData()) return false;
    u32 w = buf.GetStride();
    u32 h = buf.GetHeight();
    if (w == 0 || h == 0) return false;

    u8 *temp = nullptr;
    const u8 *rgba = ConvertBufferToScreenshot(buf, true, temp, w, h);
    if (!rgba || w == 0 || h == 0) {
        delete[] temp;
        return false;
    }

    const size_t nbytes = (size_t)w * (size_t)h * 4;
    uint8_t *out = (uint8_t *)std::malloc(nbytes);
    if (!out) {
        delete[] temp;
        return false;
    }
    std::memcpy(out, rgba, nbytes);
    delete[] temp;

    *outBytes = out;
    *outWidth = (int)w;
    *outHeight = (int)h;
    *outStrideBytes = (int)w * 4;
    return true;
}

/// SoftGPU::GetOutputFramebuffer fails until sceDisplaySetFrameBuf (displayFramebuf_ valid).
/// Fall back to the current render target via gstate + Memory once MemMap is up.
bool copyFromGStateVRAM(uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    if (!Memory::IsActive()) return false;

    u32 addr = gstate.getFrameBufAddress();
    if (!Memory::IsValidAddress(addr)) {
        addr = 0x04000000;
        if (!Memory::IsValidAddress(addr)) return false;
    }

    const u8 *src = Memory::GetPointerOrNull(addr);
    if (!src) return false;

    int stride = gstate.FrameBufStride();
    if (stride <= 0) stride = 512;
    GEBufferFormat fmt = gstate.FrameBufFormat();

    const int w = 480;
    const int h = 272;
    const int depth = (fmt == GE_FORMAT_8888) ? 4 : 2;

    GPUDebugBuffer tight;
    tight.Allocate((u32)w, (u32)h, fmt);
    u8 *td = tight.GetData();
    if (!td) return false;
    for (int y = 0; y < h; ++y) {
        std::memcpy(td + y * w * depth, src + y * stride * depth, (size_t)w * (size_t)depth);
    }
    return packRGBAFromDebugBuffer(tight, outBytes, outWidth, outHeight, outStrideBytes);
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
    param.headLess = true;
    param.fileToStart = Path(std::string(gamePath));
    param.startBreak = false;

    std::string error;
    BootState state = PSP_Init(param, &error);
    if (state != BootState::Complete) {
        NativeShutdown();
        setError(errorOut, errorOutLen, error.empty() ? "PSP_Init failed" : error);
        return false;
    }

    // EmuScreen / libretro set this after Complete; PSP_Init alone does not.
    coreState = CORE_RUNNING_CPU;

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

    resumeCPUIfNeeded();
    PSP_RunLoopWhileState();
    // Match libretro: after a full host frame, put the CPU back to running for the next tick.
    if (coreState == CORE_NEXTFRAME) {
        coreState = CORE_RUNNING_CPU;
    }
}

bool rp_ppsspp_copy_rgba(void *bridgePtr, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || !outBytes || !outWidth || !outHeight || !outStrideBytes) {
        return false;
    }
    *outBytes = nullptr;

    if (gpu) {
        GPUDebugBuffer buf;
        if (gpu->GetOutputFramebuffer(buf) && buf.GetData() != nullptr) {
            if (packRGBAFromDebugBuffer(buf, outBytes, outWidth, outHeight, outStrideBytes)) {
                return true;
            }
        }
    }

    // Display buffer not set yet (or SoftGPU early-out). Try render-target VRAM via gstate.
    return copyFromGStateVRAM(outBytes, outWidth, outHeight, outStrideBytes);
}

void rp_ppsspp_pause(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) bridge->paused = true;
}

void rp_ppsspp_resume(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) {
        bridge->paused = false;
        resumeCPUIfNeeded();
    }
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
