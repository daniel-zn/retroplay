#import "N64LibretroHost.h"

#import <TargetConditionals.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <OpenGLES/EAGL.h>
#import <Foundation/Foundation.h>

#include "libretro.h"

#include <dlfcn.h>
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
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
}

struct N64HostHandle {
    EAGLContext *context = nil;
    GLuint fbo = 0;
    GLuint colorRBO = 0;
    GLuint depthRBO = 0;
    int fbW = 640;
    int fbH = 480;
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
    std::vector<uint8_t> romBytes;
    std::string systemDir;
    std::string saveDir;
    std::string lastVideoPath;
};

static N64HostHandle *gHost = nullptr;

static void audio_sample(int16_t, int16_t) {}
static size_t audio_sample_batch(const int16_t *, size_t frames) { return frames; }
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
    uintptr_t fb = gHost ? (uintptr_t)gHost->fbo : 0;
    static int n = 0;
    if ((++n % 120) == 1) fprintf(stderr, "N64Host: get_current_framebuffer=%llu fbo=%u\n", (unsigned long long)fb, gHost ? (unsigned)gHost->fbo : 0u);
    return fb;
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
        gHost->fbW = w;
        gHost->fbH = h;
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
        static int once = 0;
        if ((++once % 60) == 1) {
            fprintf(stderr, "N64Host: soft video %ux%u fmt=%d px0=%02x%02x%02x%02x\n",
                width, height, (int)gHost->pixelFormat,
                gHost->rgba[0], gHost->rgba[1], gHost->rgba[2], gHost->rgba[3]);
        }
        return;
    }

    // HW path (GLideN64)
    if (!gHost->contextReady) return;
    [EAGLContext setCurrentContext:gHost->context];
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)gHost->fbo);
    const int w = gHost->fbW;
    const int h = gHost->fbH;
    glFinish();
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    std::vector<uint8_t> raw((size_t)w * (size_t)h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, raw.data());
    const size_t stride = (size_t)w * 4;
    gHost->rgba.resize(raw.size());
    for (int y = 0; y < h; y++) {
        memcpy(gHost->rgba.data() + (size_t)(h - 1 - y) * stride,
               raw.data() + (size_t)y * stride,
               stride);
    }
    gHost->hasFrame = true;
}

