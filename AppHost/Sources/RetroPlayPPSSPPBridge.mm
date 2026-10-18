// SPDX-License-Identifier: GPL-3.0-or-later
#import "RetroPlayPPSSPPBridge.h"
#import "RetroPlayPPSSPPVulkan.h"
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
#include "Core/HW/Display.h"
#include "Core/FrameTiming.h"
#include <algorithm>
#include <fstream>
#include <mutex>
#include <vector>
#include "GPU/Common/GPUDebugInterface.h"
#include "GPU/GPUCommon.h"
#include "GPU/ge_constants.h"
#include "Common/GPU/thin3d.h"
#include "Common/System/Display.h"
#include "Common/File/FileUtil.h"
#include "Core/ELF/ParamSFO.h"
#include "GPU/Vulkan/GPU_Vulkan.h"
#include <atomic>
#include <memory>

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

    /// Hardware rendering (Vulkan on MoltenVK). Null when the software renderer is used.
    std::unique_ptr<RetroPlayVulkan::GraphicsContext> graphics;
    rp_ppsspp_frame_callback frameCallback = nullptr;
    void *frameCallbackContext = nullptr;
    /// Internal resolution the host asked for (multiple of 480×272); applied between frames.
    std::atomic<int> requestedScale{2};
    int appliedScale = 0;
    int framesSinceCacheSave = 0;
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

/// Present the PSP picture 1:1 into an image exactly the internal render size; Core Animation
/// scales that on screen (the app's Smooth Screen picks nearest or linear), so PPSSPP's own
/// output pass is a straight copy with no filtering, cropping or letterboxing.
void applyHardwareRenderingConfig() {
    for (DisplayLayoutConfig *layout : { &g_Config.displayLayoutLandscape, &g_Config.displayLayoutPortrait }) {
        layout->iDisplayFilter = SCALE_NEAREST;
        layout->bDisplayStretch = true;
        layout->fDisplayOffsetX = 0.5f;
        layout->fDisplayOffsetY = 0.5f;
        layout->fDisplayScale = 1.0f;
        layout->bDisplayIntegerScale = false;
        layout->fDisplayAspectRatio = 1.0f;
        layout->iInternalScreenRotation = ROTATION_LOCKED_HORIZONTAL;
        layout->bEnableCardboardVR = false;
    }
    g_Config.bDisplayCropTo16x9 = false;
    g_Config.vPostShaderNames.clear();
    // Texture upscaling runs on the CPU (no JIT on iOS): far too slow to be worth it.
    g_Config.iTexScalingLevel = 1;
    g_Config.bTexHardwareScaling = false;
    g_Config.bShaderCache = true;
}

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
    // Software rendering only when the GPU path is unavailable. PPGeDrawCurrentText uses 512
    // texture windows only when this flag is set; without it the software sampler clamps the
    // 2048-wide atlas and SAVEDATA dialog text draws as garbage (the GPU samples it fine).
    g_Config.bSoftwareRendering = !bridge->graphics && rp_ppsspp_enables_software_renderer();
    if (bridge->graphics) {
        applyHardwareRenderingConfig();
        // The host picks the resolution (Options, or Auto from the screen), not a game ini.
        g_Config.iInternalResolution = bridge->appliedScale;
    }
    // Heavy scenes (LEGO Batman's busy levels): when a frame runs late, skip drawing the next
    // one (at most 3 in a row) so the game keeps full speed instead of slowing down. The
    // software renderer is most of a frame's cost, and a skipped frame skips it. Auto
    // frameskip needs buffer effects on.
    g_Config.bSkipBufferEffects = false;
    g_Config.iFrameSkip = 3;
    g_Config.bAutoFrameSkip = true;
#if DEBUG
    // Measuring: `-RetroPlayPSPNoFrameskip YES` turns it off for a before/after comparison.
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"RetroPlayPSPNoFrameskip"]) {
        g_Config.iFrameSkip = 0;
        g_Config.bAutoFrameSkip = false;
    }
#endif
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

/// Opaque black 480×272 RGBA, malloc'd like packRGBAFromDebugBuffer's output.
bool blackFrame(uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    const int w = 480, h = 272;
    uint8_t *out = (uint8_t *)std::malloc((size_t)w * h * 4);
    if (!out) return false;
    for (size_t i = 0; i < (size_t)w * h; ++i) {
        out[i * 4 + 0] = 0;
        out[i * 4 + 1] = 0;
        out[i * 4 + 2] = 0;
        out[i * 4 + 3] = 0xFF;
    }
    *outBytes = out;
    *outWidth = w;
    *outHeight = h;
    *outStrideBytes = w * 4;
    return true;
}
}  // namespace

