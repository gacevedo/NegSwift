#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Sensor-native linear RGB from LibRaw (`output_color=raw`, unity WB, linear gamma).
typedef struct NegSwiftRawBuffer {
    int width;
    int height;
    /// LibRaw `sizes.flip` (0 or EXIF 1–8). Pixels are unrotated (`user_flip=0`).
    int orientation;
    float *pixels;
    size_t count;
    /// 1 when LibRaw `half_size` ran (Bayer 2×2 bin). 0 for full-size or X-Trans.
    int used_half_size;
} NegSwiftRawBuffer;

/// 1 when this build linked LibRaw on macOS.
int negswift_raw_available(void);

/// Identify without unpack. Writes unrotated output size (`iwidth`/`iheight`) and flip.
int negswift_raw_probe(const char *path, int *width, int *height, int *orientation);

/// `half_size` requests NegPy's preview/thumb path (LINEAR + 2×2 bin). X-Trans ignores it.
int negswift_raw_decode(const char *path, int half_size, NegSwiftRawBuffer *out, char *err, size_t err_len);

void negswift_raw_free(NegSwiftRawBuffer *buf);

#ifdef __cplusplus
}
#endif
