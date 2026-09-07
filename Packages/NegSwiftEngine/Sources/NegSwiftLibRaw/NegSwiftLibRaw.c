#include "NegSwiftLibRaw.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef NEGSWIFT_HAS_LIBRAW
#include <Accelerate/Accelerate.h>
#include <dlfcn.h>
#include <libraw/libraw.h>
#endif

int negswift_raw_available(void) {
#ifdef NEGSWIFT_HAS_LIBRAW
    return 1;
#else
    return 0;
#endif
}

void negswift_raw_free(NegSwiftRawBuffer *buf) {
    if (buf == NULL) {
        return;
    }
    free(buf->pixels);
    buf->pixels = NULL;
    buf->count = 0;
    buf->width = 0;
    buf->height = 0;
    buf->orientation = 0;
    buf->used_half_size = 0;
    buf->user_qual = 0;
    buf->is_xtrans = 0;
}

void negswift_raw_free_thumb(NegSwiftRawThumb *thumb) {
    if (thumb == NULL) {
        return;
    }
    free(thumb->data);
    thumb->data = NULL;
    thumb->size = 0;
    thumb->width = 0;
    thumb->height = 0;
    thumb->orientation = 0;
    thumb->format = 0;
}

#ifndef NEGSWIFT_HAS_LIBRAW

int negswift_raw_probe(const char *path, int *width, int *height, int *orientation) {
    (void)path;
    if (width) {
        *width = 0;
    }
    if (height) {
        *height = 0;
    }
    if (orientation) {
        *orientation = 1;
    }
    return -1;
}

int negswift_raw_decode(const char *path, int half_size, NegSwiftRawBuffer *out, char *err, size_t err_len) {
    (void)path;
    (void)half_size;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return -1;
}

int negswift_raw_extract_thumb(const char *path, NegSwiftRawThumb *out, char *err, size_t err_len) {
    (void)path;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return -1;
}

NegSwiftRawHandle *negswift_raw_open(const char *path, char *err, size_t err_len) {
    (void)path;
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return NULL;
}

void negswift_raw_close(NegSwiftRawHandle *handle) {
    (void)handle;
}

int negswift_raw_handle_probe(const NegSwiftRawHandle *handle, int *width, int *height, int *orientation) {
    (void)handle;
    if (width) {
        *width = 0;
    }
    if (height) {
        *height = 0;
    }
    if (orientation) {
        *orientation = 1;
    }
    return -1;
}

int negswift_raw_handle_decode(
    NegSwiftRawHandle *handle,
    int half_size,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
) {
    (void)handle;
    (void)half_size;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return -1;
}

int negswift_raw_handle_decode_ex(
    NegSwiftRawHandle *handle,
    int half_size,
    int user_qual,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
) {
    (void)user_qual;
    return negswift_raw_handle_decode(handle, half_size, out, err, err_len);
}

int negswift_raw_handle_thumb(NegSwiftRawHandle *handle, NegSwiftRawThumb *out, char *err, size_t err_len) {
    (void)handle;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return -1;
}

void negswift_raw_reset_stats(void) {}

int negswift_raw_stat_opens(void) {
    return 0;
}

int negswift_raw_stat_unpacks(void) {
    return 0;
}

void negswift_raw_set_omp_threads(int n) {
    (void)n;
}

int negswift_raw_omp_max_threads(void) {
    return 1;
}

int negswift_raw_omp_num_procs(void) {
    return 1;
}

#else

struct NegSwiftRawHandle {
    libraw_data_t *raw;
    int unpacked;
    int thumb_unpacked;
};

static int g_opens = 0;
static int g_unpacks = 0;

static void fail_msg(char *err, size_t err_len, const char *msg) {
    if (err && err_len) {
        snprintf(err, err_len, "%s", msg);
    }
}

static int is_xtrans(const libraw_data_t *raw) {
    return raw->idata.filters == LIBRAW_XTRANS;
}

typedef void (*omp_set_num_threads_fn)(int);
typedef int (*omp_get_max_threads_fn)(void);
typedef int (*omp_get_num_procs_fn)(void);

static void *omp_sym(const char *name) {
    return dlsym(RTLD_DEFAULT, name);
}