namespace {
/// PSP first (it saves the shader cache and frees GPU objects), then the Vulkan device.
void shutDownGame(BridgeState *bridge) {
    if (bridge->inited) {
        PSP_Shutdown(true);
        NativeShutdown();
        bridge->inited = false;
    }
    if (bridge->graphics) {
        bridge->graphics->ShutdownAPI();
        bridge->graphics.reset();
    }
}

int clampScale(int scale) { return std::clamp(scale, 1, 8); }

// GPU_Vulkan saves its shader/pipeline cache only from its destructor, at a clean shutdown,
// which an iOS app rarely gets (it's suspended, then killed). Its SaveCache is private; an
// explicit template instantiation may name a private member, which lets the bridge call it
// without patching PPSSPP.
void saveVulkanCacheTo(GPU_Vulkan *gpu, const Path &path);
template <void (GPU_Vulkan::*Save)(const Path &)>
struct VulkanCacheSaver {
    friend void saveVulkanCacheTo(GPU_Vulkan *gpu, const Path &path) { (gpu->*Save)(path); }
};
template struct VulkanCacheSaver<&GPU_Vulkan::SaveCache>;

/// Writes the game's `.vkshadercache` (shader and pipeline keys, a few hundred KB at most) so
/// the next launch compiles them up front instead of stuttering through first use. Between
/// frames on the emulation thread only. Written aside and renamed, so a kill never leaves a
/// torn file.
void saveShaderCache(BridgeState *bridge) {
    if (!bridge->graphics || !bridge->inited || !gpu || PSP_CoreParameter().gpuCore != GPUCORE_VULKAN) return;
    const std::string discID = g_paramSFO.GetDiscID();
    if (discID.empty()) return;
    const Path path = GetSysDirectory(DIRECTORY_APP_CACHE) / (discID + ".vkshadercache");
    const Path temp = GetSysDirectory(DIRECTORY_APP_CACHE) / (discID + ".vkshadercache.tmp");
    saveVulkanCacheTo(static_cast<GPU_Vulkan *>(gpu), temp);
    if (File::Exists(temp)) File::Rename(temp, path);
}

/// Host frames between shader cache saves while playing (about 30 s).
constexpr int kShaderCacheSaveFrames = 1800;

/// Hardware rendering unless the device can't (or, in Debug, `-RetroPlayPSPSoftwareGPU YES`).
void startGraphics(BridgeState *bridge) {
#if DEBUG
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"RetroPlayPSPSoftwareGPU"]) return;
#endif
    const int scale = clampScale(bridge->requestedScale.load());
    auto sink = [bridge](void *surface) {
        if (bridge->frameCallback) bridge->frameCallback(bridge->frameCallbackContext, surface);
    };
    auto graphics = std::make_unique<RetroPlayVulkan::GraphicsContext>(sink, 480 * scale, 272 * scale);
    std::string deviceName, error;
    if (!graphics->InitAPI(nullptr, &deviceName, &error)) {
        std::fprintf(stderr, "RetroPlay: PSP GPU rendering unavailable (%s); using the software renderer\n", error.c_str());
        return;
    }
    std::fprintf(stderr, "RetroPlay: PSP renders on %s (Vulkan), %dx internal\n", graphics->DeviceName().c_str(), scale);
    bridge->graphics = std::move(graphics);
    bridge->appliedScale = scale;
    g_Config.iInternalResolution = scale;
}

/// The render size follows the requested scale: PPSSPP renders at 480×272 × scale, and the
/// presented image is that size too.
void setRenderSize(int scale) {
    const int width = 480 * scale, height = 272 * scale;
    g_Config.iInternalResolution = scale;
    PSP_CoreParameter().pixelWidth = width;
    PSP_CoreParameter().pixelHeight = height;
    g_display.pixel_xres = width;
    g_display.pixel_yres = height;
    g_display.dp_xres = width;
    g_display.dp_yres = height;
}

void applyRequestedScale(BridgeState *bridge) {
    const int scale = clampScale(bridge->requestedScale.load());
    if (!bridge->graphics || scale == bridge->appliedScale) return;
    bridge->appliedScale = scale;
    setRenderSize(scale);
    std::fprintf(stderr, "RetroPlay: PSP internal resolution %dx (%dx%d)\n", scale, 480 * scale, 272 * scale);
    bridge->graphics->SetOutputSize(480 * scale, 272 * scale);
    if (gpu) {
        gpu->NotifyDisplayResized();
        gpu->NotifyRenderResized(g_Config.displayLayoutLandscape);
    }
}

