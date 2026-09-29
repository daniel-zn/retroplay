// SPDX-License-Identifier: GPL-3.0-or-later
#import "N64LibretroHost.h"

#import <TargetConditionals.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <OpenGLES/EAGL.h>
#import <Foundation/Foundation.h>

#include "libretro.h"

#include <algorithm>
#include <dlfcn.h>
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

// mupen64plus-next exports the libretro C API.
extern "C" {
unsigned retro_api_version(void);
void retro_init(void);
void retro_deinit(void);
void retro_get_system_info(struct retro_system_info *info);
void retro_get_system_av_info(struct retro_system_av_info *info);
void retro_set_environment(retro_environment_t);
void retro_set_video_refresh(retro_video_refresh_t);
void retro_set_audio_sample(retro_audio_sample_t);
void retro_set_audio_sample_batch(retro_audio_sample_batch_t);
void retro_set_input_poll(retro_input_poll_t);
void retro_set_input_state(retro_input_state_t);
bool retro_load_game(const struct retro_game_info *game);
void retro_unload_game(void);
void retro_run(void);
void retro_reset(void);
size_t retro_serialize_size(void);
bool retro_serialize(void *data, size_t size);
bool retro_unserialize(const void *data, size_t size);
void retro_set_controller_port_device(unsigned port, unsigned device);
void *retro_get_memory_data(unsigned id);
size_t retro_get_memory_size(unsigned id);
}

struct N64HostHandle {
    EAGLContext *context = nil;
    GLuint fbo = 0;
    GLuint colorRBO = 0;
    GLuint depthRBO = 0;
    int fbW = 640;
    int fbH = 480;
    int frameW = 640;
    int frameH = 480;
    struct retro_hw_render_callback hw {};
    bool hwValid = false;
    bool loaded = false;
    bool contextReady = false;
    bool hasFrame = false;
    enum retro_pixel_format pixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;

    uint32_t joypadMask = 0;
    int16_t stickX = 0;
    int16_t stickY = 0;

    std::vector<uint8_t> rgba;
    std::vector<uint8_t> readback;
    std::vector<uint8_t> romBytes;
    std::vector<int16_t> audio;
    double fps = 60.0;
    double sampleRate = 44100.0;
    std::string sramPath;
    std::vector<uint8_t> sramShadow;
    std::string systemDir;
    std::string saveDir;
    std::string lastVideoPath;
    // Defaults the core declares via SET_CORE_OPTIONS* / SET_VARIABLES.
    std::map<std::string, std::string> optionDefaults;
};

static N64HostHandle *gHost = nullptr;

// ~0.5 s of stereo audio; the emulation thread drains it after every frame.
static const size_t kMaxAudioSamples = 44100;

static void trimAudio(N64HostHandle *h) {
    if (h->audio.size() > kMaxAudioSamples) {
        h->audio.erase(h->audio.begin(), h->audio.end() - (std::ptrdiff_t)kMaxAudioSamples);
    }
}

static void audio_sample(int16_t left, int16_t right) {
    if (!gHost) return;
    gHost->audio.push_back(left);
    gHost->audio.push_back(right);
    trimAudio(gHost);
}

static size_t audio_sample_batch(const int16_t *data, size_t frames) {
    if (!gHost || !data) return frames;
    gHost->audio.insert(gHost->audio.end(), data, data + frames * 2);
    trimAudio(gHost);
    return frames;
}
static void input_poll(void) {}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (!gHost || port != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)(gHost->joypadMask & 0xFFFF);
        if (id <= RETRO_DEVICE_ID_JOYPAD_R3) return (gHost->joypadMask & (1u << id)) ? 1 : 0;
    }
    if (device == RETRO_DEVICE_ANALOG && index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
        if (id == RETRO_DEVICE_ID_ANALOG_X) return gHost->stickX;
        if (id == RETRO_DEVICE_ID_ANALOG_Y) return gHost->stickY;
    }
    return 0;
}

