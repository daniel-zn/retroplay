#include "MelonDSBridge.h"
#include "NDS.h"
#include "NDSCart.h"
#include "args.h"
#include "GPU.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

using namespace melonDS;

struct MelonDSHandle {
    std::unique_ptr<NDS> nds;
};

MelonDSHandle* MelonDS_Create(void) {
    auto* h = new MelonDSHandle();
    NDSArgs args;
    args.JIT = std::nullopt; // interpreter only
    h->nds = std::make_unique<NDS>(std::move(args), nullptr);
    return h;
}

void MelonDS_Destroy(MelonDSHandle* h) {
    delete h;
}

bool MelonDS_LoadROM(MelonDSHandle* h, const char* path) {
    if (!h || !h->nds || !path) return false;
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) return false;
    auto len = (size_t)in.tellg();
    in.seekg(0);
    auto buf = std::make_unique<u8[]>(len);
    in.read(reinterpret_cast<char*>(buf.get()), (std::streamsize)len);
    if (!in) return false;
    auto cart = NDSCart::ParseROM(std::move(buf), (u32)len, nullptr, std::nullopt);
    if (!cart) return false;
    h->nds->SetNDSCart(std::move(cart));
    h->nds->Reset();
    // FreeBIOS / generated firmware cannot boot the firmware UI — jump to cart entry.
    if (h->nds->NeedsDirectBoot()) {
        h->nds->SetupDirectBoot(path);
    }
    h->nds->Start(); // Running=true — required or RunFrame blanks
    return true;
}

void MelonDS_SetKeyMask(MelonDSHandle* h, uint32_t mask) {
    if (!h || !h->nds) return;
    // melonDS KeyInput is active-low; RetroPlay NDSInput is pressed=1.
    h->nds->SetKeyMask((~mask) & 0xFFF);
}

void MelonDS_Touch(MelonDSHandle* h, uint16_t x, uint16_t y, bool pressed) {
    if (!h || !h->nds) return;
    if (pressed) h->nds->TouchScreen(x, y);
    else h->nds->ReleaseScreen();
}

void MelonDS_RunFrame(MelonDSHandle* h) {
    if (h && h->nds) h->nds->RunFrame();
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