/// One host frame on the GPU, shaped like PPSSPP's own EmuScreen: savestate work, emulation,
/// then the display framebuffer copied into the presented image.
template <typename Work>
void hardwareFrame(BridgeState *bridge, Work &&work, bool runEmulation) {
    Draw::DrawContext *draw = bridge->graphics->GetDrawContext();
    const DisplayLayoutConfig &layout = g_Config.displayLayoutLandscape;
    __DisplaySetDisplayLayoutConfig(layout);
    draw->BeginFrame(Draw::DebugFlags::NONE);
    work();
    if (gpu) gpu->BeginHostFrame(layout);
    if (runEmulation) PSP_RunLoopWhileState();
    if (gpu) {
        gpu->PrepareCopyDisplayToOutput(layout);
        gpu->EndHostFrame();
    }
    draw->BindFramebufferAsRenderTarget(nullptr, { Draw::RPAction::CLEAR, Draw::RPAction::CLEAR, Draw::RPAction::CLEAR }, "BackBuffer");
    if (gpu) gpu->CopyDisplayToOutput(layout);
    draw->EndFrame();
    // PPSSPP keeps the game at real-time speed itself: it defers the wait for a frame's time
    // slot to the frontend, after the frame is submitted. Without this the host's own ticking
    // set the pace, one display flip per tick, which runs games that flip less than every
    // vblank (30 fps titles) or skip frames (auto frameskip) too fast.
    g_frameTiming.PostSubmit();
    draw->Present(g_frameTiming.PresentMode());
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
    shutDownGame(bridge);
    delete bridge;
}

bool rp_ppsspp_load(void *bridgePtr, const char *gamePath, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !gamePath) {
        setError(errorOut, errorOutLen, "null bridge or path");
        return false;
    }

    shutDownGame(bridge);

    const char *argv[] = { "RetroPlay", gamePath };
    CommandLineOptions cmd{};
    const std::string ppgeAssets = retroPlayBundledPPSSPPAssetsDirectory();
    const char *externalDir = ppgeAssets.empty() ? bridge->saveDir.c_str() : ppgeAssets.c_str();
    NativeInit(2, argv, cmd, bridge->saveDir.c_str(), externalDir, bridge->cacheDir.c_str());
    startGraphics(bridge);
    applyRetroPlayHostConfig(bridge);

    g_Config.iCpuCore = (int)CPUCore::IR_INTERPRETER;
    g_Config.bEnableSound = true;
    {
        std::lock_guard<std::mutex> lock(gAudioMutex);
        gAudio.clear();
    }

    CoreParameter param{};
    param.cpuCore = CPUCore::IR_INTERPRETER;
    param.gpuCore = bridge->graphics ? GPUCORE_VULKAN : GPUCORE_SOFTWARE;
    if (bridge->graphics) {
        param.graphicsContext = bridge->graphics.get();
        setRenderSize(bridge->appliedScale);
        param.pixelWidth = param.renderWidth = 480 * bridge->appliedScale;
        param.pixelHeight = param.renderHeight = 272 * bridge->appliedScale;
    }
    param.enableSound = true;
    param.headLess = true;
    param.fileToStart = Path(std::string(gamePath));
    param.startBreak = false;

    std::string error;
    BootState state = PSP_Init(param, &error);
    if (state != BootState::Complete) {
        NativeShutdown();
        if (bridge->graphics) {
            bridge->graphics->ShutdownAPI();
            bridge->graphics.reset();
        }
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
    if (bridge->graphics) {
        applyRequestedScale(bridge);
        hardwareFrame(bridge, [] {}, true);
        if (++bridge->framesSinceCacheSave >= kShaderCacheSaveFrames) {
            bridge->framesSinceCacheSave = 0;
            saveShaderCache(bridge);
        }
    } else {
        PSP_RunLoopWhileState();
        // PPSSPP's deferred real-time wait; see hardwareFrame.
        g_frameTiming.PostSubmit();
    }
#if DEBUG
    // Speed log for measuring: vps is emulated vblanks per second (60 = full speed), fps the
    // frames the game drew per second.
    static int perfTicks = 0;
    if (++perfTicks % 120 == 0) {
        float vps = 0, fps = 0, actual = 0;
        __DisplayGetFPS(&vps, &fps, &actual);
        std::fprintf(stderr, "RP_PERF vps=%.1f fps=%.1f actual=%.1f\n", vps, fps, actual);
    }
#endif
    // Match libretro: after a full host frame, put the CPU back to running for the next tick.
    if (!resumeCPUIfNeeded()) {
        bridge->hadRuntimeError = true;
    }
}

void rp_ppsspp_set_fast_forward(void *bridgePtr, bool enabled) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->inited) return;
    PSP_CoreParameter().fastForward = enabled;
}

bool rp_ppsspp_had_runtime_error(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    return bridge ? bridge->hadRuntimeError : false;
}

