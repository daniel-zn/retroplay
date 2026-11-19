// SPDX-License-Identifier: GPL-3.0-or-later
// What the libretro host and the N64 host do the same way: audio, input, frames,
// core option defaults, save RAM and state files.
#pragma once

#include "libretro.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace retroplay {

/// Appends interleaved stereo samples, keeping only the newest `maxSamples`.
inline void appendAudio(std::vector<int16_t> &audio, const int16_t *data, size_t samples, size_t maxSamples) {
    audio.insert(audio.end(), data, data + samples);
    if (audio.size() > maxSamples) audio.erase(audio.begin(), audio.end() - (std::ptrdiff_t)maxSamples);
}

/// Moves up to `maxFrames` stereo frames out of the buffer; returns how many.
inline int readAudio(std::vector<int16_t> &audio, int16_t *out, int maxFrames) {
    if (!out || maxFrames <= 0) return 0;
    const size_t frames = std::min(audio.size() / 2, (size_t)maxFrames);
    if (frames == 0) return 0;
    memcpy(out, audio.data(), frames * 2 * sizeof(int16_t));
    audio.erase(audio.begin(), audio.begin() + (std::ptrdiff_t)(frames * 2));
    return (int)frames;
}

/// Player one's pad and left stick; every other port reads as idle.
inline int16_t inputState(uint32_t joypad, int16_t stickX, int16_t stickY,
                          unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)(joypad & 0xFFFF);
        if (id <= RETRO_DEVICE_ID_JOYPAD_R3) return (joypad & (1u << id)) ? 1 : 0;
    }
    if (device == RETRO_DEVICE_ANALOG && index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
        if (id == RETRO_DEVICE_ID_ANALOG_X) return stickX;
        if (id == RETRO_DEVICE_ID_ANALOG_Y) return stickY;
    }
    return 0;
}

/// RetroPlay's stick (±1, Y up) as libretro analog (±0x7fff, Y down).
inline int16_t analogX(float x) { return (int16_t)(std::clamp(x, -1.0f, 1.0f) * 32767.0f); }
inline int16_t analogY(float y) { return (int16_t)(-std::clamp(y, -1.0f, 1.0f) * 32767.0f); }

/// One core frame as RGBA8. 5- and 6-bit channels are widened by repeating their top bits.
inline void convertFrame(std::vector<uint8_t> &rgba, const void *data, int w, int h, size_t pitch,
                         enum retro_pixel_format format) {
    rgba.resize((size_t)w * (size_t)h * 4);
    const uint8_t *src = (const uint8_t *)data;
    for (int y = 0; y < h; y++) {
        uint8_t *dst = rgba.data() + (size_t)y * (size_t)w * 4;
        const uint8_t *row = src + (size_t)y * pitch;
        for (int x = 0; x < w; x++, dst += 4) {
            if (format == RETRO_PIXEL_FORMAT_XRGB8888) {
                const uint32_t px = ((const uint32_t *)row)[x];
                dst[0] = (px >> 16) & 0xff;
                dst[1] = (px >> 8) & 0xff;
                dst[2] = px & 0xff;
            } else {
                const uint16_t px = ((const uint16_t *)row)[x];
                const bool rgb565 = format == RETRO_PIXEL_FORMAT_RGB565;
                const uint8_t r = (px >> (rgb565 ? 11 : 10)) & 0x1f, b = px & 0x1f;
                const uint8_t g = rgb565 ? (px >> 5) & 0x3f : (px >> 5) & 0x1f;
                dst[0] = (uint8_t)((r << 3) | (r >> 2));
                dst[1] = rgb565 ? (uint8_t)((g << 2) | (g >> 4)) : (uint8_t)((g << 3) | (g >> 2));
                dst[2] = (uint8_t)((b << 3) | (b >> 2));
            }
            dst[3] = 0xff;
        }
    }
}

using OptionDefaults = std::map<std::string, std::string>;

/// The defaults a core declares (SET_CORE_OPTIONS*). A null default_value means the first listed value.
template <typename Definition>
inline void recordDefaults(OptionDefaults &defaults, const Definition *defs) {
    for (; defs && defs->key; defs++) {
        const char *def = defs->default_value;
        if (!def && defs->values[0].value) def = defs->values[0].value;
        if (def) defaults[defs->key] = def;
    }
}

/// The legacy form (SET_VARIABLES): "Description; default|other|…".
inline void recordVariableDefaults(OptionDefaults &defaults, const struct retro_variable *vars) {
    for (; vars && vars->key; vars++) {
        if (!vars->value) continue;
        const char *p = strstr(vars->value, "; ");
        if (!p) continue;
        p += 2;
        const char *end = strchr(p, '|');
        defaults[vars->key] = end ? std::string(p, (size_t)(end - p)) : std::string(p);
    }
}

/// The whole file, or false if it can't be read or is empty.
inline bool readFile(const char *path, std::vector<uint8_t> &out) {
    out.clear();
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    const long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size > 0) {
        out.resize((size_t)size);
        if (fread(out.data(), 1, (size_t)size, f) != (size_t)size) out.clear();
    }
    fclose(f);
    return !out.empty();
}

inline bool writeFile(const char *path, const void *data, size_t size) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    const bool ok = fwrite(data, 1, size, f) == size;
    fclose(f);
    return ok;
}

/// Battery save: the core's SAVE_RAM block, read from `path` if it exists. `shadow` keeps
/// what's on disk so a flush writes only when the game changed it.
inline void loadSaveRAM(const std::string &path, uint8_t *mem, size_t size, std::vector<uint8_t> &shadow) {
    shadow.clear();
    if (path.empty() || !mem || size == 0) return;
    if (FILE *f = fopen(path.c_str(), "rb")) {
        fread(mem, 1, size, f);
        fclose(f);
    }
    shadow.assign(mem, mem + size);
}

/// Writes the save RAM (through a temporary file) when it changed since the last load or flush.
inline void flushSaveRAM(const std::string &path, const uint8_t *mem, size_t size, std::vector<uint8_t> &shadow) {
    if (path.empty() || !mem || size == 0) return;
    if (shadow.size() == size && memcmp(shadow.data(), mem, size) == 0) return;
    // Nothing was ever written: don't leave an all-zero file behind for games without saves.
    if (shadow.empty() && std::all_of(mem, mem + size, [](uint8_t b) { return b == 0; })) return;
    const std::string tmp = path + ".tmp";
    if (writeFile(tmp.c_str(), mem, size) && rename(tmp.c_str(), path.c_str()) == 0) {
        shadow.assign(mem, mem + size);
    } else {
        remove(tmp.c_str());
    }
}

} // namespace retroplay