void negswift_raw_set_omp_threads(int n) {
    if (n < 1) {
        n = 1;
    }
    char buf[16];
    snprintf(buf, sizeof(buf), "%d", n);
    setenv("OMP_NUM_THREADS", buf, 1);
    omp_set_num_threads_fn set = (omp_set_num_threads_fn)omp_sym("omp_set_num_threads");
    if (set) {
        set(n);
    }
}

int negswift_raw_omp_max_threads(void) {
    omp_get_max_threads_fn get = (omp_get_max_threads_fn)omp_sym("omp_get_max_threads");
    return get ? get() : 1;
}

int negswift_raw_omp_num_procs(void) {
    omp_get_num_procs_fn get = (omp_get_num_procs_fn)omp_sym("omp_get_num_procs");
    return get ? get() : 1;
}

static void apply_linear_params(libraw_data_t *raw, int half_size, int user_qual) {
    raw->params.output_color = 0; /* raw / sensor-native */
    raw->params.output_bps = 16;
    raw->params.gamm[0] = 1.0;
    raw->params.gamm[1] = 1.0;
    raw->params.no_auto_bright = 1;
    raw->params.use_camera_wb = 0;
    raw->params.use_auto_wb = 0;
    raw->params.user_mul[0] = 1.0f;
    raw->params.user_mul[1] = 1.0f;
    raw->params.user_mul[2] = 1.0f;
    raw->params.user_mul[3] = 1.0f;
    raw->params.adjust_maximum_thr = 0.0f;
    raw->params.user_flip = 0;
    raw->params.bright = 1.0f;
    raw->params.highlight = 0;
    if (user_qual >= 0) {
        raw->params.half_size = (half_size && !is_xtrans(raw)) ? 1 : 0;
        raw->params.user_qual = user_qual;
        return;
    }
    /* NegPy preview: Bayer half_size + LINEAR. X-Trans + linear aliases the
       6×6 CFA, so preview stays full-size and uses PPG (1-pass Markesteijn).
       Export / AUTO stays AHD (3-pass on X-Trans). */
    if (is_xtrans(raw)) {
        raw->params.half_size = 0;
        raw->params.user_qual = half_size ? NEGSWIFT_RAW_QUAL_PPG : NEGSWIFT_RAW_QUAL_AHD;
    } else if (half_size) {
        raw->params.half_size = 1;
        raw->params.user_qual = NEGSWIFT_RAW_QUAL_LINEAR;
    } else {
        raw->params.half_size = 0;
        raw->params.user_qual = NEGSWIFT_RAW_QUAL_AHD;
    }
}

static void write_probe(const libraw_data_t *raw, int *width, int *height, int *orientation) {
    if (width) {
        *width = (int)raw->sizes.iwidth;
    }
    if (height) {
        *height = (int)raw->sizes.iheight;
    }
    if (orientation) {
        int flip = raw->sizes.flip;
        *orientation = flip == 0 ? 1 : flip;
    }
}

static int copy_mem_image(const libraw_processed_image_t *img, float **out_pixels, size_t *out_count, char *err, size_t err_len) {
    int width = (int)img->width;
    int height = (int)img->height;
    int colors = (int)img->colors;
    int bits = (int)img->bits;
    if (width <= 0 || height <= 0 || colors < 1 || (bits != 8 && bits != 16)) {
        fail_msg(err, err_len, "Unsupported LibRaw output layout.");
        return -1;
    }

    size_t count = (size_t)width * (size_t)height * 3u;
    float *pixels = (float *)malloc(count * sizeof(float));
    if (pixels == NULL) {
        fail_msg(err, err_len, "Out of memory.");
        return -1;
    }

    if (bits == 16 && colors == 3) {
        const float scale = 1.0f / 65535.0f;
        vDSP_vfltu16((const unsigned short *)img->data, 1, pixels, 1, count);
        vDSP_vsmul(pixels, 1, &scale, pixels, 1, count);
    } else if (bits == 8 && colors == 3) {
        const float scale = 1.0f / 255.0f;
        vDSP_vfltu8(img->data, 1, pixels, 1, count);
        vDSP_vsmul(pixels, 1, &scale, pixels, 1, count);
    } else if (bits == 16) {
        const uint16_t *src = (const uint16_t *)img->data;
        const float scale = 1.0f / 65535.0f;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                const uint16_t *px = src + ((size_t)y * (size_t)width + (size_t)x) * (size_t)colors;
                size_t o = ((size_t)y * (size_t)width + (size_t)x) * 3u;
                uint16_t r = px[0];
                uint16_t g = colors > 1 ? px[1] : r;
                uint16_t b = colors > 2 ? px[2] : r;
                pixels[o] = (float)r * scale;
                pixels[o + 1] = (float)g * scale;
                pixels[o + 2] = (float)b * scale;
            }
        }
    } else {
        const uint8_t *src = img->data;
        const float scale = 1.0f / 255.0f;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                const uint8_t *px = src + ((size_t)y * (size_t)width + (size_t)x) * (size_t)colors;
                size_t o = ((size_t)y * (size_t)width + (size_t)x) * 3u;
                uint8_t r = px[0];
                uint8_t g = colors > 1 ? px[1] : r;
                uint8_t b = colors > 2 ? px[2] : r;
                pixels[o] = (float)r * scale;
                pixels[o + 1] = (float)g * scale;
                pixels[o + 2] = (float)b * scale;
            }
        }
    }

    *out_pixels = pixels;
    *out_count = count;
    return 0;
}