void rp_ppsspp_set_frame_callback(void *bridgePtr, rp_ppsspp_frame_callback callback, void *context) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge) return;
    bridge->frameCallback = callback;
    bridge->frameCallbackContext = context;
}

void rp_ppsspp_set_render_scale(void *bridgePtr, int scale) {
    if (auto *bridge = asBridge(bridgePtr)) bridge->requestedScale = clampScale(scale);
}

bool rp_ppsspp_uses_gpu(void *bridgePtr) {
    auto *bridge = asBridge(bridgePtr);
    return bridge && bridge->graphics != nullptr;
}

bool rp_ppsspp_copy_rgba(void *bridgePtr, uint8_t **outBytes, int *outWidth, int *outHeight, int *outStrideBytes) {
    auto *bridge = asBridge(bridgePtr);
    // On the GPU, frames reach the app as IOSurfaces through the frame callback instead.
    if (!bridge || !bridge->inited || bridge->graphics || !outBytes || !outWidth || !outHeight || !outStrideBytes) {
        return false;
    }
    *outBytes = nullptr;

    // Only the display framebuffer is shown, never raw VRAM: before the game sets up its
    // display (any boot without a resume save, e.g. a first launch or Restart from
    // Scratch) VRAM holds the game's own data in other formats, which showed as "static".
    // A game that turns the display off (sceDisplaySetFrameBuf with address 0, common on
    // loading screens) still gets a "valid" SoftGPU framebuffer at VRAM's base, which shows
    // as streaks of raw VRAM. A real PSP shows black: publish a black frame instead.
    PSPPointer<u8> topaddr;
    topaddr.ptr = 0;
    u32 linesize = 0;
    __DisplayGetFramebuf(&topaddr, &linesize, nullptr, 0);
    if (topaddr.ptr == 0 || linesize == 0) {
        return blackFrame(outBytes, outWidth, outHeight, outStrideBytes);
    }
    if (gpu) {
        GPUDebugBuffer buf;
        if (gpu->GetOutputFramebuffer(buf) && buf.GetData() != nullptr) {
            return packRGBAFromDebugBuffer(buf, outBytes, outWidth, outHeight, outStrideBytes);
        }
    }
    return false;
}


namespace {
bool saveState(BridgeState *bridge, const char *path, char *errorOut, size_t errorOutLen);
bool loadState(BridgeState *bridge, const char *path, char *errorOut, size_t errorOutLen);
}  // namespace

// On the GPU, savestate work runs inside a host frame, as PPSSPP's own EmuScreen does it, so
// framebuffer readbacks and resets have a frame to record into. The emulated CPU doesn't run.
bool rp_ppsspp_save_state(void *bridgePtr, const char *path, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->graphics || !bridge->inited) return saveState(bridge, path, errorOut, errorOutLen);
    bool ok = false;
    hardwareFrame(bridge, [&] { ok = saveState(bridge, path, errorOut, errorOutLen); }, false);
    return ok;
}

bool rp_ppsspp_load_state(void *bridgePtr, const char *path, char *errorOut, size_t errorOutLen) {
    auto *bridge = asBridge(bridgePtr);
    if (!bridge || !bridge->graphics || !bridge->inited) return loadState(bridge, path, errorOut, errorOutLen);
    bool ok = false;
    hardwareFrame(bridge, [&] { ok = loadState(bridge, path, errorOut, errorOutLen); }, false);
    return ok;
}

namespace {
bool saveState(BridgeState *bridge, const char *path, char *errorOut, size_t errorOutLen) {
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

bool loadState(BridgeState *bridge, const char *path, char *errorOut, size_t errorOutLen) {
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
}  // namespace

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

void rp_ppsspp_save_caches(void *bridgePtr) {
    if (auto *bridge = asBridge(bridgePtr)) {
        bridge->framesSinceCacheSave = 0;
        saveShaderCache(bridge);
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
void rp_ppsspp_set_fast_forward(void *, bool) {}
bool rp_ppsspp_copy_rgba(void *, uint8_t **, int *, int *, int *) { return false; }
void rp_ppsspp_set_frame_callback(void *, rp_ppsspp_frame_callback, void *) {}
void rp_ppsspp_set_render_scale(void *, int) {}
bool rp_ppsspp_uses_gpu(void *) { return false; }
bool rp_ppsspp_save_state(void *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    return false;
}
bool rp_ppsspp_load_state(void *, const char *, char *errorOut, size_t errorOutLen) {
    if (errorOut && errorOutLen) std::snprintf(errorOut, errorOutLen, "RETROPLAY_HAS_PPSSPP not set");
    return false;
}
void rp_ppsspp_save_caches(void *) {}
void rp_ppsspp_pause(void *) {}
void rp_ppsspp_resume(void *) {}

#endif
