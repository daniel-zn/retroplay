// SPDX-License-Identifier: GPL-3.0-or-later
#include "MelonDSBridge.h"
#include "NDS.h"
#include "NDSCart.h"
#include "Savestate.h"
#include "Args.h"
#include "GPU.h"
#include "SPU.h"

#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

using namespace melonDS;

namespace {
constexpr double kSampleRate = 48000.0;
}

struct MelonDSHandle {
    std::unique_ptr<NDS> nds;
    std::string romPath;
    std::string savePath;
    std::vector<u8> save;
    bool saveDirty = false;
};

MelonDSHandle* MelonDS_Create(void) {
    auto* h = new MelonDSHandle();
    NDSArgs args;
    args.JIT = std::nullopt; // interpreter only (App Store)
    args.OutputSampleRate = kSampleRate;
    // userdata = handle, so Platform callbacks can find us.
    h->nds = std::make_unique<NDS>(std::move(args), h);
    return h;
}

void MelonDS_Destroy(MelonDSHandle* h) {
    if (!h) return;
    MelonDS_FlushSave(h);
    delete h;
}

void MelonDS_OnNDSSaveWritten(void* userdata, const uint8_t* savedata, uint32_t savelen) {
    auto* h = static_cast<MelonDSHandle*>(userdata);
    if (!h || !savedata || savelen == 0) return;
    h->save.assign(savedata, savedata + savelen);
    h->saveDirty = true;
}

static bool readFile(const char* path, std::vector<u8>& out) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) return false;
    const auto len = in.tellg();
    if (len <= 0) return false;
    out.resize((size_t)len);
    in.seekg(0);
    in.read(reinterpret_cast<char*>(out.data()), len);
    return (bool)in;
}

// Like melonDS Qt's setDateTime: the RTC otherwise starts at 2000-01-01.
static void syncClock(MelonDSHandle* h) {
    const time_t now = time(nullptr);
    struct tm local {};
    if (!localtime_r(&now, &local)) return;
    h->nds->RTC.SetDateTime(local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
                            local.tm_hour, local.tm_min, local.tm_sec);
}

static void bootCart(MelonDSHandle* h) {
    h->nds->Reset();
    syncClock(h);
    // FreeBIOS / generated firmware cannot boot the firmware UI — jump to cart entry.
    if (h->nds->NeedsDirectBoot()) {
        h->nds->SetupDirectBoot(h->romPath);
    }
    h->nds->Start(); // Running=true — required or RunFrame blanks
}

bool MelonDS_LoadROM(MelonDSHandle* h, const char* path, const char* savePath) {
    if (!h || !h->nds || !path) return false;
    std::vector<u8> rom;
    if (!readFile(path, rom)) return false;
    auto romBuf = std::make_unique<u8[]>(rom.size());
    std::memcpy(romBuf.get(), rom.data(), rom.size());

    h->romPath = path;
    h->savePath = savePath ? savePath : "";
    h->save.clear();
    h->saveDirty = false;

    NDSCart::NDSCartArgs cartArgs {};
    std::vector<u8> existing;
    if (!h->savePath.empty() && readFile(h->savePath.c_str(), existing)) {
        cartArgs.SRAM = std::make_unique<u8[]>(existing.size());
        std::memcpy(cartArgs.SRAM.get(), existing.data(), existing.size());
        cartArgs.SRAMLength = (u32)existing.size();
        h->save = existing;
    }

    // Cart userdata = handle, so Platform::WriteNDSSave reaches MelonDS_OnNDSSaveWritten.
    auto cart = NDSCart::ParseROM(std::move(romBuf), (u32)rom.size(), h, std::move(cartArgs));
    if (!cart) return false;
    h->nds->SetNDSCart(std::move(cart));
    bootCart(h);
    return true;
}

void MelonDS_SetKeyMask(MelonDSHandle* h, uint32_t mask) {
    if (!h || !h->nds) return;
    // melonDS KeyInput is active-low; RetroPlay NDSInput is pressed=1.
    h->nds->SetKeyMask((~mask) & 0xFFF);
}

void MelonDS_Touch(MelonDSHandle* h, uint16_t x, uint16_t y, bool pressed) {
    if (!h || !h->nds) return;
    if (pressed) h->nds->TouchScreen(x > 255 ? 255 : x, y > 191 ? 191 : y);
    else h->nds->ReleaseScreen();
}

void MelonDS_RunFrame(MelonDSHandle* h) {
    if (h && h->nds) h->nds->RunFrame();
}

