# PPSSPP (PlayStation Portable)

RetroPlay's PSP core is [PPSSPP](https://www.ppsspp.org) ([hrydgard/ppsspp](https://github.com/hrydgard/ppsspp),
GPL-2.0-or-later). The exact revision and submodule states are in [`SOURCES.md`](SOURCES.md).

- CPU: IR interpreter (`CPUCore = 2`), no JIT, as iOS requires. See `PPSSPPDefaults`.
- GPU: PPSSPP's Vulkan backend on [MoltenVK](https://github.com/KhronosGroup/MoltenVK) (linked
  statically, like PPSSPP's own App Store build), rendering into IOSurfaces that the app shows
  directly. The software renderer remains as a fallback (see "GPU rendering" below).

## Build

1. `App/Vendor/fetch-core-sources.sh` checks out PPSSPP with its submodules into `External/` (git-ignored).
2. Build for `iphoneos` with PPSSPP's CMake iOS toolchain
   (`cmake -DCMAKE_TOOLCHAIN_FILE=./cmake/Toolchains/ios.cmake -DIOS_PLATFORM=OS …`, see the
   [PPSSPP build instructions](https://github.com/hrydgard/ppsspp/wiki/Build-instructions)) and
   merge the static libraries (Core, dependencies and the prebuilt FFmpeg) into one.
3. Package it with `PPSSPP_DEVICE_LIB=… PPSSPP_SIM_LIB=… PPSSPP_HEADERS=… App/Vendor/build-ppsspp-ios.sh`,
   which writes `App/Vendor/Output/PPSSPP.xcframework`.

PPSSPP's prebuilt FFmpeg libraries are device-only; a Simulator build needs FFmpeg rebuilt for
the Simulator.

## GPU rendering

`AppHost/Sources/RetroPlayPPSSPPVulkan.mm` creates the Vulkan instance and device on MoltenVK
and plugs a `VulkanPresentation` (PPSSPP's hook for hosts without a swapchain, the same one its
libretro core uses) into `VulkanContext`. Instead of swapchain images it hands PPSSPP a ring of
five BGRA IOSurfaces, imported as `VkImage`s with `VK_EXT_metal_objects`. When PPSSPP presents
a frame, a fence on the queue marks it done; a waiter thread then passes the surface to the
app's `VideoFrameStore`, and `GameScreenView` puts it straight into `CALayer.contents` on the
phone and on an external display. No frame is ever read back to the CPU. A surface is drawn
into again only after two newer frames were shown and `IOSurfaceIsInUse` is false.

- **Resolution.** PPSSPP renders at 480×272 × N and the presented image is that size; Core
  Animation scales it on screen (Smooth Screen picks linear or nearest). N is the pause menu's
  Resolution option, or for Auto the picture's on-screen size in pixels (largest screen showing
  it) divided by 480×272, rounded, at most 5 (`PSPRenderResolution`). Changes apply between
  frames (`rp_ppsspp_set_render_scale`): PPSSPP rebuilds the IOSurface ring inside its next
  `BeginFrame`, after draining the render thread and the queue.
- **Frames in flight.** The host sets PPSSPP's frames-in-flight count (2) before the first
  `GOT_BACKBUFFER`, so it is applied at init. Set afterwards (as PPSSPP's windowed frontends do), the
  render manager would switch from its default 3 at the first resolution change, inside
  `BeginFrame`, and the rest of that frame would record into another frame's slot: its fence and
  descriptor sets got out of step with the render thread, and MoltenVK crashed on a null
  descriptor set in `vkQueueSubmit` (debug builds can force the timing with
  `-RetroPlayPSPSlowPresent YES`, which holds up the render thread after a rebuild).
- **Host frame** (`hardwareFrame` in the bridge), as PPSSPP's EmuScreen does it: `BeginFrame`,
  savestate work, `BeginHostFrame`, `PSP_RunLoopWhileState`, copy the display framebuffer to the
  presented image, `EndFrame`, `g_frameTiming.PostSubmit()` (PPSSPP's real-time wait), `Present`.
  Save and load states run inside such a frame without running the CPU.
- **Shader cache.** PPSSPP writes `<disc ID>.vkshadercache` only from `GPU_Vulkan`'s destructor,
  which an iOS app rarely reaches. The bridge also saves it when the game pauses (menu,
  backgrounding), when it quits, and every 30 s of play, so the next launch builds its pipelines
  up front instead of stuttering through them.
- **Config.** Texture upscaling off (CPU work without a JIT), no post-processing shaders, 16:9
  crop off, stretch to the presented image, nearest output filter (the image is 1:1).
- **Fallback.** If MoltenVK can't start (or lacks `VK_EXT_metal_objects`), the game runs on the
  software renderer as before. Debug builds can force it with `-RetroPlayPSPSoftwareGPU YES`
  for comparisons.
- **Why Vulkan, not OpenGL ES.** PPSSPP's official iOS build defaults to Vulkan on MoltenVK;
  Apple deprecated OpenGL ES (iOS 12) and implements it on Metal anyway; PPSSPP's GL backend
  needs its own render thread with an EAGL context and a CVOpenGLESTextureCache round trip to
  reach an IOSurface, while Vulkan's pluggable presentation renders into IOSurfaces directly.
  The GLES path was not built for a side-by-side measurement (the Simulator emulates GLES on
  Metal, so its numbers wouldn't carry over to a phone).

`App/Vendor/fetch-moltenvk.sh` downloads MoltenVK (pinned release, checksums checked) and
writes `Output/MoltenVK.xcframework`.

## Integration

- C++ bridge: `AppHost/Sources/RetroPlayPPSSPPBridge.{h,mm}`; Swift driver
  `AppHost/Sources/PPSSPPNativeDriver.swift` (`RETROPLAY_HAS_PPSSPP`).
- Header search paths expect the PPSSPP checkout at `External/ppsspp` (a folder or a link to one).
- PPSSPP's runtime data (PPGe atlas, VFPU tables, `compat.ini`, …) is bundled from
  `AppHost/Supporting/assets/` (see `SOURCE.md` there).

## Troubleshooting a black screen

1. After `PSP_Init`, and after every host frame, the host must set `coreState = CORE_RUNNING_CPU`
   (PPSSPP leaves `CORE_NEXTFRAME`), as PPSSPP's own frontends do; otherwise frames don't advance.
2. Software-GPU display buffers are often 16-bit: export with `ConvertBufferToScreenshot`, not a raw
   RGBA copy. `GetOutputFramebuffer` fails until the game calls `sceDisplaySetFrameBuf`.
3. In the Simulator, `vm_remap failed` / `Failed at view N` lines are memory-map probing; if init
   completes they're harmless.
