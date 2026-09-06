#include "NegSwiftLibRaw.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef NEGSWIFT_HAS_LIBRAW
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

int negswift_raw_decode(const char *path, NegSwiftRawBuffer *out, char *err, size_t err_len) {
    (void)path;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (err && err_len) {
        snprintf(err, err_len, "LibRaw is not linked in this build.");
    }
    return -1;
}

#else

static void fail_msg(char *err, size_t err_len, const char *msg) {
    if (err && err_len) {
        snprintf(err, err_len, "%s", msg);
    }
}

static void apply_linear_params(libraw_data_t *raw) {
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
    raw->params.user_qual = 3; /* AHD — NegPy AUTO on Bayer */
    raw->params.bright = 1.0f;
    raw->params.highlight = 0;
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
    if (path == NULL) {
        return -1;
    }
    libraw_data_t *raw = libraw_init(0);
    if (raw == NULL) {
        return -1;
    }
    int rc = libraw_open_file(raw, path);
    if (rc != LIBRAW_SUCCESS) {
        libraw_close(raw);
        return rc;
    }
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
    libraw_close(raw);
    return 0;
}

int negswift_raw_decode(const char *path, NegSwiftRawBuffer *out, char *err, size_t err_len) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    if (path == NULL || out == NULL) {
        fail_msg(err, err_len, "Missing path or output buffer.");
        return -1;
    }

    libraw_data_t *raw = libraw_init(0);
    if (raw == NULL) {
        fail_msg(err, err_len, "libraw_init failed.");
        return -1;
    }

    int rc = libraw_open_file(raw, path);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        libraw_close(raw);
        return rc;
    }

    rc = libraw_unpack(raw);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        libraw_close(raw);
        return rc;
    }

    apply_linear_params(raw);
    int flip = raw->sizes.flip;

    rc = libraw_dcraw_process(raw);
    if (rc != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, libraw_strerror(rc));
        libraw_close(raw);
        return rc;
    }

    int mem_err = 0;
    libraw_processed_image_t *img = libraw_dcraw_make_mem_image(raw, &mem_err);
    libraw_close(raw);
    raw = NULL;
    if (img == NULL || mem_err != LIBRAW_SUCCESS) {
        fail_msg(err, err_len, mem_err ? libraw_strerror(mem_err) : "LibRaw produced no image.");
        if (img) {
            libraw_dcraw_clear_mem(img);
        }
        return mem_err != 0 ? mem_err : -1;
    }

    int width = (int)img->width;
    int height = (int)img->height;
    int colors = (int)img->colors;
    int bits = (int)img->bits;
    if (width <= 0 || height <= 0 || colors < 1 || (bits != 8 && bits != 16)) {
        fail_msg(err, err_len, "Unsupported LibRaw output layout.");
        libraw_dcraw_clear_mem(img);
        return -1;
    }

    size_t count = (size_t)width * (size_t)height * 3u;
    float *pixels = (float *)malloc(count * sizeof(float));
    if (pixels == NULL) {
        fail_msg(err, err_len, "Out of memory.");
        libraw_dcraw_clear_mem(img);
        return -1;
    }

    if (bits == 16) {
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

    libraw_dcraw_clear_mem(img);
    out->width = width;
    out->height = height;
    out->orientation = flip == 0 ? 1 : flip;
    out->pixels = pixels;
    out->count = count;
    return 0;
}

#endif
