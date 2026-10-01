// SPDX-License-Identifier: GPL-3.0-or-later
#import "RetroPlayPPSSPPBridge.h"
#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if RETROPLAY_HAS_PPSSPP

#include "Common/File/Path.h"
#include "Common/System/NativeApp.h"
#include "Common/System/System.h"
#include "Core/CmdLine.h"
#include "Core/Config.h"
#include "Core/ConfigValues.h"
#include "Core/Core.h"
#include "Core/CoreParameter.h"
#include "Core/Util/PathUtil.h"
#include "Core/HLE/sceUtility.h"
#include "Core/HW/MemoryStick.h"
#include "Core/Screenshot.h"
#include "Core/System.h"
#include "Core/HLE/sceCtrl.h"
#include "Core/SaveState.h"
#include "Core/HLE/sceDisplay.h"
#include <algorithm>
#include <fstream>
#include <mutex>
#include <vector>
#include "GPU/Common/GPUDebugInterface.h"
#include "GPU/GPUCommon.h"
#include "GPU/ge_constants.h"

namespace {
struct BridgeState {
    bool inited = false;
    bool paused = false;
    uint32_t buttons = 0;
    /// Set once the CPU stops at the unrecoverable CORE_RUNTIME_ERROR (see resumeCPUIfNeeded).
    /// Sticky so the host can say so instead of showing a silently frozen game.
    bool hadRuntimeError = false;
    std::string saveDir;
    std::string cacheDir;
};

// PPSSPP pushes mixed audio through the host hook System_AudioPushSamples (on the
// emulation thread, inside PSP_RunLoop*). Buffer it here until Swift drains it.
std::mutex gAudioMutex;
std::vector<int16_t> gAudio;
// ~0.5 s of stereo 44.1 kHz; older samples are dropped if nobody drains.
constexpr size_t kMaxAudioSamples = 44100;

BridgeState *asBridge(void *p) { return static_cast<BridgeState *>(p); }

void setError(char *errorOut, size_t errorOutLen, const std::string &msg) {
    if (!errorOut || errorOutLen == 0) return;
    std::snprintf(errorOut, errorOutLen, "%s", msg.c_str());
}

extern "C" bool rp_ppsspp_enables_software_renderer(void);

/// RetroPlay's memstick lives under Documents/Saves/psp-memstick. NativeInit on iOS resets
/// g_Config.memStickDirectory to Documents/ and loads ppsspp.ini from there, so host
/// defaults are applied before PSP_Init and again after (a game ini can change them).
void applyRetroPlayHostConfig(BridgeState *bridge) {
    g_Config.memStickDirectory = Path(bridge->saveDir);
    g_Config.internalDataDirectory = Path(bridge->saveDir);
    if (g_Config.iMemStickSizeGB < 1) {
        g_Config.iMemStickSizeGB = 16;
    }
    g_Config.bMemStickInserted = true;
    // Config::Load mutes every instance after the first (PPSSPP_ID > 1), and
    // RetroPlay has no in-app volume slider for this, so keep game audio at full.
    g_Config.iGameVolume = VOLUMEHI_FULL;
    // Games that query BUTTON_PREFERENCE copy this into common.buttonSwap.
    g_Config.iButtonPreference = PSP_SYSTEMPARAM_BUTTON_CROSS;
    // PPGeDrawCurrentText uses 512 texture windows only when this flag is set. Without it the
    // software sampler clamps the 2048-wide atlas and SAVEDATA dialog text draws as garbage.
    g_Config.bSoftwareRendering = rp_ppsspp_enables_software_renderer();
    g_Config.SetSearchPath(GetSysDirectory(DIRECTORY_SYSTEM));
    CreateSysDirectories();
    MemoryStick_Init();
    MemoryStick_SetState(PSP_MEMORYSTICK_STATE_INSERTED);
}

/// Bundle folder holding `ppge_atlas.zim`. Official iOS passes `<bundle>/assets/` as
/// NativeInit's external_dir, which is the VFS root `__PPGeInit` reads for dialog glyphs.
std::string retroPlayBundledPPSSPPAssetsDirectory() {
    NSString *root = NSBundle.mainBundle.resourcePath;
    if (root.length == 0) return {};
    NSString *assets = [root stringByAppendingPathComponent:@"assets"];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:[assets stringByAppendingPathComponent:@"ppge_atlas.zim"]] ||
        ![files fileExistsAtPath:[assets stringByAppendingPathComponent:@"ppge_atlas.meta"]]) {
        std::fprintf(stderr, "RetroPlay: PPGe atlas missing (SAVEDATA dialog text will not draw)\n");
        return {};
    }
    return std::string(assets.fileSystemRepresentation);
}

