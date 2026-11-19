// SPDX-License-Identifier: GPL-3.0-or-later
#import "LibretroHost.h"
#import "LibretroCommon.h"

#import <Foundation/Foundation.h>

#include <cstdarg>
#include <dlfcn.h>

/// The libretro C API, resolved from one core image.
struct LibretroAPI {
    void (*init)(void);
    void (*deinit)(void);
    void (*get_system_info)(struct retro_system_info *);
    void (*get_system_av_info)(struct retro_system_av_info *);
    void (*set_environment)(retro_environment_t);
    void (*set_video_refresh)(retro_video_refresh_t);
    void (*set_audio_sample)(retro_audio_sample_t);
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*set_input_poll)(retro_input_poll_t);
    void (*set_input_state)(retro_input_state_t);
    void (*set_controller_port_device)(unsigned, unsigned);
    bool (*load_game)(const struct retro_game_info *);
    void (*unload_game)(void);
    void (*run)(void);
    void (*reset)(void);
    size_t (*serialize_size)(void);
    bool (*serialize)(void *, size_t);
    bool (*unserialize)(const void *, size_t);
    void *(*get_memory_data)(unsigned);
    size_t (*get_memory_size)(unsigned);
};

struct LibretroHost {
    std::string name;
    LibretroAPI api {};
    bool initialized = false;
    bool loaded = false;
    std::string systemDir;
    std::string saveDir;
    std::string error;

    enum retro_pixel_format pixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;
    std::vector<uint8_t> rgba;
    int frameW = 0;
    int frameH = 0;
    /// A frame came since the app last took one (a repeated frame doesn't count).
    bool newFrame = false;

    uint32_t joypad = 0;
    int16_t leftX = 0;
    int16_t leftY = 0;

    std::vector<int16_t> audio;
    size_t maxAudioSamples = 48000;
    double fps = 60.0;
    double sampleRate = 44100.0;

    std::vector<uint8_t> content;
    std::string sramPath;
    std::vector<uint8_t> sramShadow;

    std::map<std::string, std::string> overrides;
    retroplay::OptionDefaults defaults;
};

static LibretroHost *gHost = nullptr;

// One dlopen per core for the life of the process: cores keep static state that isn't
// safe to unmap, and retro_init / retro_deinit bracket each game instead.
static void *openCore(const std::string &name, std::string &error) {
    static std::map<std::string, void *> handles;
    auto it = handles.find(name);
    if (it != handles.end()) return it->second;
    NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath;
    NSString *fw = [NSString stringWithFormat:@"%s.framework/%s", name.c_str(), name.c_str()];
    NSString *path = [frameworks stringByAppendingPathComponent:fw];
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *reason = dlerror();
        error = std::string("could not open the ") + name + " core" + (reason ? std::string(": ") + reason : "");
        return nullptr;
    }
    handles[name] = handle;
    return handle;
}

template <typename T>
static bool resolve(void *handle, const char *symbol, T &out) {
    out = reinterpret_cast<T>(dlsym(handle, symbol));
    return out != nullptr;
}

static bool resolveAPI(void *handle, LibretroAPI &api) {
    return resolve(handle, "retro_init", api.init)
        && resolve(handle, "retro_deinit", api.deinit)
        && resolve(handle, "retro_get_system_info", api.get_system_info)
        && resolve(handle, "retro_get_system_av_info", api.get_system_av_info)
        && resolve(handle, "retro_set_environment", api.set_environment)
        && resolve(handle, "retro_set_video_refresh", api.set_video_refresh)
        && resolve(handle, "retro_set_audio_sample", api.set_audio_sample)
        && resolve(handle, "retro_set_audio_sample_batch", api.set_audio_sample_batch)
        && resolve(handle, "retro_set_input_poll", api.set_input_poll)
        && resolve(handle, "retro_set_input_state", api.set_input_state)
        && resolve(handle, "retro_set_controller_port_device", api.set_controller_port_device)
        && resolve(handle, "retro_load_game", api.load_game)
        && resolve(handle, "retro_unload_game", api.unload_game)
        && resolve(handle, "retro_run", api.run)
        && resolve(handle, "retro_reset", api.reset)
        && resolve(handle, "retro_serialize_size", api.serialize_size)
        && resolve(handle, "retro_serialize", api.serialize)
        && resolve(handle, "retro_unserialize", api.unserialize)
        && resolve(handle, "retro_get_memory_data", api.get_memory_data)
        && resolve(handle, "retro_get_memory_size", api.get_memory_size);
}

