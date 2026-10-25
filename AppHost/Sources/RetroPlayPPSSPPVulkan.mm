// SPDX-License-Identifier: GPL-3.0-or-later
#import "RetroPlayPPSSPPVulkan.h"

#if RETROPLAY_HAS_PPSSPP

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

#include "Common/GPU/Vulkan/VulkanLoader.h"
#include "Common/GPU/Vulkan/VulkanContext.h"
#include "Common/GPU/Vulkan/VulkanPresentation.h"
#include "Common/GPU/Vulkan/VulkanRenderManager.h"
#include "Common/GPU/thin3d.h"
#include "Common/GPU/thin3d_create.h"
#include "Common/Thread/ThreadUtil.h"
#include "Core/Config.h"
#include "Core/System.h"
#include "GPU/Vulkan/VulkanUtil.h"

using namespace PPSSPP_VK;

// MoltenVK is linked statically, like PPSSPP's own App Store build. Its entry point gets a
// different C++ name here because PPSSPP keeps a function pointer called vkGetInstanceProcAddr.
extern "C" PFN_vkVoidFunction RetroPlayMoltenVKGetInstanceProcAddr(VkInstance instance, const char *name)
    __asm__("_vkGetInstanceProcAddr");
extern "C" PFN_vkVoidFunction RetroPlayMoltenVKGetDeviceProcAddr(VkDevice device, const char *name)
    __asm__("_vkGetDeviceProcAddr");

namespace {
/// PPSSPP's global Vulkan entry points, from the linked MoltenVK (what VulkanLoad() would
/// dlopen). Instance and device functions are loaded by VulkanContext from these.
bool loadMoltenVK() {
    vkGetInstanceProcAddr = RetroPlayMoltenVKGetInstanceProcAddr;
    vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)RetroPlayMoltenVKGetDeviceProcAddr;
    vkCreateInstance = (PFN_vkCreateInstance)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    vkEnumerateInstanceVersion = (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion");
    vkEnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    vkEnumerateInstanceLayerProperties = (PFN_vkEnumerateInstanceLayerProperties)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceLayerProperties");
    return vkCreateInstance && vkEnumerateInstanceExtensionProperties && vkEnumerateInstanceLayerProperties;
}
}  // namespace

/// A swapchain replacement: a ring of IOSurface-backed images (VK_EXT_metal_objects import).
/// QueuePresent fences the frame; a waiter thread hands the surface to the app once the GPU is
/// done with it. An image is reused only after two newer frames were shown and nothing (Core
/// Animation, an external display) still uses its surface, so a frame on screen is never
/// drawn over.
class RetroPlaySurfacePresentation final : public VulkanPresentation {
public:
    RetroPlaySurfacePresentation(RetroPlayVulkan::FrameSink sink, VkExtent2D extent)
        : sink_(std::move(sink)), extent_(extent), requested_(extent) {}

    ~RetroPlaySurfacePresentation() override { StopWaiter(); }

    bool Create(VulkanContext *vulkan) {
        VkDevice device = vulkan->GetDevice();
        images_.resize(kImageCount);
        for (Image &img : images_) {
            img = Image{};
            if (!CreateImage(vulkan, device, img)) {
                Destroy(vulkan);
                return false;
            }
        }
        shownSequence_ = 0;
        StartWaiter(vulkan);
        return true;
    }

    void Destroy(VulkanContext *vulkan) override {
        StopWaiter();
        VkDevice device = vulkan->GetDevice();
        for (Image &img : images_) {
            if (img.fence) {
                if (img.state == State::Pending) {
                    vkWaitForFences(device, 1, &img.fence, VK_TRUE, 1000ull * 1000 * 1000);
                }
                vkDestroyFence(device, img.fence, nullptr);
            }
            if (img.image) vkDestroyImage(device, img.image, nullptr);
            if (img.memory) vkFreeMemory(device, img.memory, nullptr);
            if (img.surface) CFRelease(img.surface);
        }
        images_.clear();
    }

    bool NeedsRecreate() const override {
        std::lock_guard<std::mutex> lock(requestMutex_);
        return requested_.width != extent_.width || requested_.height != extent_.height;
    }

    bool Recreate(VulkanContext *vulkan) override {
        Destroy(vulkan);
        {
            std::lock_guard<std::mutex> lock(requestMutex_);
            extent_ = requested_;
        }
#if DEBUG
        // `-RetroPlayPSPSlowPresent YES`: hold up the render thread for the first frames after
        // a rebuild, so the emulation thread runs ahead of it (for testing frame handover).
        if ([NSUserDefaults.standardUserDefaults boolForKey:@"RetroPlayPSPSlowPresent"]) slowAcquires_ = 4;
#endif
        return Create(vulkan);
    }