/// Map RetroPlay N64Input (m64p BUTTON bits) → libretro joypad bits (alternate_mapping layout).
static uint32_t mapN64ToJoypad(uint32_t n64) {
    uint32_t j = 0;
    auto set = [&](uint32_t n64bit, unsigned joyId) {
        if (n64 & n64bit) j |= (1u << joyId);
    };
    // dpad
    set(0x0001, RETRO_DEVICE_ID_JOYPAD_RIGHT);
    set(0x0002, RETRO_DEVICE_ID_JOYPAD_LEFT);
    set(0x0004, RETRO_DEVICE_ID_JOYPAD_DOWN);
    set(0x0008, RETRO_DEVICE_ID_JOYPAD_UP);
    set(0x0010, RETRO_DEVICE_ID_JOYPAD_START);
    set(0x0020, RETRO_DEVICE_ID_JOYPAD_SELECT); // L (alternate)
    set(0x2000, RETRO_DEVICE_ID_JOYPAD_L2);     // Z
    set(0x4000, RETRO_DEVICE_ID_JOYPAD_Y);      // B
    set(0x8000, RETRO_DEVICE_ID_JOYPAD_B);      // A
    set(0x0100, RETRO_DEVICE_ID_JOYPAD_R);      // C-Right
    set(0x0200, RETRO_DEVICE_ID_JOYPAD_L);      // C-Left
    set(0x0400, RETRO_DEVICE_ID_JOYPAD_A);      // C-Down
    set(0x0800, RETRO_DEVICE_ID_JOYPAD_X);      // C-Up
    set(0x1000, RETRO_DEVICE_ID_JOYPAD_R2);     // R
    return j;
}


// GLideN64 + glsm often bind FBO 0 as "default". On iOS/EAGL that is incomplete;
// remap 0 → our HW FBO so draws land where get_current_framebuffer points.
static void (*real_glBindFramebuffer)(GLenum target, GLuint framebuffer) = nullptr;
static void (*real_glBindFramebufferOES)(GLenum target, GLuint framebuffer) = nullptr;
static void RP_glBindFramebuffer(GLenum target, GLuint framebuffer) {
    if (framebuffer == 0 && gHost && gHost->fbo)
        framebuffer = gHost->fbo;
    if (real_glBindFramebuffer)
        real_glBindFramebuffer(target, framebuffer);
}
static void RP_glBindFramebufferOES(GLenum target, GLuint framebuffer) {
    if (framebuffer == 0 && gHost && gHost->fbo)
        framebuffer = gHost->fbo;
    if (real_glBindFramebufferOES)
        real_glBindFramebufferOES(target, framebuffer);
    else if (real_glBindFramebuffer)
        real_glBindFramebuffer(target, framebuffer);
}

static uintptr_t get_current_framebuffer(void) {
    return gHost ? (uintptr_t)gHost->fbo : 0;
}

static retro_proc_address_t get_proc_address(const char *sym) {
    if (!sym) return nullptr;
    if (!strcmp(sym, "glBindFramebuffer")) {
        if (!real_glBindFramebuffer)
            real_glBindFramebuffer = (void (*)(GLenum, GLuint))dlsym(RTLD_DEFAULT, "glBindFramebuffer");
        return (retro_proc_address_t)RP_glBindFramebuffer;
    }
    if (!strcmp(sym, "glBindFramebufferOES")) {
        if (!real_glBindFramebufferOES)
            real_glBindFramebufferOES = (void (*)(GLenum, GLuint))dlsym(RTLD_DEFAULT, "glBindFramebufferOES");
        if (!real_glBindFramebuffer)
            real_glBindFramebuffer = (void (*)(GLenum, GLuint))dlsym(RTLD_DEFAULT, "glBindFramebuffer");
        return (retro_proc_address_t)RP_glBindFramebufferOES;
    }
    void *p = dlsym(RTLD_DEFAULT, sym);
    return (retro_proc_address_t)p;
}

