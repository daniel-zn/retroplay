#if RETROPLAY_HAS_PPSSPP

#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "Common/Render/Text/draw_text.h"

// Upstream draw_text_cocoa.h only forward-declares these; unique_ptr needs a complete type.
class TextDrawerFontContext {
public:
    ~TextDrawerFontContext() = default;
};

struct TextDrawerContext {
    ~TextDrawerContext() = default;
};

#include "Common/Render/Text/draw_text_cocoa.h"

TextDrawerCocoa::TextDrawerCocoa(Draw::DrawContext *draw) : TextDrawer(draw), ctx_(nullptr) {}
TextDrawerCocoa::~TextDrawerCocoa() {
    ClearFonts();
}
void TextDrawerCocoa::SetOrCreateFont(const FontStyle &) {}
bool TextDrawerCocoa::DrawStringBitmap(std::vector<uint8_t> &, TextStringEntry &, Draw::DataFormat, std::string_view, int, bool) {
    return false;
}
void TextDrawerCocoa::MeasureStringInternal(std::string_view, float *w, float *h) {
    if (w) *w = 0;
    if (h) *h = 0;
}
void TextDrawerCocoa::ClearFonts() {
    fontMap_.clear();
}

#endif
