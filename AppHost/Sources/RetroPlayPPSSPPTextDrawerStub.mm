#if RETROPLAY_HAS_PPSSPP

#include "Common/Render/Text/draw_text.h"
#include "Common/Render/Text/draw_text_cocoa.h"

TextDrawerCocoa::TextDrawerCocoa(Draw::DrawContext *draw) : TextDrawer(draw), ctx_(nullptr) {}
TextDrawerCocoa::~TextDrawerCocoa() {}
void TextDrawerCocoa::SetOrCreateFont(const FontStyle &) {}
bool TextDrawerCocoa::DrawStringBitmap(std::vector<uint8_t> &, TextStringEntry &, Draw::DataFormat, std::string_view, int, bool) {
    return false;
}
void TextDrawerCocoa::MeasureStringInternal(std::string_view, float *w, float *h) {
    if (w) *w = 0;
    if (h) *h = 0;
}
void TextDrawerCocoa::ClearFonts() {}

#endif