    void RequestExtent(VkExtent2D extent) {
        std::lock_guard<std::mutex> lock(requestMutex_);
        requested_ = extent;
    }

    VkResult AcquireNextImage(VulkanContext *, VkSemaphore, uint32_t *imageIndex) override {
#if DEBUG
        if (slowAcquires_ > 0) {
            slowAcquires_--;
            std::this_thread::sleep_for(std::chrono::milliseconds(60));
        }
#endif
        std::unique_lock<std::mutex> lock(mutex_);
        // Normally an image is free at once. If the screen holds on to every one (the app is
        // stalled), skip presenting this frame rather than block emulation.
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(50);
        while (true) {
            int best = -1;
            for (int i = 0; i < (int)images_.size(); i++) {
                const Image &img = images_[i];
                if (img.state != State::Free) continue;
                if (img.shownAt != 0 && shownSequence_ - img.shownAt < 2) continue;
                if (IOSurfaceIsInUse(img.surface)) continue;
                if (best < 0 || img.shownAt < images_[best].shownAt) best = i;
            }
            if (best >= 0) {
                images_[best].state = State::Acquired;
                *imageIndex = (uint32_t)best;
                return VK_SUCCESS;
            }
            if (cond_.wait_until(lock, deadline) == std::cv_status::timeout) {
                return VK_NOT_READY;
            }
        }
    }

    VkResult QueuePresent(VulkanContext *vulkan, VkQueue queue, uint32_t imageIndex, VkSemaphore) override {
        if (imageIndex >= images_.size()) return VK_ERROR_OUT_OF_DATE_KHR;
        Image &img = images_[imageIndex];
        VkDevice device = vulkan->GetDevice();
        vkResetFences(device, 1, &img.fence);
        // An empty submission's fence signals once everything submitted before it (this frame)
        // has finished on the GPU.
        VkResult res = vkQueueSubmit(queue, 0, nullptr, img.fence);
        std::lock_guard<std::mutex> lock(mutex_);
        if (res != VK_SUCCESS) {
            img.state = State::Free;
            cond_.notify_all();
            return res;
        }
        img.state = State::Pending;
        pending_.push_back(imageIndex);
        cond_.notify_all();
        return VK_SUCCESS;
    }

    uint32_t GetImageCount() const override { return (uint32_t)images_.size(); }
    VkImage GetImage(uint32_t index) const override { return images_[index].image; }
    VkExtent2D GetExtent() const override { return extent_; }
    VkFormat GetFormat() const override { return VK_FORMAT_B8G8R8A8_UNORM; }
    VkImageLayout GetPresentLayout() const override { return VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL; }

    // There's no presentation engine to hand semaphores to: the acquire semaphore is never
    // signaled and the render-complete one is never waited on, so neither may reach the queue.
    // Ordering comes from the single queue and the present fence.
    void PrepareSubmit(VkSubmitInfo &submitInfo) override {
        submitInfo.waitSemaphoreCount = 0;
        submitInfo.pWaitSemaphores = nullptr;
        submitInfo.pWaitDstStageMask = nullptr;
        submitInfo.signalSemaphoreCount = 0;
        submitInfo.pSignalSemaphores = nullptr;
    }

private:
    static constexpr int kImageCount = 5;

    enum class State { Free, Acquired, Pending, Shown };

    struct Image {
        IOSurfaceRef surface = nullptr;
        VkImage image = VK_NULL_HANDLE;
        VkDeviceMemory memory = VK_NULL_HANDLE;
        VkFence fence = VK_NULL_HANDLE;
        State state = State::Free;
        uint64_t shownAt = 0;  // shownSequence_ when it was last handed to the app; 0 = never
    };

