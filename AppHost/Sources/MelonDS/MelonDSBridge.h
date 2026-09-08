#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MelonDSHandle MelonDSHandle;

MelonDSHandle* MelonDS_Create(void);
void MelonDS_Destroy(MelonDSHandle* h);
bool MelonDS_LoadROM(MelonDSHandle* h, const char* path);
void MelonDS_SetKeyMask(MelonDSHandle* h, uint32_t mask);
void MelonDS_Touch(MelonDSHandle* h, uint16_t x, uint16_t y, bool pressed);
void MelonDS_RunFrame(MelonDSHandle* h);
/// Copies stacked top+bottom screens as RGBA8 (256x384). Returns byte length or 0.
size_t MelonDS_CopyRGBA(MelonDSHandle* h, void* outRGBA, size_t outCapacity, int* outW, int* outH);

#ifdef __cplusplus
}
#endif