static int fill_thumb(libraw_data_t *raw, NegSwiftRawThumb *out, char *err, size_t err_len) {
    int flip = raw->sizes.flip;
    int mem_err = 0;
    libraw_processed_image_t *thumb = libraw_dcraw_make_mem_thumb(raw, &mem_err);
    if (thumb == NULL || mem_err != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, mem_err ? libraw_strerror(mem_err) : "LibRaw produced no thumbnail.");
        if (thumb) {
            libraw_dcraw_clear_mem(thumb);
        }
        return mem_err != 0 ? mem_err : -1;
    }

    out->width = (int)thumb->width;
    out->height = (int)thumb->height;
    out->orientation = flip == 0 ? 1 : flip;

    if (thumb->type == LIBRAW_IMAGE_JPEG) {
        uint8_t *copy = (uint8_t *)malloc(thumb->data_size);
        if (copy == NULL) {
            fail_msg(err, err_len, "Out of memory.");
            libraw_dcraw_clear_mem(thumb);
            memset(out, 0, sizeof(*out));
            return -1;
        }
        memcpy(copy, thumb->data, thumb->data_size);
        out->format = 1;
        out->data = copy;
        out->size = thumb->data_size;
        libraw_dcraw_clear_mem(thumb);
        return 0;
    }

    if (thumb->type == LIBRAW_IMAGE_BITMAP) {
        out->format = 2;
        out->data = NULL;
        out->size = 0;
        libraw_dcraw_clear_mem(thumb);
        return 0;
    }

    fail_msg(err, err_len, "Unsupported LibRaw thumbnail format.");
    libraw_dcraw_clear_mem(thumb);
    memset(out, 0, sizeof(*out));
    return -1;
}

static int ensure_unpack(NegSwiftRawHandle *handle, char *err, size_t err_len) {
    if (handle->unpacked) {
        return 0;
    }
    int rc = libraw_unpack(handle->raw);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        return rc;
    }
    handle->unpacked = 1;
    g_unpacks += 1;
    return 0;
}

NegSwiftRawHandle *negswift_raw_open(const char *path, char *err, size_t err_len) {
    if (path == NULL) {
        fail_msg(err, err_len, "Missing path.");
        return NULL;
    }
    NegSwiftRawHandle *handle = (NegSwiftRawHandle *)calloc(1, sizeof(NegSwiftRawHandle));
    if (handle == NULL) {
        fail_msg(err, err_len, "Out of memory.");
        return NULL;
    }
    handle->raw = libraw_init(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);
    if (handle->raw == NULL) {
        fail_msg(err, err_len, "libraw_init failed.");
        free(handle);
        return NULL;
    }
    int rc = libraw_open_file(handle->raw, path);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        libraw_close(handle->raw);
        free(handle);
        return NULL;
    }
    g_opens += 1;
    return handle;
}

void negswift_raw_close(NegSwiftRawHandle *handle) {
    if (handle == NULL) {
        return;
    }
    if (handle->raw) {
        libraw_close(handle->raw);
        handle->raw = NULL;
    }
    free(handle);
}

int negswift_raw_handle_probe(const NegSwiftRawHandle *handle, int *width, int *height, int *orientation) {
    if (width) {
        *width = 0;
    }
    if (height) {
        *height = 0;
    }
    if (orientation) {
        *orientation = 1;
    }
    if (handle == NULL || handle->raw == NULL) {
        return -1;
    }
    write_probe(handle->raw, width, height, orientation);
    return 0;
}

