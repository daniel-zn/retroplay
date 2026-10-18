// SPDX-License-Identifier: GPL-3.0-or-later
// PPSSPP's Vulkan backend on MoltenVK, rendering into IOSurfaces instead of a swapchain.
// Internal to the PPSSPP bridge (C++ only).
#pragma once

#if RETROPLAY_HAS_PPSSPP

#include <functional>
#include <string>

#include "Common/GPU/GraphicsContext.h"

class VulkanContext;
class RetroPlaySurfacePresentation;

namespace RetroPlayVulkan {

/// Called on a background thread once the GPU has finished a frame. The surface is retained
/// for the duration of the call only; retain it to keep it.
using FrameSink = std::function<void(void *ioSurface)>;

/// Owns the VkInstance/VkDevice (MoltenVK, linked statically), the thin3d draw context, and
/// the IOSurface presentation that replaces a swapchain: every frame PPSSPP "presents" lands in
/// one of a small ring of IOSurfaces that the app shows directly as layer contents, on the
/// phone and on an external display alike, with no CPU copy.
class GraphicsContext final : public ::GraphicsContext {
public:
    GraphicsContext(FrameSink sink, int width, int height);
    ~GraphicsContext() override;

    bool InitAPI(void *wnd, std::string *deviceName, std::string *errorMessage) override;
    void ShutdownAPI() override;
    void Resize() override {}
    void *GetAPIContext() override;
    Draw::DrawContext *GetDrawContext() override { return draw_; }

    /// Size of the presented image (the internal render size). Takes effect at the start of
    /// the next frame; call between frames on the emulation thread.
    void SetOutputSize(int width, int height);
    int OutputWidth() const { return width_; }
    int OutputHeight() const { return height_; }
    std::string DeviceName() const { return deviceName_; }

private:
    FrameSink sink_;
    int width_;
    int height_;
    std::string deviceName_;
    VulkanContext *vulkan_ = nullptr;
    RetroPlaySurfacePresentation *presentation_ = nullptr;  // owned by vulkan_
    Draw::DrawContext *draw_ = nullptr;
};

}  // namespace RetroPlayVulkan

#endif