static void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (!gHost) return;
    if (data == nullptr) return; // dupe

    // Angrylion (and other software RDPs): CPU framebuffer
    if (data != RETRO_HW_FRAME_BUFFER_VALID) {
        if (!width || !height) return;
        const int w = (int)width;
        const int h = (int)height;
        gHost->frameW = w;
        gHost->frameH = h;
        gHost->rgba.resize((size_t)w * (size_t)h * 4);
        const uint8_t *src = (const uint8_t *)data;
        for (int y = 0; y < h; y++) {
            uint8_t *dst = gHost->rgba.data() + (size_t)y * (size_t)w * 4;
            const uint8_t *row = src + (size_t)y * pitch;
            if (gHost->pixelFormat == RETRO_PIXEL_FORMAT_XRGB8888) {
                for (int x = 0; x < w; x++) {
                    // XRGB little-endian: B G R X (or XRGB as bytes varies; libretro is 0x00RRGGBB in native)
                    uint32_t px = ((const uint32_t *)row)[x];
                    dst[x*4+0] = (px >> 16) & 0xff; // R
                    dst[x*4+1] = (px >> 8) & 0xff;  // G
                    dst[x*4+2] = px & 0xff;         // B
                    dst[x*4+3] = 0xff;
                }
            } else if (gHost->pixelFormat == RETRO_PIXEL_FORMAT_RGB565) {
                for (int x = 0; x < w; x++) {
                    uint16_t px = ((const uint16_t *)row)[x];
                    dst[x*4+0] = ((px >> 11) & 0x1f) * 255 / 31;
                    dst[x*4+1] = ((px >> 5) & 0x3f) * 255 / 63;
                    dst[x*4+2] = (px & 0x1f) * 255 / 31;
                    dst[x*4+3] = 0xff;
                }
            } else {
                // 0RGB1555
                for (int x = 0; x < w; x++) {
                    uint16_t px = ((const uint16_t *)row)[x];
                    dst[x*4+0] = ((px >> 10) & 0x1f) * 255 / 31;
                    dst[x*4+1] = ((px >> 5) & 0x1f) * 255 / 31;
                    dst[x*4+2] = (px & 0x1f) * 255 / 31;
                    dst[x*4+3] = 0xff;
                }
            }
        }
        gHost->hasFrame = true;
        return;
    }

    // HW path (GLideN64): read back the whole FBO (GLideN64 renders at the 640x480 screen size).
    if (!gHost->contextReady) return;
    [EAGLContext setCurrentContext:gHost->context];
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)gHost->fbo);
    const int w = gHost->fbW;
    const int h = gHost->fbH;
    const size_t stride = (size_t)w * 4;
    gHost->readback.resize(stride * (size_t)h);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, gHost->readback.data());
    gHost->rgba.resize(gHost->readback.size());
    // GL rows are bottom-up.
    for (int y = 0; y < h; y++) {
        memcpy(gHost->rgba.data() + (size_t)(h - 1 - y) * stride,
               gHost->readback.data() + (size_t)y * stride,
               stride);
    }
    gHost->frameW = w;
    gHost->frameH = h;
    gHost->hasFrame = true;
}

static void ensureDirs(N64HostHandle *h) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *sys = [docs stringByAppendingPathComponent:@"N64System"];
    NSString *save = [[docs stringByAppendingPathComponent:@"Saves"] stringByAppendingPathComponent:@"n64"];
    [[NSFileManager defaultManager] createDirectoryAtPath:sys withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:save withIntermediateDirectories:YES attributes:nil error:nil];
    h->systemDir = sys.fileSystemRepresentation;
    h->saveDir = save.fileSystemRepresentation;
}

static bool createGL(N64HostHandle *h) {
    h->context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!h->context) {
        h->context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    if (!h->context) {
        fprintf(stderr, "N64Host: EAGLContext failed\n");
        return false;
    }
    if (![EAGLContext setCurrentContext:h->context]) {
        fprintf(stderr, "N64Host: setCurrentContext failed\n");
        return false;
    }

    glGenFramebuffers(1, &h->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, h->fbo);

    glGenTextures(1, &h->colorRBO);
    glBindTexture(GL_TEXTURE_2D, h->colorRBO);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, h->fbW, h->fbH, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, h->colorRBO, 0);

    glGenRenderbuffers(1, &h->depthRBO);
    glBindRenderbuffer(GL_RENDERBUFFER, h->depthRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, h->fbW, h->fbH);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, h->depthRBO);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, h->depthRBO);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "N64Host: FBO incomplete 0x%x\n", status);
        return false;
    }
    glViewport(0, 0, h->fbW, h->fbH);
    glClearColor(1.f, 0.f, 1.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    fprintf(stderr, "N64Host: FBO cleared magenta\n");
    h->contextReady = true;
    return true;
}