void MelonDS_Reset(MelonDSHandle* h) {
    if (!h || !h->nds || h->romPath.empty()) return;
    MelonDS_FlushSave(h);
    bootCart(h);
}

static void convertFramebuffer(const u32* src, uint8_t* dst, int pixels) {
    // SoftRenderer ExpandColor writes BGRA (A in high byte). Emit RGBA8.
    for (int i = 0; i < pixels; i++) {
        u32 p = src[i];
        dst[i * 4 + 0] = (uint8_t)((p >> 16) & 0xFF); // R
        dst[i * 4 + 1] = (uint8_t)((p >> 8) & 0xFF);  // G
        dst[i * 4 + 2] = (uint8_t)(p & 0xFF);          // B
        dst[i * 4 + 3] = 0xFF;
    }
}

size_t MelonDS_CopyRGBA(MelonDSHandle* h, void* outRGBA, size_t outCapacity, int* outW, int* outH) {
    if (!h || !h->nds || !outRGBA) return 0;
    void* top = nullptr;
    void* bottom = nullptr;
    if (!h->nds->GPU.GetFramebuffers(&top, &bottom) || !top || !bottom) return 0;
    const size_t need = 256 * 384 * 4;
    if (outCapacity < need) return 0;
    auto* dst = static_cast<uint8_t*>(outRGBA);
    convertFramebuffer(static_cast<const u32*>(top), dst, 256 * 192);
    convertFramebuffer(static_cast<const u32*>(bottom), dst + 256 * 192 * 4, 256 * 192);
    if (outW) *outW = 256;
    if (outH) *outH = 384;
    return need;
}

int MelonDS_ReadAudio(MelonDSHandle* h, int16_t* out, int maxFrames) {
    if (!h || !h->nds || !out || maxFrames <= 0) return 0;
    return h->nds->SPU.ReadOutput(out, maxFrames);
}

double MelonDS_SampleRate(void) { return kSampleRate; }

void MelonDS_FlushSave(MelonDSHandle* h) {
    if (!h || !h->saveDirty || h->savePath.empty() || h->save.empty()) return;
    const std::string tmp = h->savePath + ".tmp";
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out) return;
    out.write(reinterpret_cast<const char*>(h->save.data()), (std::streamsize)h->save.size());
    out.close();
    if (out.good() && std::rename(tmp.c_str(), h->savePath.c_str()) == 0) {
        h->saveDirty = false;
    } else {
        std::remove(tmp.c_str());
    }
}

bool MelonDS_SaveState(MelonDSHandle* h, const char* path) {
    if (!h || !h->nds || !path) return false;
    Savestate state;
    if (state.Error) return false;
    h->nds->DoSavestate(&state);
    if (state.Error) return false;
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    out.write(static_cast<const char*>(state.Buffer()), (std::streamsize)state.Length());
    return out.good();
}

bool MelonDS_LoadState(MelonDSHandle* h, const char* path) {
    if (!h || !h->nds || !path) return false;
    std::vector<u8> data;
    if (!readFile(path, data)) return false;

    // Keep a snapshot so a bad file can't leave the game half-restored.
    auto backup = std::make_unique<Savestate>(Savestate::DEFAULT_SIZE);
    if (backup->Error || !h->nds->DoSavestate(backup.get()) || backup->Error) return false;

    // A state carries the cart's save memory from when it was made. The battery
    // save is newer than any state, so put the current one back afterwards.
    std::vector<u8> liveSave;
    if (const u8* mem = h->nds->GetNDSSave()) {
        liveSave.assign(mem, mem + h->nds->GetNDSSaveLength());
    }
    const std::vector<u8> mirror = h->save;
    const bool mirrorDirty = h->saveDirty;
    auto keepLiveSave = [&]() {
        if (!liveSave.empty() && h->nds->GetNDSSaveLength() == liveSave.size()) {
            h->nds->SetNDSSave(liveSave.data(), (u32)liveSave.size());
        }
        // Loading reported the state's save through WriteNDSSave; undo that so
        // the load itself never rewrites the .sav on disk.
        h->save = mirror;
        h->saveDirty = mirrorDirty;
    };

    Savestate state(data.data(), (u32)data.size(), false);
    if (!h->nds->DoSavestate(&state) || state.Error) {
        Savestate restore(backup->Buffer(), backup->Length(), false);
        h->nds->DoSavestate(&restore);
        keepLiveSave();
        return false;
    }
    keepLiveSave();
    syncClock(h);
    return true;
}