// MARK: - Callbacks

static void audio_sample(int16_t left, int16_t right) {
    if (!gHost) return;
    const int16_t frame[2] = {left, right};
    retroplay::appendAudio(gHost->audio, frame, 2, gHost->maxAudioSamples);
}

static size_t audio_sample_batch(const int16_t *data, size_t frames) {
    if (gHost && data) retroplay::appendAudio(gHost->audio, data, frames * 2, gHost->maxAudioSamples);
    return frames;
}

static void input_poll(void) {}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (!gHost) return 0;
    return retroplay::inputState(gHost->joypad, gHost->leftX, gHost->leftY, port, device, index, id);
}

static void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    // NULL: the core repeats the previous frame (GET_CAN_DUPE).
    if (!gHost || !data || data == RETRO_HW_FRAME_BUFFER_VALID || !width || !height) return;
    const int w = (int)width;
    const int h = (int)height;
    gHost->frameW = w;
    gHost->frameH = h;
    retroplay::convertFrame(gHost->rgba, data, w, h, pitch, gHost->pixelFormat);
    gHost->newFrame = true;
#if DEBUG
    static int logged = 0;
    if (logged < 3 || (logged < 400 && logged % 120 == 0)) {
        size_t lit = 0;
        for (size_t i = 0; i < gHost->rgba.size(); i += 4)
            if (gHost->rgba[i] | gHost->rgba[i + 1] | gHost->rgba[i + 2]) lit++;
        NSLog(@"RP_LIBRETRO %s frame %d: %dx%d pitch %zu format %d, %zu lit pixels",
              gHost->name.c_str(), logged, w, h, pitch, (int)gHost->pixelFormat, lit);
    }
    logged++;
#endif
}

// Core messages go to the unified log (Console, `log stream`), like the rest of the app.
static void RETRO_CALLCONV host_log(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    NSLog(@"RP_LIBRETRO %s: %s", gHost ? gHost->name.c_str() : "?", line);
}

static bool environ_cb(unsigned cmd, void *data) {
    LibretroHost *h = gHost;
    if (!h) return false;
    switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        auto *fmt = (const enum retro_pixel_format *)data;
        if (!fmt) return false;
        if (*fmt != RETRO_PIXEL_FORMAT_XRGB8888 && *fmt != RETRO_PIXEL_FORMAT_RGB565 &&
            *fmt != RETRO_PIXEL_FORMAT_0RGB1555) return false;
        h->pixelFormat = *fmt;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        if (data) *(bool *)data = true;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char **)data = h->systemDir.c_str();
        return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = h->saveDir.c_str();
        return true;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        if (!data) return false;
        *(unsigned *)data = 2;
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        if (!data) return false;
        *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        retroplay::recordVariableDefaults(h->defaults, (const struct retro_variable *)data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
        retroplay::recordDefaults(h->defaults, (const struct retro_core_option_definition *)data);
        return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
        auto *intl = (const struct retro_core_options_intl *)data;
        if (intl) retroplay::recordDefaults(h->defaults, intl->us);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
        auto *opts = (const struct retro_core_options_v2 *)data;
        if (opts) retroplay::recordDefaults(h->defaults, opts->definitions);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
        auto *intl = (const struct retro_core_options_v2_intl *)data;
        if (intl && intl->us) retroplay::recordDefaults(h->defaults, intl->us->definitions);
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        if (data) *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto *var = (struct retro_variable *)data;
        if (!var || !var->key) return false;
        auto o = h->overrides.find(var->key);
        if (o != h->overrides.end()) { var->value = o->second.c_str(); return true; }
        auto d = h->defaults.find(var->key);
        if (d != h->defaults.end()) { var->value = d->second.c_str(); return true; }
        var->value = nullptr;
        return false;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        auto *cb = (struct retro_log_callback *)data;
        if (!cb) return false;
        cb->log = host_log;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
        auto *msg = (const struct retro_message *)data;
        if (msg && msg->msg) NSLog(@"RP_LIBRETRO %s message: %s", h->name.c_str(), msg->msg);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        auto *av = (const struct retro_system_av_info *)data;
        if (av && av->timing.fps > 1) h->fps = av->timing.fps;
        if (av && av->timing.sample_rate > 1) h->sampleRate = av->timing.sample_rate;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true;
    default:
        return false;
    }
}

