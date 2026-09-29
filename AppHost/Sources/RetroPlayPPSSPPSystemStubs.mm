// SPDX-License-Identifier: GPL-3.0-or-later
// Host System_* / iOS glue stubs so libPPSSPP.a can link inside RetroPlay.
// Modeled on upstream headless stubs + minimal iOS symbols.

#if RETROPLAY_HAS_PPSSPP

#include <string>
#include <string_view>
#include <vector>
#include <functional>

#include "Common/System/System.h"
#include "Common/System/NativeApp.h"
#include "Common/System/Request.h"
#include "Common/GPU/GraphicsContext.h"
#include "Common/Audio/AudioBackend.h"

void System_Toast(std::string_view) {}
void System_Notify(SystemNotification) {}
void System_Vibrate(int) {}
void System_LaunchUrl(LaunchUrlType, std::string_view) {}

std::string System_GetProperty(SystemProperty) { return ""; }
std::vector<std::string> System_GetPropertyStringVec(SystemProperty) { return {}; }
int64_t System_GetPropertyInt(SystemProperty prop) {
    if (prop == SYSPROP_SYSTEMVERSION) return 18;
    return -1;
}
float System_GetPropertyFloat(SystemProperty) { return -1.0f; }
extern "C" bool rp_ppsspp_reports_system_headless(void);

bool System_GetPropertyBool(SystemProperty prop) {
    switch (prop) {
    case SYSPROP_IS_HEADLESS:
        // Official iOS and libretro return false here. With true, __PPGeInit skips
        // ppge_atlas.zim and SAVEDATA dialog labels and button icons never draw.
        return rp_ppsspp_reports_system_headless();
    case SYSPROP_CAN_JIT: return false;  // App Store path
    default: return false;
    }
}

bool System_MakeRequest(SystemRequestType, int, const std::string &, const std::string &, int64_t, int64_t) {
    return false;
}
void System_AskForPermission(SystemPermission) {}
PermissionStatus System_GetPermissionStatus(SystemPermission) { return PERMISSION_STATUS_GRANTED; }
std::vector<std::string> System_GetCameraDeviceList() { return {}; }

AudioBackend *System_CreateAudioBackend() { return nullptr; }

void System_PostUIMessage(UIMessage, std::string_view) {}
void System_RunOnMainThread(std::function<void()>) {}
void System_AudioGetDebugStats(char *buf, size_t bufSize) { if (buf && bufSize) buf[0] = '\0'; }
void System_AudioClear() {}
// System_AudioPushSamples lives in RetroPlayPPSSPPBridge.mm (feeds RetroPlay audio).

bool NativeSaveSecret(std::string_view, std::string_view) { return false; }
std::string NativeLoadSecret(std::string_view) { return ""; }

void NativeFrame(GraphicsContext *) {}
void NativeResized() {}

// iOS ViewController glue referenced by linked PPSSPP UI bits.
void bindDefaultFBO() {}
void *sharedViewController = nullptr;  // typed as id in upstream; unused in headless path
void copyDeepLinkForPath(std::string_view) {}

#endif  // RETROPLAY_HAS_PPSSPP