int negswift_raw_handle_decode(
    NegSwiftRawHandle *handle,
    int half_size,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
) {
    return negswift_raw_handle_decode_ex(handle, half_size, -1, out, err, err_len);
}

int negswift_raw_handle_decode_ex(
    NegSwiftRawHandle *handle,
    int half_size,
    int user_qual,
    NegSwiftRawBuffer *out,
    char *err,
    size_t err_len
) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (handle == NULL || handle->raw == NULL || out == NULL) {
        fail_msg(err, err_len, "Missing handle or output buffer.");
        return -1;
    }

    int rc = ensure_unpack(handle, err, err_len);
    if (rc != 0) {
        return rc;
    }

    apply_linear_params(handle->raw, half_size, user_qual);
    int used_half = handle->raw->params.half_size ? 1 : 0;
    int applied_qual = handle->raw->params.user_qual;
    int xtrans = is_xtrans(handle->raw);
    int flip = handle->raw->sizes.flip;

    libraw_free_image(handle->raw);
    rc = libraw_dcraw_process(handle->raw);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        return rc;
    }

    int mem_err = 0;
    libraw_processed_image_t *img = libraw_dcraw_make_mem_image(handle->raw, &mem_err);
    if (img == NULL || mem_err != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, mem_err ? libraw_strerror(mem_err) : "LibRaw produced no image.");
        if (img) {
            libraw_dcraw_clear_mem(img);
        }
        return mem_err != 0 ? mem_err : -1;
    }

    float *pixels = NULL;
    size_t count = 0;
    rc = copy_mem_image(img, &pixels, &count, err, err_len);
    int width = (int)img->width;
    int height = (int)img->height;
    libraw_dcraw_clear_mem(img);
    libraw_free_image(handle->raw);
    if (rc != 0) {
        return rc;
    }

    out->width = width;
    out->height = height;
    out->orientation = flip == 0 ? 1 : flip;
    out->pixels = pixels;
    out->count = count;
    out->used_half_size = used_half;
    out->user_qual = applied_qual;
    out->is_xtrans = xtrans;
    return 0;
}

int negswift_raw_handle_thumb(NegSwiftRawHandle *handle, NegSwiftRawThumb *out, char *err, size_t err_len) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (handle == NULL || handle->raw == NULL || out == NULL) {
        fail_msg(err, err_len, "Missing handle or output thumb.");
        return -1;
    }
    if (!handle->thumb_unpacked) {
        int rc = libraw_unpack_thumb(handle->raw);
        if (rc != LIBRAW_SUCCESS) {
            fail_msg(err, err_len, libraw_strerror(rc));
            return rc;
        }
        handle->thumb_unpacked = 1;
    }
    return fill_thumb(handle->raw, out, err, err_len);
}

int negswift_raw_probe(const char *path, int *width, int *height, int *orientation) {
    if (width) {
        *width = 0;
    }
    if (height) {
        *height = 0;
    }
    if (orientation) {
        *orientation = 1;
    }
    char err[8];
    NegSwiftRawHandle *handle = negswift_raw_open(path, err, sizeof(err));
    if (handle == NULL) {
        return -1;
    }
    int rc = negswift_raw_handle_probe(handle, width, height, orientation);
    negswift_raw_close(handle);
    return rc;
}

int negswift_raw_decode(const char *path, int half_size, NegSwiftRawBuffer *out, char *err, size_t err_len) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    NegSwiftRawHandle *handle = negswift_raw_open(path, err, err_len);
    if (handle == NULL) {
        return -1;
    }
    int rc = negswift_raw_handle_decode(handle, half_size, out, err, err_len);
    negswift_raw_close(handle);
    return rc;
}

int negswift_raw_extract_thumb(const char *path, NegSwiftRawThumb *out, char *err, size_t err_len) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    NegSwiftRawHandle *handle = negswift_raw_open(path, err, err_len);
    if (handle == NULL) {
        return -1;
    }
    int rc = negswift_raw_handle_thumb(handle, out, err, err_len);
    negswift_raw_close(handle);
    return rc;
}

void negswift_raw_reset_stats(void) {
    g_opens = 0;
    g_unpacks = 0;
}

int negswift_raw_stat_opens(void) {
    return g_opens;
}

int negswift_raw_stat_unpacks(void) {
    return g_unpacks;
}

#endif