// MARK: - Save RAM

static void loadSRAM(LibretroHost *h) {
    retroplay::loadSaveRAM(h->sramPath, (uint8_t *)h->api.get_memory_data(RETRO_MEMORY_SAVE_RAM),
                           h->api.get_memory_size(RETRO_MEMORY_SAVE_RAM), h->sramShadow);
}

static void flushSRAM(LibretroHost *h) {
    if (!h->loaded) return;
    retroplay::flushSaveRAM(h->sramPath, (const uint8_t *)h->api.get_memory_data(RETRO_MEMORY_SAVE_RAM),
                            h->api.get_memory_size(RETRO_MEMORY_SAVE_RAM), h->sramShadow);
}

static void unloadGame(LibretroHost *h) {
    gHost = h;
    if (h->loaded) {
        flushSRAM(h);
        h->api.unload_game();
        h->loaded = false;
    }
    if (h->initialized) {
        h->api.deinit();
        h->initialized = false;
    }
}

// MARK: - API

LibretroHost* LibretroHost_Create(const char* frameworkName, const char* systemDir, const char* saveDir) {
    if (!frameworkName) return nullptr;
    auto *h = new LibretroHost();
    h->name = frameworkName;
    h->systemDir = systemDir ? systemDir : "";
    h->saveDir = saveDir ? saveDir : "";
    void *handle = openCore(h->name, h->error);
    if (!handle || !resolveAPI(handle, h->api)) {
        NSLog(@"RP_LIBRETRO %s", h->error.empty() ? "missing libretro symbols" : h->error.c_str());
        delete h;
        return nullptr;
    }
    return h;
}

void LibretroHost_Destroy(LibretroHost* h) {
    if (!h) return;
    unloadGame(h);
    if (gHost == h) gHost = nullptr;
    delete h;
}

void LibretroHost_SetOption(LibretroHost* h, const char* key, const char* value) {
    if (h && key && value) h->overrides[key] = value;
}