static void destroyGL(N64HostHandle *h) {
    if (h->context) {
        [EAGLContext setCurrentContext:h->context];
        if (h->colorRBO) glDeleteTextures(1, &h->colorRBO);
        if (h->depthRBO) glDeleteRenderbuffers(1, &h->depthRBO);
        if (h->fbo) glDeleteFramebuffers(1, &h->fbo);
        h->colorRBO = h->depthRBO = h->fbo = 0;
        [EAGLContext setCurrentContext:nil];
        h->context = nil;
    }
    h->contextReady = false;
}

static void RETRO_CALLCONV host_log(enum retro_log_level level, const char *fmt, ...) {
    fprintf(stderr, "mupen[%d] ", (int)level);
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}

// Options RetroPlay pins regardless of the core's defaults.
static const char *hostOptionOverride(const char *key) {
    if (!strcmp(key, "mupen64plus-rdp-plugin")) {
#if TARGET_OS_SIMULATOR
        return "angrylion";
#else
        return "gliden64";
#endif
    }
    if (!strcmp(key, "mupen64plus-rsp-plugin")) {
#if TARGET_OS_SIMULATOR
        return "cxd4";
#else
        return "hle";
#endif
    }
    // iOS has no JIT, so never let a dynarec build pick the recompiler.
    if (!strcmp(key, "mupen64plus-cpucore")) return "cached_interpreter";
    // RetroPlay applies its own touch deadzone, so the core adds none.
    if (!strcmp(key, "mupen64plus-astick-sensitivity")) return "100";
    if (!strcmp(key, "mupen64plus-astick-deadzone")) return "0";
    if (!strcmp(key, "mupen64plus-alt-map")) return "True";
    if (!strcmp(key, "mupen64plus-ThreadedRenderer")) return "False";
    if (!strcmp(key, "mupen64plus-pak1")) return "memory";
    // FB emulation forces draws to FBO 0; on iOS that skips our HW FBO.
    if (!strcmp(key, "mupen64plus-EnableFBEmulation")) return "True";
    return nullptr;
}

// A null default_value means the first listed value, per libretro.h.
static void recordDefault(N64HostHandle *h, const char *key, const char *def,
                          const struct retro_core_option_value *values) {
    if (!key) return;
    if (!def && values && values[0].value) def = values[0].value;
    if (def) h->optionDefaults[key] = def;
}

static void recordV1Defaults(N64HostHandle *h, const struct retro_core_option_definition *defs) {
    for (; defs && defs->key; defs++)
        recordDefault(h, defs->key, defs->default_value, defs->values);
}

static void recordV2Defaults(N64HostHandle *h, const struct retro_core_option_v2_definition *defs) {
    for (; defs && defs->key; defs++)
        recordDefault(h, defs->key, defs->default_value, defs->values);
}

// Legacy form: value is "Description; default|other|...".
static void recordVariableDefaults(N64HostHandle *h, const struct retro_variable *vars) {
    for (; vars && vars->key; vars++) {
        if (!vars->value) continue;
        const char *p = strstr(vars->value, "; ");
        if (!p) continue;
        p += 2;
        const char *end = strchr(p, '|');
        h->optionDefaults[vars->key] = end ? std::string(p, (size_t)(end - p)) : std::string(p);
    }
}