/// After a host frame, PPSSPP leaves coreState as CORE_NEXTFRAME. EmuScreen / libretro
/// reset it to CORE_RUNNING_CPU before the next RunLoop; without that, every later
/// PSP_RunLoop* returns immediately and the game never advances (no display framebuffer).
///
/// CORE_STEPPING_CPU is PPSSPP's bucket for recoverable runtime errors. The desktop UI
/// resumes it or shows a debugger; RetroPlay has neither, so a SAVEDATA dialog that trips
/// one would freeze forever. Continue it, like "ignore and continue" would.
/// CORE_RUNTIME_ERROR is unrecoverable and is left alone; returns false for it.
bool resumeCPUIfNeeded() {
    if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN || coreState == CORE_STEPPING_CPU) {
        coreState = CORE_RUNNING_CPU;
    }
    return coreState != CORE_RUNTIME_ERROR;
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
    const std::string ppgeAssets = retroPlayBundledPPSSPPAssetsDirectory();
    const char *externalDir = ppgeAssets.empty() ? bridge->saveDir.c_str() : ppgeAssets.c_str();
    NativeInit(2, argv, cmd, bridge->saveDir.c_str(), externalDir, bridge->cacheDir.c_str());
    applyRetroPlayHostConfig(bridge);

    g_Config.iCpuCore = (int)CPUCore::IR_INTERPRETER;
    g_Config.bEnableSound = true;
    {
        std::lock_guard<std::mutex> lock(gAudioMutex);
        gAudio.clear();
    }

    CoreParameter param{};
    param.cpuCore = CPUCore::IR_INTERPRETER;
    param.gpuCore = GPUCORE_SOFTWARE;
    param.enableSound = true;
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
    applyRetroPlayHostConfig(bridge);
    bridge->hadRuntimeError = false;

    bridge->inited = true;
    bridge->paused = false;
    return true;
}

void rp_ppsspp_set_buttons(void *bridgePtr, uint32_t ctrlBits) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited) {
        if (bridge) bridge->buttons = ctrlBits;
        return;
    }
    const uint32_t prev = bridge->buttons;
    const uint32_t bitsToSet = ctrlBits & ~prev;
    const uint32_t bitsToClear = prev & ~ctrlBits;
    bridge->buttons = ctrlBits;
    if (bitsToSet || bitsToClear) {
        __CtrlUpdateButtons(bitsToSet, bitsToClear);
    }
}

void rp_ppsspp_set_analog(void *bridgePtr, float x, float y) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited) return;
    __CtrlSetAnalogXY(CTRL_STICK_LEFT, std::clamp(x, -1.0f, 1.0f), std::clamp(y, -1.0f, 1.0f));
}

int rp_ppsspp_read_audio(void *bridgePtr, int16_t *out, int maxFrames) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !out || maxFrames <= 0) return 0;
    std::lock_guard<std::mutex> lock(gAudioMutex);
    const size_t frames = std::min(gAudio.size() / 2, (size_t)maxFrames);
    if (frames == 0) return 0;
    std::memcpy(out, gAudio.data(), frames * 2 * sizeof(int16_t));
    gAudio.erase(gAudio.begin(), gAudio.begin() + (std::ptrdiff_t)(frames * 2));
    return (int)frames;
}