bool LibretroHost_Load(LibretroHost* h, const char* path, const char* sramPath, const char** errorOut) {
    if (!h || !path) return false;
    unloadGame(h);
    h->error.clear();
    h->sramPath = sramPath ? sramPath : "";
    h->defaults.clear();
    h->audio.clear();
    h->newFrame = false;
    h->pixelFormat = RETRO_PIXEL_FORMAT_0RGB1555;
    gHost = h;

    h->api.set_environment(environ_cb);
    h->api.set_video_refresh(video_refresh);
    h->api.set_audio_sample(audio_sample);
    h->api.set_audio_sample_batch(audio_sample_batch);
    h->api.set_input_poll(input_poll);
    h->api.set_input_state(input_state);
    h->api.init();
    h->initialized = true;

    struct retro_system_info sys {};
    h->api.get_system_info(&sys);
    struct retro_game_info info {};
    info.path = path;
    h->content.clear();
    if (!sys.need_fullpath) {
        if (!retroplay::readFile(path, h->content)) {
            h->error = "the game file is missing, empty or unreadable";
            if (errorOut) *errorOut = h->error.c_str();
            unloadGame(h);
            return false;
        }
        info.data = h->content.data();
        info.size = h->content.size();
    }
    if (!h->api.load_game(&info)) {
        h->error = "the core could not start this game";
        if (errorOut) *errorOut = h->error.c_str();
        unloadGame(h);
        return false;
    }
    h->loaded = true;

    struct retro_system_av_info av {};
    h->api.get_system_av_info(&av);
    if (av.timing.fps > 1) h->fps = av.timing.fps;
    if (av.timing.sample_rate > 1) h->sampleRate = av.timing.sample_rate;
    h->maxAudioSamples = (size_t)(h->sampleRate) & ~(size_t)1; // ~0.5 s of stereo
    h->api.set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    loadSRAM(h);
    NSLog(@"RP_LIBRETRO %s loaded %s %s: %ux%u @ %.3f fps, %.0f Hz, fullpath=%d, save RAM %zu bytes",
          h->name.c_str(), sys.library_name ?: "?", sys.library_version ?: "",
          av.geometry.base_width, av.geometry.base_height, h->fps, h->sampleRate,
          (int)sys.need_fullpath, h->api.get_memory_size(RETRO_MEMORY_SAVE_RAM));
    return true;
}

void LibretroHost_SetInput(LibretroHost* h, uint32_t joypad, float leftX, float leftY) {
    if (!h) return;
    h->joypad = joypad;
    h->leftX = retroplay::analogX(leftX);
    h->leftY = retroplay::analogY(leftY);
}

void LibretroHost_RunFrame(LibretroHost* h) {
    if (!h || !h->loaded) return;
    gHost = h;
    h->api.run();
}

void LibretroHost_Reset(LibretroHost* h) {
    if (!h || !h->loaded) return;
    gHost = h;
    h->api.reset();
}

const uint8_t* LibretroHost_Frame(LibretroHost* h, int* outW, int* outH) {
    if (!h || !h->newFrame || h->frameW <= 0 || h->frameH <= 0) return nullptr;
    if (h->rgba.size() < (size_t)h->frameW * (size_t)h->frameH * 4) return nullptr;
    if (outW) *outW = h->frameW;
    if (outH) *outH = h->frameH;
    h->newFrame = false;
    return h->rgba.data();
}

int LibretroHost_ReadAudio(LibretroHost* h, int16_t* out, int maxFrames) {
    return h ? retroplay::readAudio(h->audio, out, maxFrames) : 0;
}

double LibretroHost_FrameRate(LibretroHost* h) { return h ? h->fps : 60.0; }
double LibretroHost_SampleRate(LibretroHost* h) { return h ? h->sampleRate : 44100.0; }

void LibretroHost_FlushSaveData(LibretroHost* h) {
    if (!h) return;
    gHost = h;
    flushSRAM(h);
}

bool LibretroHost_SaveState(LibretroHost* h, const char* path) {
    if (!h || !h->loaded || !path) return false;
    gHost = h;
    const size_t size = h->api.serialize_size();
    if (!size) return false;
    std::vector<uint8_t> buf(size);
    return h->api.serialize(buf.data(), size) && retroplay::writeFile(path, buf.data(), size);
}

bool LibretroHost_LoadState(LibretroHost* h, const char* path) {
    if (!h || !h->loaded || !path) return false;
    gHost = h;
    std::vector<uint8_t> buf;
    // A state from another core or a truncated file: refuse rather than hand it over.
    const size_t expected = h->api.serialize_size();
    if (!retroplay::readFile(path, buf) || expected == 0 || buf.size() > expected) return false;
    return h->api.unserialize(buf.data(), buf.size());
}