    bool CreateImage(VulkanContext *vulkan, VkDevice device, Image &img) {
        const int width = (int)extent_.width;
        const int height = (int)extent_.height;
        NSDictionary *props = @{
            (id)kIOSurfaceWidth: @(width),
            (id)kIOSurfaceHeight: @(height),
            (id)kIOSurfaceBytesPerElement: @4,
            (id)kIOSurfaceBytesPerRow: @(IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, (size_t)width * 4)),
            (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        };
        img.surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        if (!img.surface) {
            std::fprintf(stderr, "RetroPlay: IOSurfaceCreate %dx%d failed\n", width, height);
            return false;
        }

        VkImportMetalIOSurfaceInfoEXT import{ VK_STRUCTURE_TYPE_IMPORT_METAL_IO_SURFACE_INFO_EXT };
        import.ioSurface = img.surface;
        VkImageCreateInfo info{ VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
        info.pNext = &import;
        info.imageType = VK_IMAGE_TYPE_2D;
        info.format = VK_FORMAT_B8G8R8A8_UNORM;
        info.extent = { extent_.width, extent_.height, 1 };
        info.mipLevels = 1;
        info.arrayLayers = 1;
        info.samples = VK_SAMPLE_COUNT_1_BIT;
        info.tiling = VK_IMAGE_TILING_OPTIMAL;
        info.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT |
                     VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        if (vkCreateImage(device, &info, nullptr, &img.image) != VK_SUCCESS) return false;

        // The texture lives in the IOSurface, but Vulkan still wants memory bound to the image.
        VkMemoryRequirements req;
        vkGetImageMemoryRequirements(device, img.image, &req);
        VkMemoryAllocateInfo alloc{ VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
        alloc.allocationSize = req.size;
        VkMemoryDedicatedAllocateInfoKHR dedicated{ VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO_KHR };
        if (vulkan->Extensions().KHR_dedicated_allocation) {
            dedicated.image = img.image;
            alloc.pNext = &dedicated;
        }
        if (!vulkan->MemoryTypeFromProperties(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &alloc.memoryTypeIndex)) return false;
        if (vkAllocateMemory(device, &alloc, nullptr, &img.memory) != VK_SUCCESS) return false;
        if (vkBindImageMemory(device, img.image, img.memory, 0) != VK_SUCCESS) return false;

        VkFenceCreateInfo fenceInfo{ VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
        return vkCreateFence(device, &fenceInfo, nullptr, &img.fence) == VK_SUCCESS;
    }

    void StartWaiter(VulkanContext *vulkan) {
        stopWaiter_ = false;
        VkDevice device = vulkan->GetDevice();
        waiter_ = std::thread([this, device] { WaiterLoop(device); });
    }

    void StopWaiter() {
        if (!waiter_.joinable()) return;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            stopWaiter_ = true;
            cond_.notify_all();
        }
        waiter_.join();
    }

    /// Hands finished frames to the app in submission order.
    void WaiterLoop(VkDevice device) {
        SetCurrentThreadName("RPPresentWaiter");
        std::unique_lock<std::mutex> lock(mutex_);
        while (true) {
            cond_.wait(lock, [this] { return stopWaiter_ || !pending_.empty(); });
            if (pending_.empty()) return;  // stopping, nothing left
            const uint32_t index = pending_.front();
            VkFence fence = images_[index].fence;
            lock.unlock();
            VkResult res;
            do {
                res = vkWaitForFences(device, 1, &fence, VK_TRUE, 100ull * 1000 * 1000);
            } while (res == VK_TIMEOUT && !stopWaiter_);
            lock.lock();
            pending_.pop_front();
            Image &img = images_[index];
            if (res != VK_SUCCESS) {
                img.state = State::Free;
                cond_.notify_all();
                continue;
            }
            for (Image &other : images_) {
                if (other.state == State::Shown) other.state = State::Free;
            }
            img.state = State::Shown;
            img.shownAt = ++shownSequence_;
            IOSurfaceRef surface = img.surface;
            CFRetain(surface);
            lock.unlock();
            if (sink_) sink_((void *)surface);
            CFRelease(surface);
            lock.lock();
            cond_.notify_all();
        }
    }

    RetroPlayVulkan::FrameSink sink_;
    VkExtent2D extent_;
    mutable std::mutex requestMutex_;
    VkExtent2D requested_;

    std::vector<Image> images_;
    std::mutex mutex_;
    std::condition_variable cond_;
    std::deque<uint32_t> pending_;
    uint64_t shownSequence_ = 0;
    bool stopWaiter_ = false;
    std::thread waiter_;
#if DEBUG
    std::atomic<int> slowAcquires_{0};
#endif
};

namespace RetroPlayVulkan {

GraphicsContext::GraphicsContext(FrameSink sink, int width, int height)
    : sink_(std::move(sink)), width_(width), height_(height) {}

GraphicsContext::~GraphicsContext() {
    ShutdownAPI();
}

void *GraphicsContext::GetAPIContext() { return vulkan_; }

bool GraphicsContext::InitAPI(void *, std::string *, std::string *errorMessage) {
    if (vulkan_) return true;
    init_glslang();

    if (!loadMoltenVK()) {
        *errorMessage = "MoltenVK entry points missing";
        return false;
    }

    vulkan_ = new VulkanContext();
    VulkanContext::CreateInfo info{};
    InitVulkanCreateInfoFromConfig(&info);
    info.app_name = "RetroPlay";
    if (vulkan_->CreateInstance(info) != VK_SUCCESS) {
        *errorMessage = "Vulkan instance: " + vulkan_->InitError();
        ShutdownAPI();
        return false;
    }
    const int device = vulkan_->GetBestPhysicalDevice();
    if (device < 0) {
        *errorMessage = "No Vulkan device";
        ShutdownAPI();
        return false;
    }
    if (vulkan_->CreateDevice(device, { VK_EXT_METAL_OBJECTS_EXTENSION_NAME }) != VK_SUCCESS) {
        *errorMessage = "Vulkan device: " + vulkan_->InitError();
        ShutdownAPI();
        return false;
    }
    bool hasMetalObjects = false;
    for (const char *ext : vulkan_->GetDeviceExtensionsEnabled()) {
        if (!strcmp(ext, VK_EXT_METAL_OBJECTS_EXTENSION_NAME)) hasMetalObjects = true;
    }
    if (!hasMetalObjects || !vulkan_->ChooseGraphicsQueueWithoutSurface()) {
        *errorMessage = hasMetalObjects ? "No Vulkan graphics queue" : "MoltenVK lacks VK_EXT_metal_objects";
        ShutdownAPI();
        return false;
    }
    deviceName_ = vulkan_->GetPhysicalDeviceProperties(device).properties.deviceName;

    auto presentation = std::make_unique<RetroPlaySurfacePresentation>(sink_, VkExtent2D{ (uint32_t)width_, (uint32_t)height_ });
    if (!presentation->Create(vulkan_)) {
        *errorMessage = "Could not create IOSurface images";
        ShutdownAPI();
        return false;
    }
    presentation_ = presentation.get();
    vulkan_->SetPresentation(std::move(presentation));

    const bool useRenderThread = g_Config.bRenderMultiThreading && g_Config.iInflightFrames != 1;
    draw_ = Draw::T3DCreateVulkanContext(vulkan_, useRenderThread);
    if (!draw_ || !draw_->CreatePresets()) {
        *errorMessage = "Vulkan presets failed";
        ShutdownAPI();
        return false;
    }
    SetGPUBackend(GPUBackend::VULKAN, deviceName_);
    // The frames-in-flight count must be set before the backbuffers are first made: the render
    // manager applies a pending count only when it (re)creates them. Set after, as PPSSPP's
    // windowed frontends do, the count would change (from the default 3) at the first
    // resolution change instead, in the middle of BeginFrame, which then works on a different
    // frame than the rest of the frame records into. That frame's descriptor sets are cleared
    // while the render thread still encodes them: MoltenVK crashes on a null set at submit.
    auto *renderManager = (VulkanRenderManager *)draw_->GetNativeObject(Draw::NativeObject::RENDER_MANAGER);
    renderManager->SetInflightFrames(g_Config.iInflightFrames);
    draw_->HandleEvent(Draw::Event::GOT_BACKBUFFER, width_, height_);
    return true;
}

void GraphicsContext::SetOutputSize(int width, int height) {
    if (width == width_ && height == height_) return;
    width_ = width;
    height_ = height;
    if (presentation_) presentation_->RequestExtent(VkExtent2D{ (uint32_t)width, (uint32_t)height });
    // The images are rebuilt inside the next BeginFrame; the frame count must not change there.
    std::fprintf(stderr, "RetroPlay: PSP output %dx%d, %d frames in flight (now frame %d)\n",
                 width, height, vulkan_ ? vulkan_->GetInflightFrames() : 0, vulkan_ ? vulkan_->GetCurFrame() : -1);
}

void GraphicsContext::ShutdownAPI() {
    if (!vulkan_) return;
    if (draw_) {
        draw_->HandleEvent(Draw::Event::LOST_BACKBUFFER, vulkan_->GetBackbufferWidth(), vulkan_->GetBackbufferHeight());
    }
    delete draw_;
    draw_ = nullptr;
    vulkan_->WaitUntilQueueIdle();
    if (presentation_) {
        presentation_->Destroy(vulkan_);
        vulkan_->SetPresentation(nullptr);
        presentation_ = nullptr;
    }
    vulkan_->DestroyDevice();
    vulkan_->DestroyInstance();
    delete vulkan_;
    vulkan_ = nullptr;
    finalize_glslang();
}

}  // namespace RetroPlayVulkan

#endif