void rp_ppsspp_run_frame(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || bridge->paused) return;

    if (bridge->hadRuntimeError) return;
    if (!resumeCPUIfNeeded()) {
        // Unrecoverable: don't spin PSP_RunLoopWhileState() against a dead CPU every tick.
        bridge->hadRuntimeError = true;
        return;
    }
    PSP_RunLoopWhileState();
    // Match libretro: after a full host frame, put the CPU back to running for the next tick.
    if (!resumeCPUIfNeeded()) {
        bridge->hadRuntimeError = true;
    }
}

bool rp_ppsspp_had_runtime_error(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    return bridge ? bridge->hadRuntimeError : false;
}

bool rp_ppsspp_copy_rgba(void *bridgePtr, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || !outBytes || !outWidth || !outHeight || !outStrideBytes) {
        return false;
    }
    *outBytes = nullptr;

    // Only the display framebuffer is shown. Until the game sets one (sceDisplaySetFrameBuf)
    // there is nothing to show, as on a real PSP: report no new frame and the screen keeps
    // its last image (black on a fresh boot). Reading raw VRAM instead showed garbage
    // ("static") after Restart from Scratch, when VRAM holds data in another format.
    if (gpu) {
        GPUDebugBuffer buf;
        if (gpu->GetOutputFramebuffer(buf) && buf.GetData() != nullptr) {
            return packRGBAFromDebugBuffer(buf, outBytes, outWidth, outHeight, outStrideBytes);
        }
    }
    return false;
}


bool rp_ppsspp_save_state(void *bridgePtr, const char *path, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || !path) {
        setError(errorOut, errorOutLen, "null bridge/path or not inited");
        return false;
    }
    if (!gpu) {
        setError(errorOut, errorOutLen, "PPSSPP GPU not ready for save state");
        return false;
    }

    // Prefer the same queued path as EmuScreen (Save + Process) so screenshot/side
    // effects stay consistent; fall back to SaveToRam if the file op fails.
    struct Result {
        bool done = false;
        bool ok = false;
        std::string message;
    } result;

    SaveState::Save(Path(std::string(path)), -1,
        [&result](SaveState::Status status, std::string_view message, std::string_view) {
            result.ok = (status != SaveState::Status::FAILURE);
            result.message = std::string(message);
            result.done = true;
        });
    SaveState::Process();
    if (result.done && result.ok) {
        __DisplaySetWasPaused();
        return true;
    }

    // Fallback: synchronous RAM snapshot into `path`.
    std::vector<u8> data;
    auto err = SaveState::SaveToRam(data);
    if (err != CChunkFileReader::ERROR_NONE || data.empty()) {
        setError(errorOut, errorOutLen,
                 result.message.empty() ? "SaveState::SaveToRam failed" : result.message.c_str());
        return false;
    }
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        setError(errorOut, errorOutLen, "could not open save path");
        return false;
    }
    out.write(reinterpret_cast<const char *>(data.data()), (std::streamsize)data.size());
    if (!out.good()) {
        setError(errorOut, errorOutLen, "write failed");
        return false;
    }
    __DisplaySetWasPaused();
    return true;
}