static bool environ_cb(unsigned cmd, void *data) {
    if (!gHost) return false;
    switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        auto *fmt = (enum retro_pixel_format *)data;
        if (!fmt) return false;
        if (*fmt == RETRO_PIXEL_FORMAT_XRGB8888 || *fmt == RETRO_PIXEL_FORMAT_RGB565 || *fmt == RETRO_PIXEL_FORMAT_0RGB1555) {
            gHost->pixelFormat = *fmt;
            fprintf(stderr, "N64Host: pixel format %d\n", (int)*fmt);
            return true;
        }
        return false;
    }
    case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
        *(bool *)data = true;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        auto *cb = (struct retro_hw_render_callback *)data;
        if (!cb) return false;
        // Accept GLES2/3/OpenGL family
        if (cb->context_type != RETRO_HW_CONTEXT_OPENGLES2 &&
            cb->context_type != RETRO_HW_CONTEXT_OPENGLES3 &&
            cb->context_type != RETRO_HW_CONTEXT_OPENGLES_VERSION &&
            cb->context_type != RETRO_HW_CONTEXT_OPENGL &&
            cb->context_type != RETRO_HW_CONTEXT_OPENGL_CORE) {
            fprintf(stderr, "N64Host: unsupported HW context %d\n", (int)cb->context_type);
            return false;
        }
        cb->get_current_framebuffer = get_current_framebuffer;
        cb->get_proc_address = get_proc_address;
        gHost->hw = *cb;
        gHost->hwValid = true;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
        *(const char **)data = gHost->systemDir.c_str();
        return true;
    }
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
        *(const char **)data = gHost->saveDir.c_str();
        return true;
    }
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: {
        if (!data) return false;
        *(unsigned *)data = 2;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_LANGUAGE: {
        if (!data) return false;
        *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        recordVariableDefaults(gHost, (const struct retro_variable *)data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
        recordV1Defaults(gHost, (const struct retro_core_option_definition *)data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
        auto *intl = (const struct retro_core_options_intl *)data;
        if (intl) recordV1Defaults(gHost, intl->us);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
        auto *opts = (const struct retro_core_options_v2 *)data;
        if (opts) recordV2Defaults(gHost, opts->definitions);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
        auto *intl = (const struct retro_core_options_v2_intl *)data;
        if (intl && intl->us) recordV2Defaults(gHost, intl->us->definitions);
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto *var = (struct retro_variable *)data;
        if (!var || !var->key) return false;
        // Host override first, then the core's declared default. Without the
        // default mupen leaves the setting at 0, which is not what it documents.
        if (const char *value = hostOptionOverride(var->key)) {
            var->value = value;
            return true;
        }
        auto it = gHost->optionDefaults.find(var->key);
        if (it != gHost->optionDefaults.end()) {
            var->value = it->second.c_str();
            return true;
        }
        var->value = nullptr;
        return false;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        auto *cb = (struct retro_log_callback *)data;
        if (!cb) return false;
        cb->log = host_log;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY: {
        auto *geom = (struct retro_game_geometry *)data;
        if (geom && geom->base_width && geom->base_height) {
            // Keep FBO at init size unless we recreate; store for info
        }
        return true;
    }
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
        return true;
    default:
        return false;
    }
}

N64HostHandle* N64Host_Create(void) {
    auto *h = new N64HostHandle();
    ensureDirs(h);
    h->rgba.assign((size_t)h->fbW * (size_t)h->fbH * 4, 0);
    return h;
}

// Battery saves (EEPROM / SRAM / FlashRAM / Controller Pak) live in one libretro
// SAVE_RAM block. mupen never writes it to disk itself, so the host does.
static void loadSRAM(N64HostHandle *h) {
    h->sramShadow.clear();
    if (h->sramPath.empty()) return;
    auto *mem = (uint8_t *)retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    const size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (!mem || size == 0) return;
    FILE *f = fopen(h->sramPath.c_str(), "rb");
    if (f) {
        const size_t n = fread(mem, 1, size, f);
        fclose(f);
        fprintf(stderr, "N64Host: loaded %zu bytes of save RAM\n", n);
    }
    h->sramShadow.assign(mem, mem + size);
}

static void flushSRAM(N64HostHandle *h) {
    if (!h->loaded || h->sramPath.empty()) return;
    auto *mem = (const uint8_t *)retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    const size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (!mem || size == 0) return;
    if (h->sramShadow.size() == size && memcmp(h->sramShadow.data(), mem, size) == 0) return;
    const std::string tmp = h->sramPath + ".tmp";
    FILE *f = fopen(tmp.c_str(), "wb");
    if (!f) return;
    const bool ok = fwrite(mem, 1, size, f) == size;
    fclose(f);
    if (ok && rename(tmp.c_str(), h->sramPath.c_str()) == 0) {
        h->sramShadow.assign(mem, mem + size);
    } else {
        remove(tmp.c_str());
    }
}

// retro_init creates mupen's 8 MiB emulation coroutine and never frees it, so
// each game load leaks one stack. It cannot be reused across games: mupen only
// stops that coroutine and closes the ROM in retro_deinit, and CoreStartup /
// CoreShutdown are paired with init/deinit. co_delete is not exported from the
// prebuilt dylib, so the host cannot free it either.
static void unloadGame(N64HostHandle *h) {
    if (!h->loaded) return;
    gHost = h;
    if (h->context) [EAGLContext setCurrentContext:h->context];
    flushSRAM(h);
    retro_unload_game();
    retro_deinit();
    // Let the core drop its GL state while our context is still alive.
    if (h->hwValid && h->hw.context_destroy && h->context) {
        [EAGLContext setCurrentContext:h->context];
        h->hw.context_destroy();
    }
    h->hwValid = false;
    h->loaded = false;
}

void N64Host_Destroy(N64HostHandle* h) {
    if (!h) return;
    unloadGame(h);
    destroyGL(h);
    if (gHost == h) gHost = nullptr;
    delete h;
}

bool N64Host_LoadROM(N64HostHandle* h, const char* path, const char* sramPath) {
    if (!h || !path) return false;
    // Runs on the caller's thread (RetroPlay's emulation thread). The GL context is
    // made current here and on every frame, so it never needs the main thread.
    unloadGame(h);
    destroyGL(h);
    h->sramPath = sramPath ? sramPath : "";

    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "N64Host: fopen failed\n");
        return false;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return false; }
    h->romBytes.resize((size_t)sz);
    if (fread(h->romBytes.data(), 1, (size_t)sz, f) != (size_t)sz) { fclose(f); return false; }
    fclose(f);

    gHost = h;
    h->hwValid = false;
    if (!createGL(h)) {
#if TARGET_OS_SIMULATOR
        fprintf(stderr, "N64Host: createGL failed — continuing for software RDP\n");
#else
        gHost = nullptr;
        return false;
#endif
    }

    retro_set_environment(environ_cb);
    retro_set_video_refresh(video_refresh);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_sample_batch);
    retro_set_input_poll(input_poll);
    retro_set_input_state(input_state);
    retro_init();

    struct retro_game_info info {};
    info.path = path;
    info.data = h->romBytes.data();
    info.size = h->romBytes.size();
    info.meta = nullptr;

    if (!retro_load_game(&info)) {
        fprintf(stderr, "N64Host: retro_load_game failed\n");
        retro_deinit();
        if (h->hwValid && h->hw.context_destroy && h->context) {
            [EAGLContext setCurrentContext:h->context];
            h->hw.context_destroy();
        }
        h->hwValid = false;
        destroyGL(h);
        gHost = nullptr;
        return false;
    }

    if (h->hwValid && h->hw.context_reset) {
        [EAGLContext setCurrentContext:h->context];
        h->hw.context_reset();
    } else {
        fprintf(stderr, "N64Host: no HW context_reset (hwValid=%d)\n", (int)h->hwValid);
    }

    struct retro_system_av_info av {};
    retro_get_system_av_info(&av);
    if (av.timing.fps > 1) h->fps = av.timing.fps;
    if (av.timing.sample_rate > 1) h->sampleRate = av.timing.sample_rate;

    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    h->audio.clear();
    h->hasFrame = false;
    h->loaded = true;
    loadSRAM(h);
    return true;
}

