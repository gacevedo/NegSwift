#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// dcraw `-q` values LibRaw reads as `user_qual`.
enum {
    NEGSWIFT_RAW_QUAL_LINEAR = 0,
    NEGSWIFT_RAW_QUAL_PPG = 2,
    NEGSWIFT_RAW_QUAL_AHD = 3
};

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
    /// `user_qual` actually applied (LINEAR / PPG / AHD).
    int user_qual;
    /// 1 when the CFA is X-Trans (`filters == 9`).
    int is_xtrans;
} NegSwiftRawBuffer;

/// One `libraw` file: `open` once, then `unpack` / `unpack_thumb` / process.
typedef struct NegSwiftRawHandle NegSwiftRawHandle;

/// 1 when this build linked LibRaw on macOS.
int negswift_raw_available(void);

/// Identify without unpack. Writes unrotated output size (`iwidth`/`iheight`) and flip.
int negswift_raw_probe(const char *path, int *width, int *height, int *orientation);

/// `half_size` requests NegPy preview: Bayer LINEAR + 2×2; X-Trans full-size PPG.
int negswift_raw_decode(const char *path, int half_size, NegSwiftRawBuffer *out, char *err, size_t err_len);

void negswift_raw_free(NegSwiftRawBuffer *buf);

/// Embedded preview from `libraw_unpack_thumb`. JPEG `data` is the file bytes.
/// BITMAP: `format=2` and `data` is NULL — never copy grayscale BITMAP (NegPy).
typedef struct NegSwiftRawThumb {
    int width;
    int height;
    /// LibRaw `sizes.flip` (0 or EXIF 1–8).
    int orientation;
    /// 1 = JPEG, 2 = BITMAP (unsafe to read).
    int format;
    uint8_t *data;
    size_t size;
} NegSwiftRawThumb;

int negswift_raw_extract_thumb(const char *path, NegSwiftRawThumb *out, char *err, size_t err_len);

void negswift_raw_free_thumb(NegSwiftRawThumb *thumb);

/// Open + identify. Does not unpack. Caller must `negswift_raw_close`.
NegSwiftRawHandle *negswift_raw_open(const char *path, char *err, size_t err_len);

void negswift_raw_close(NegSwiftRawHandle *handle);

int negswift_raw_handle_probe(const NegSwiftRawHandle *handle, int *width, int *height, int *orientation);

/// Unpack once (shared), then process. Safe to call again with a different `half_size`.
int negswift_raw_handle_decode(
    NegSwiftRawHandle *handle,
    int half_size,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
);

/// `user_qual` < 0 uses the preview/export default (PPG vs AHD). Timing tests pass PPG/AHD explicitly.
int negswift_raw_handle_decode_ex(
    NegSwiftRawHandle *handle,
    int half_size,
    int user_qual,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
);

/// Homebrew libraw uses libomp. `n` is `omp_set_num_threads` + `OMP_NUM_THREADS`.
void negswift_raw_set_omp_threads(int n);
int negswift_raw_omp_max_threads(void);
int negswift_raw_omp_num_procs(void);

/// `unpack_thumb` once on the open handle.
int negswift_raw_handle_thumb(NegSwiftRawHandle *handle, NegSwiftRawThumb *out, char *err, size_t err_len);

/// Process-wide open / unpack counters (S13i tests).
void negswift_raw_reset_stats(void);
int negswift_raw_stat_opens(void);
int negswift_raw_stat_unpacks(void);

#ifdef __cplusplus
}
#endif