bool rp_ppsspp_load_state(void *bridgePtr, const char *path, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited || !path) {
        setError(errorOut, errorOutLen, "null bridge/path or not inited");
        return false;
    }
    if (!gpu) {
        setError(errorOut, errorOutLen, "PPSSPP GPU not ready for load state");
        return false;
    }

    // A broken state can fail halfway through, leaving a half-restored game that
    // PPSSPP would only recover from by restarting. Snapshot first and put it back.
    std::vector<u8> snapshot;
    if (SaveState::SaveToRam(snapshot) != CChunkFileReader::ERROR_NONE) {
        snapshot.clear();
    }
    auto fail = [&](const std::string &message) {
        if (!snapshot.empty()) {
            std::string restoreErr;
            if (SaveState::LoadFromRam(snapshot, &restoreErr) == CChunkFileReader::ERROR_NONE) {
                // Drop the restart request HandleLoadFailure queued; the game is intact.
                SaveState::PollRestartNeeded();
                resumeCPUIfNeeded();
            } else {
                std::fprintf(stderr, "RetroPlay: PSP state rollback failed: %s\n", restoreErr.c_str());
            }
        }
        setError(errorOut, errorOutLen, message);
        return false;
    };

    struct Result {
        bool done = false;
        bool ok = false;
        std::string message;
    } result;

    SaveState::Load(Path(std::string(path)), -1,
        [&result](SaveState::Status status, std::string_view message, std::string_view) {
            result.ok = (status != SaveState::Status::FAILURE);
            result.message = std::string(message);
            result.done = true;
        });
    SaveState::Process();
    if (result.done && result.ok) {
        if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN) {
            coreState = CORE_RUNNING_CPU;
        }
        bridge->hadRuntimeError = false;
        __DisplaySetWasPaused();
        return true;
    }

    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) {
        return fail(result.message.empty() ? "save state file missing" : result.message);
    }
    const auto sz = in.tellg();
    if (sz <= 0) {
        return fail("empty save state");
    }
    std::vector<u8> data((size_t)sz);
    in.seekg(0, std::ios::beg);
    in.read(reinterpret_cast<char *>(data.data()), sz);
    if (!in) {
        return fail("read failed");
    }
    std::string errStr;
    auto err = SaveState::LoadFromRam(data, &errStr);
    if (err != CChunkFileReader::ERROR_NONE) {
        return fail(errStr.empty() ? "LoadFromRam failed" : errStr);
    }
    // The queued load may have failed first and asked for a restart; this one worked.
    SaveState::PollRestartNeeded();
    if (coreState == CORE_NEXTFRAME || coreState == CORE_POWERDOWN) {
        coreState = CORE_RUNNING_CPU;
    }
    bridge->hadRuntimeError = false;
    __DisplaySetWasPaused();
    return true;
}

void System_AudioPushSamples(const int32_t *audio, int numSamples, float volume) {
    if (!audio || numSamples <= 0) return;
    std::lock_guard<std::mutex> lock(gAudioMutex);
    const size_t count = (size_t)numSamples * 2;
    const size_t start = gAudio.size();
    gAudio.resize(start + count);
    for (size_t i = 0; i < count; ++i) {
        const float v = (float)audio[i] * volume;
        gAudio[start + i] = (int16_t)std::clamp(v, -32768.0f, 32767.0f);
    }
    if (gAudio.size() > kMaxAudioSamples) {
        gAudio.erase(gAudio.begin(), gAudio.end() - (std::ptrdiff_t)kMaxAudioSamples);
    }
}

void rp_ppsspp_pause(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) bridge->paused = true;
}

void rp_ppsspp_resume(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) {
        bridge->paused = false;
        if (bridge->inited) {
            MemoryStick_SetState(PSP_MEMORYSTICK_STATE_INSERTED);
        }
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
void rp_ppsspp_set_analog(void *, float, float) {}
int rp_ppsspp_read_audio(void *, int16_t *, int) { return 0; }
void rp_ppsspp_run_frame(void *) {}
bool rp_ppsspp_had_runtime_error(void *) { return false; }
bool rp_ppsspp_copy_rgba(void *, uint8_t **, int *, int *, int *) { return false; }
bool rp_ppsspp_save_state(void *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    return false;
}
bool rp_ppsspp_load_state(void *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    return false;
}
void rp_ppsspp_pause(void *) {}
void rp_ppsspp_resume(void *) {}

#endif