void N64Host_SetKeys(N64HostHandle* h, uint32_t n64Bitmask, float stickX, float stickY) {
    if (!h) return;
    h->joypadMask = mapN64ToJoypad(n64Bitmask);
    // libretro analog is ±0x7fff with Y pointing DOWN; RetroPlay Y points up.
    const float x = std::clamp(stickX, -1.0f, 1.0f);
    const float y = std::clamp(stickY, -1.0f, 1.0f);
    h->stickX = (int16_t)(x * 32767.0f);
    h->stickY = (int16_t)(-y * 32767.0f);
}

void N64Host_RunFrame(N64HostHandle* h) {
    if (!h || !h->loaded) return;
    gHost = h;
    if (h->context) {
        [EAGLContext setCurrentContext:h->context];
        if (h->fbo) glBindFramebuffer(GL_FRAMEBUFFER, h->fbo);
    }
    retro_run();
}

void N64Host_Reset(N64HostHandle* h) {
    if (!h || !h->loaded) return;
    gHost = h;
    if (h->context) [EAGLContext setCurrentContext:h->context];
    retro_reset();
}

const uint8_t* N64Host_Frame(N64HostHandle* h, int* outW, int* outH) {
    if (!h || !h->hasFrame || h->rgba.empty()) return nullptr;
    const size_t need = (size_t)h->frameW * (size_t)h->frameH * 4;
    if (h->frameW <= 0 || h->frameH <= 0 || h->rgba.size() < need) return nullptr;
    if (outW) *outW = h->frameW;
    if (outH) *outH = h->frameH;
    return h->rgba.data();
}