static void ensureDirs(N64HostHandle *h) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *sys = [docs stringByAppendingPathComponent:@"N64System"];
    NSString *save = [docs stringByAppendingPathComponent:@"N64Saves"];
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
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto *var = (struct retro_variable *)data;
        if (!var || !var->key) return false;
        if (!strcmp(var->key, "mupen64plus-rdp-plugin")) {
#if TARGET_OS_SIMULATOR
            var->value = "angrylion";
#else
            var->value = "gliden64";
#endif
            return true;
        }
        if (!strcmp(var->key, "mupen64plus-rsp-plugin")) {
#if TARGET_OS_SIMULATOR
            var->value = "cxd4";
#else
            var->value = "hle";
#endif
            return true;
        }
        if (!strcmp(var->key, "mupen64plus-alt-map")) {
            var->value = "True";
            return true;
        }
        if (!strcmp(var->key, "mupen64plus-ThreadedRenderer")) {
            var->value = "False";
            return true;
        }
        if (!strcmp(var->key, "mupen64plus-pak1")) {
            var->value = "memory";
            return true;
        }
        // FB emulation forces draws to FBO 0; on iOS that skips our HW FBO.
        if (!strcmp(var->key, "mupen64plus-EnableFBEmulation")) {
            var->value = "True";
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
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
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

void N64Host_Destroy(N64HostHandle* h) {
    if (!h) return;
    if (gHost == h) gHost = nullptr;
    if (h->loaded) {
        if (h->context) [EAGLContext setCurrentContext:h->context];
        retro_unload_game();
        retro_deinit();
        h->loaded = false;
    }
    destroyGL(h);
    delete h;
}

bool N64Host_LoadROM(N64HostHandle* h, const char* path) {
    if (!h || !path) return false;

    __block bool ok = false;
    __block std::string pathCopy = path;
    void (^work)(void) = ^{
        if (h->loaded) {
            if (h->context) [EAGLContext setCurrentContext:h->context];
            retro_unload_game();
            retro_deinit();
            h->loaded = false;
        }
        destroyGL(h);

        fprintf(stderr, "N64Host: reading %s\n", pathCopy.c_str());
        FILE *f = fopen(pathCopy.c_str(), "rb");
        if (!f) {
            fprintf(stderr, "N64Host: fopen failed\n");
            return;
        }
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (sz <= 0) { fclose(f); return; }
        h->romBytes.resize((size_t)sz);
        if (fread(h->romBytes.data(), 1, (size_t)sz, f) != (size_t)sz) { fclose(f); return; }
        fclose(f);

        gHost = h;
        fprintf(stderr, "N64Host: createGL…\n");
        if (!createGL(h)) {
#if TARGET_OS_SIMULATOR
            fprintf(stderr, "N64Host: createGL failed — continuing for software RDP\n");
#else
            gHost = nullptr;
            return;
#endif
        }

        fprintf(stderr, "N64Host: retro_init…\n");
        retro_set_environment(environ_cb);
        retro_set_video_refresh(video_refresh);
        retro_set_audio_sample(audio_sample);
        retro_set_audio_sample_batch(audio_sample_batch);
        retro_set_input_poll(input_poll);
        retro_set_input_state(input_state);
        retro_init();

        struct retro_game_info info {};
        info.path = pathCopy.c_str();
        info.data = h->romBytes.data();
        info.size = h->romBytes.size();
        info.meta = nullptr;

        fprintf(stderr, "N64Host: retro_load_game size=%zu hwValid=%d…\n", h->romBytes.size(), (int)h->hwValid);
        if (!retro_load_game(&info)) {
            fprintf(stderr, "N64Host: retro_load_game failed\n");
            retro_deinit();
            destroyGL(h);
            gHost = nullptr;
            return;
        }
        fprintf(stderr, "N64Host: load_game ok hwValid=%d\n", (int)h->hwValid);

        if (h->hwValid && h->hw.context_reset) {
            [EAGLContext setCurrentContext:h->context];
            fprintf(stderr, "N64Host: context_reset…\n");
            h->hw.context_reset();
            fprintf(stderr, "N64Host: context_reset done\n");
        } else {
            fprintf(stderr, "N64Host: warning — no HW context_reset (hwValid=%d)\n", (int)h->hwValid);
        }

        struct retro_system_av_info av {};
        retro_get_system_av_info(&av);
        fprintf(stderr, "N64Host: av %ux%u\n", av.geometry.base_width, av.geometry.base_height);

        retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
        h->hasFrame = false;
        h->loaded = true;
        ok = true;
        fprintf(stderr, "N64Host: loaded OK\n");
    };

    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
    return ok;
}

void N64Host_SetKeys(N64HostHandle* h, uint32_t n64Bitmask, int8_t stickX, int8_t stickY) {
    if (!h) return;
    h->joypadMask = mapN64ToJoypad(n64Bitmask);
    // libretro analog: -0x7fff..0x7fff; N64 stick -128..127
    h->stickX = (int16_t)((int)stickX * 256);
    h->stickY = (int16_t)((int)stickY * 256);
}

void N64Host_RunFrame(N64HostHandle* h) {
    if (!h || !h->loaded) return;
    void (^work)(void) = ^{
        gHost = h;
        if (h->context) {
            [EAGLContext setCurrentContext:h->context];
            if (h->fbo) glBindFramebuffer(GL_FRAMEBUFFER, h->fbo);
        }
        retro_run();
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
}

size_t N64Host_CopyRGBA(N64HostHandle* h, void* outRGBA, size_t outCapacity, int* outW, int* outH) {
    if (!h || !outRGBA || !h->hasFrame || h->rgba.empty()) return 0;
    const size_t need = h->rgba.size();
    if (outCapacity < need) return 0;
    memcpy(outRGBA, h->rgba.data(), need);
    if (outW) *outW = h->fbW;
    if (outH) *outH = h->fbH;
    static int c = 0;
    if ((++c % 60) == 1) {
        int nz = 0;
        for (size_t i = 0; i + 2 < need; i += 4) {
            if (h->rgba[i] | h->rgba[i+1] | h->rgba[i+2]) nz++;
        }
        fprintf(stderr, "RP_SMOKE N64Host_CopyRGBA nonzero_px=%d\n", nz);
    }
    return need;
}

bool N64Host_SaveState(N64HostHandle* h, const char* path) {
    if (!h || !h->loaded || !path) return false;
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
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return false; }
    std::vector<uint8_t> buf((size_t)sz);
    if (fread(buf.data(), 1, (size_t)sz, f) != (size_t)sz) { fclose(f); return false; }
    fclose(f);
    return retro_unserialize(buf.data(), buf.size());
}