int N64Host_ReadAudio(N64HostHandle* h, int16_t* out, int maxFrames) {
    if (!h || !out || maxFrames <= 0) return 0;
    const size_t frames = std::min(h->audio.size() / 2, (size_t)maxFrames);
    if (frames == 0) return 0;
    memcpy(out, h->audio.data(), frames * 2 * sizeof(int16_t));
    h->audio.erase(h->audio.begin(), h->audio.begin() + (std::ptrdiff_t)(frames * 2));
    return (int)frames;
}

double N64Host_FrameRate(N64HostHandle* h) { return h ? h->fps : 60.0; }
double N64Host_SampleRate(N64HostHandle* h) { return h ? h->sampleRate : 44100.0; }

void N64Host_FlushSaveData(N64HostHandle* h) {
    if (h) flushSRAM(h);
}

bool N64Host_SaveState(N64HostHandle* h, const char* path) {
    if (!h || !h->loaded || !path) return false;
    gHost = h;
    if (h->context) [EAGLContext setCurrentContext:h->context];
    size_t sz = retro_serialize_size();
    if (!sz) return false;
    std::vector<uint8_t> buf(sz);
    if (!retro_serialize(buf.data(), sz)) return false;
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(buf.data(), 1, sz, f) == sz;
    fclose(f);
    return ok;
}

bool N64Host_LoadState(N64HostHandle* h, const char* path) {
    if (!h || !h->loaded || !path) return false;
    gHost = h;
    if (h->context) [EAGLContext setCurrentContext:h->context];
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return false; }
    // mupen's retro_unserialize returns true even when the load job fails, and
    // its retro_savestate_result is not exported from the dylib. Reject what the
    // core would reject before handing it over: the wrong size (truncated, other
    // core) or a header that is not "M64+SAVE" with major version 1. The core's
    // remaining check (ROM MD5) is not repeated here.
    const size_t expected = retro_serialize_size();
    if (expected == 0 || (size_t)sz != expected) {
        fprintf(stderr, "N64Host: state size %ld != %zu, refusing load\n", sz, expected);
        fclose(f);
        return false;
    }
    std::vector<uint8_t> buf((size_t)sz);
    if (fread(buf.data(), 1, (size_t)sz, f) != (size_t)sz) { fclose(f); return false; }
    fclose(f);
    if (memcmp(buf.data(), "M64+SAVE", 8) != 0 || buf[8] != 0x00 || buf[9] != 0x01) {
        fprintf(stderr, "N64Host: not a mupen64plus 1.x state, refusing load\n");
        return false;
    }
    return retro_unserialize(buf.data(), buf.size());
}
