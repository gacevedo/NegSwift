// S12 lite compute kernels. Per-pixel math matches the Swift CPU path
// (LogNormalization / PrintCurve / PhotoLab / WorkingOETF), not unused
// NegPy desktop stages (dye, dodge/burn, hue, CLAHE, RL).

#include <metal_stdlib>
using namespace metal;

constant float kLog10Scale = 0.43429448190325182765;
constant float kInvGamma = 256.0 / 563.0;
constant float kLabEps = 0.008856;
constant float kLabKappa = 7.787;
constant float kLabOffset = 16.0 / 116.0;
constant float kSharpenShadowFloor = 1.0 / 3.0;
constant float kSharpenShadowLHi = 35.0;

float sharpen_shadow_gain(float l) {
    return kSharpenShadowFloor + (1.0 - kSharpenShadowFloor) * smoothstep(0.0, kSharpenShadowLHi, l);
}

struct NormalizeUniforms {
    float4 floors;
    float4 ceils;
};

struct ExposureUniforms {
    float4 pivots;
    float4 slopes;
    float4 curvatures;
    float4 cmyOffsets;
    float4 midtoneGamma;
    float4 shadowGrade;
    float4 highlightGrade;
    float4 aHL;
    float4 aSH;
    float4 dMinEff;
    float4 dMaxEff;
    float4 bpcBlack;
    float shadowDensity;
    float highlightDensity;
    float vStar;
    float gammaWidth;
    float zoneShCenter;
    float zoneHiCenter;
    float zoneK;
    uint mode;
    uint useSplit;
    uint useZone;
    float _pad0;
    float _pad1;
};

struct LabUniforms {
    float saturation;
    float skinProtection;
    float sharpen;
    float kernelRadius;
    float sharpenMasking;
    float gateLo;
    float gateHi;
    float overshootLight;
    float overshootDark;
    float maskTHi;
    float _pad0;
    float _pad1;
};

inline float3 log10_vec(float3 v) {
    return log(v) * kLog10Scale;
}

inline float softplus(float x) {
    return max(x, 0.0) + log(1.0 + exp(-abs(x)));
}

inline float fast_sigmoid(float x) {
    if (x >= 0.0) {
        return 1.0 / (1.0 + exp(-x));
    }
    float z = exp(x);
    return z / (1.0 + z);
}

inline int reflect101(int c, int n) {
    if (n <= 1) {
        return 0;
    }
    int v = c;
    int last = n - 1;
    while (v < 0 || v > last) {
        if (v < 0) {
            v = -v;
        } else {
            v = 2 * last - v;
        }
    }
    return v;
}

inline float3 rgb_to_lab(float3 rgb) {
    float r = max(rgb.r, 0.0);
    float g = max(rgb.g, 0.0);
    float b = max(rgb.b, 0.0);
    float x = (r * 0.5767309 + g * 0.1855540 + b * 0.1881852) / 0.95047;
    float y = (r * 0.2973769 + g * 0.6273491 + b * 0.0752741) / 1.00000;
    float z = (r * 0.0270343 + g * 0.0706872 + b * 0.9911085) / 1.08883;
    if (x > kLabEps) { x = pow(x, 1.0 / 3.0); } else { x = kLabKappa * x + kLabOffset; }
    if (y > kLabEps) { y = pow(y, 1.0 / 3.0); } else { y = kLabKappa * y + kLabOffset; }
    if (z > kLabEps) { z = pow(z, 1.0 / 3.0); } else { z = kLabKappa * z + kLabOffset; }
    return float3(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z));
}

inline float3 lab_to_rgb(float3 lab) {
    float y = (lab.x + 16.0) / 116.0;
    float x = lab.y / 500.0 + y;
    float z = y - lab.z / 200.0;
    float x3 = x * x * x;
    float y3 = y * y * y;
    float z3 = z * z * z;
    if (x3 > kLabEps) { x = x3; } else { x = (x - kLabOffset) / kLabKappa; }
    if (y3 > kLabEps) { y = y3; } else { y = (y - kLabOffset) / kLabKappa; }
    if (z3 > kLabEps) { z = z3; } else { z = (z - kLabOffset) / kLabKappa; }
    x *= 0.95047;
    y *= 1.00000;
    z *= 1.08883;
    float r = x * 2.0413690 + y * -0.5649464 + z * -0.3446944;
    float g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
    float b = x * 0.0134474 + y * -0.1183897 + z * 1.0154096;
    return max(float3(r, g, b), 0.0);
}

inline bool in_gamut_lab(float3 lab) {
    float y = (lab.x + 16.0) / 116.0;
    float x = lab.y / 500.0 + y;
    float z = y - lab.z / 200.0;
    float x3 = x * x * x;
    float y3 = y * y * y;
    float z3 = z * z * z;
    if (x3 > kLabEps) { x = x3; } else { x = (x - kLabOffset) / kLabKappa; }
    if (y3 > kLabEps) { y = y3; } else { y = (y - kLabOffset) / kLabKappa; }
    if (z3 > kLabEps) { z = z3; } else { z = (z - kLabOffset) / kLabKappa; }
    x *= 0.95047;
    y *= 1.00000;
    z *= 1.08883;
    float r = x * 2.0413690 + y * -0.5649464 + z * -0.3446944;
    float g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
    float b = x * 0.0134474 + y * -0.1183897 + z * 1.0154096;
    float tol = 1e-4;
    return r >= -tol && r <= 1.0 + tol && g >= -tol && g <= 1.0 + tol && b >= -tol && b <= 1.0 + tol;
}

inline float gamut_aware_chroma_eff(float3 lab, float saturation) {
    if (saturation <= 1.0) {
        return saturation;
    }
    if (in_gamut_lab(float3(lab.x, lab.y * saturation, lab.z * saturation))) {
        return saturation;
    }
    float lo = 1.0;
    float hi = saturation;
    bool still_ok = in_gamut_lab(lab);
    for (int i = 0; i < 10; i++) {
        float mid = (lo + hi) * 0.5;
        if (still_ok && in_gamut_lab(float3(lab.x, lab.y * mid, lab.z * mid))) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    float s_max = max(lo, 1.0 + 1e-4);
    float knee = s_max - 1.0;
    return 1.0 + knee * (1.0 - exp(-(saturation - 1.0) / knee));
}

inline float skin_weight(float3 lab) {
    float chroma = length(lab.yz);
    if (chroma < 2.0) {
        return 0.0;
    }
    float hue_deg = atan2(lab.z, lab.y) * (180.0 / M_PI_F);
    float dist = hue_deg - 52.0;
    dist = dist - 360.0 * round(dist / 360.0);
    float x = dist / 20.0;
    float w_hue = exp(-0.5 * x * x);
    float w_chroma = 1.0 - smoothstep(35.0, 60.0, chroma);
    float w_light = smoothstep(0.0, 15.0, lab.x) * (1.0 - smoothstep(95.0, 100.0, lab.x));
    return w_hue * w_chroma * w_light;
}

inline float3 skin_chroma_rein(float3 lab, float strength) {
    float ceiling = 22.0 / strength;
    float start = 0.6 * ceiling;
    float chroma = length(lab.yz);
    if (chroma <= start) {
        return lab;
    }
    float w = skin_weight(lab);
    if (w <= 0.0) {
        return lab;
    }
    float span = ceiling - start;
    float knee = start + span * (1.0 - exp(-(chroma - start) / span));
    float scale = (chroma + w * (knee - chroma)) / chroma;
    return float3(lab.x, lab.y * scale, lab.z * scale);
}

inline float lab_l(float3 rgb) {
    rgb = max(rgb, 0.0);
    float y = rgb.r * 0.2973769 + rgb.g * 0.6273491 + rgb.b * 0.0752741;
    if (y > kLabEps) {
        y = pow(y, 1.0 / 3.0);
    } else {
        y = kLabKappa * y + kLabOffset;
    }
    return 116.0 * y - 16.0;
}

kernel void normalize_main(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    constant NormalizeUniforms &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTex.get_width() || gid.y >= inputTex.get_height()) {
        return;
    }
    float3 color = inputTex.read(gid).rgb;
    float eps = 1e-6;
    float3 logc = log10_vec(max(color, float3(eps)));
    float3 res;
    for (int ch = 0; ch < 3; ch++) {
        float f = params.floors[ch];
        float c = params.ceils[ch];
        float denom = c - f;
        if (abs(denom) < eps) {
            denom = denom >= 0.0 ? eps : -eps;
        }
        res[ch] = (logc[ch] - f) / denom;
    }
    outputTex.write(float4(res, 1.0), gid);
}

kernel void exposure_main(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    constant ExposureUniforms &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTex.get_width() || gid.y >= inputTex.get_height()) {
        return;
    }
    float4 color = inputTex.read(gid);
    if (params.mode == 1u) {
        float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        color = float4(luma, luma, luma, color.a);
    }

    float3 dens;
    for (int ch = 0; ch < 3; ch++) {
        float val = color[ch] + params.cmyOffsets[ch];
        float v = params.slopes[ch] * (val - params.pivots[ch]) + params.curvatures[ch] * val * val;
        if (params.midtoneGamma[ch] != 0.0) {
            v = v + params.midtoneGamma[ch] * params.gammaWidth * tanh((v - params.vStar) / params.gammaWidth);
        }
        if (params.useSplit != 0u) {
            float wGsh = fast_sigmoid(params.zoneK * (v - params.zoneShCenter));
            float wGhi = 1.0 - fast_sigmoid(params.zoneK * (v - params.zoneHiCenter));
            v = v + params.shadowGrade[ch] * wGsh * (v - params.zoneShCenter)
                + params.highlightGrade[ch] * wGhi * (v - params.zoneHiCenter);
        }
        if (params.useZone != 0u) {
            float wZsh = fast_sigmoid(params.zoneK * (v - params.zoneShCenter));
            float wZhi = 1.0 - fast_sigmoid(params.zoneK * (v - params.zoneHiCenter));
            v = v + params.shadowDensity * wZsh + params.highlightDensity * wZhi;
        }
        float v1 = params.dMinEff[ch] + softplus(params.aHL[ch] * (v - params.dMinEff[ch])) / params.aHL[ch];
        dens[ch] = params.dMaxEff[ch] - softplus(params.aSH[ch] * (params.dMaxEff[ch] - v1)) / params.aSH[ch];
    }

    float3 transmittance = pow(float3(10.0), -dens);
    if (params.bpcBlack.x != 0.0 || params.bpcBlack.y != 0.0 || params.bpcBlack.z != 0.0) {
        transmittance = (transmittance - params.bpcBlack.xyz) / (float3(1.0) - params.bpcBlack.xyz);
    }
    transmittance = clamp(transmittance, 0.0, 1.0);
    if (params.mode == 1u) {
        float l = dot(transmittance, float3(0.2126, 0.7152, 0.0722));
        transmittance = float3(l, l, l);
    }
    outputTex.write(float4(transmittance, 1.0), gid);
}

kernel void lab_sharpen_h(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    constant LabUniforms &params [[buffer(0)]],
    const device float *kernelW [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inputTex.get_width();
    uint h = inputTex.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    int r = int(params.kernelRadius);
    float acc = 0.0;
    for (int i = -r; i <= r; i++) {
        int sx = reflect101(int(gid.x) + i, int(w));
        float l = lab_l(inputTex.read(uint2(sx, gid.y)).rgb);
        acc += l * kernelW[uint(i + r)];
    }
    float l_center = lab_l(inputTex.read(gid).rgb);
    outputTex.write(float4(acc, l_center, 0.0, 0.0), gid);
}

kernel void lab_sharpen_v(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    constant LabUniforms &params [[buffer(0)]],
    const device float *kernelW [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inputTex.get_width();
    uint h = inputTex.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    int r = int(params.kernelRadius);
    float acc = 0.0;
    for (int j = -r; j <= r; j++) {
        int sy = reflect101(int(gid.y) + j, int(h));
        acc += inputTex.read(uint2(gid.x, sy)).x * kernelW[uint(j + r)];
    }
    float l_orig = inputTex.read(gid).y;
    outputTex.write(float4(acc, l_orig, 0.0, 0.0), gid);
}

kernel void lab_apply(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::read> sharpenTex [[texture(1)]],
    texture2d<float, access::write> outputTex [[texture(2)]],
    constant LabUniforms &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inputTex.get_width();
    uint h = inputTex.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    int2 coords = int2(gid);
    float3 color = inputTex.read(gid).rgb;
    float3 lab = rgb_to_lab(color);
    if (params.saturation != 1.0) {
        float eff = gamut_aware_chroma_eff(lab, params.saturation);
        lab.y *= eff;
        lab.z *= eff;
    }
    if (params.skinProtection > 0.0) {
        lab = skin_chroma_rein(lab, params.skinProtection);
    }
    if (params.sharpen > 0.0) {
        float blur_l = sharpenTex.read(gid).x;
        float l = lab.x;
        float diff = l - blur_l;
        float t = saturate((abs(diff) - params.gateLo) / (params.gateHi - params.gateLo));
        float gate = t * t * (3.0 - 2.0 * t);
        float gain = params.sharpen * 2.5 * gate * sharpen_shadow_gain(l);
        if (params.sharpenMasking > 0.0) {
            float grad_box = 0.0;
            for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                    int2 p = clamp(coords + int2(i, j), int2(0), int2(w, h) - 1);
                    int2 px = clamp(p + int2(1, 0), int2(0), int2(w, h) - 1);
                    int2 mx = clamp(p - int2(1, 0), int2(0), int2(w, h) - 1);
                    int2 py = clamp(p + int2(0, 1), int2(0), int2(w, h) - 1);
                    int2 my = clamp(p - int2(0, 1), int2(0), int2(w, h) - 1);
                    float gx = (sharpenTex.read(uint2(px)).y - sharpenTex.read(uint2(mx)).y) * 0.5;
                    float gy = (sharpenTex.read(uint2(py)).y - sharpenTex.read(uint2(my)).y) * 0.5;
                    grad_box += sqrt(gx * gx + gy * gy);
                }
            }
            float thr = params.maskTHi * params.sharpenMasking;
            float u = saturate((grad_box / 9.0 - 0.5 * thr) / (thr - 0.5 * thr));
            gain *= u * u * (3.0 - 2.0 * u);
        }
        float l_min = 1e9;
        float l_max = -1e9;
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                int2 p = clamp(coords + int2(i, j), int2(0), int2(w, h) - 1);
                float lv = sharpenTex.read(uint2(p)).y;
                l_min = min(l_min, lv);
                l_max = max(l_max, lv);
            }
        }
        float l_new = l + diff * gain;
        l_new = clamp(l_new, l_min - params.overshootDark, l_max + params.overshootLight);
        lab.x = clamp(l_new, 0.0, 100.0);
    }
    outputTex.write(float4(clamp(lab_to_rgb(lab), 0.0, 1.0), 1.0), gid);
}

kernel void output_encode(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTex.get_width() || gid.y >= outputTex.get_height()) {
        return;
    }
    float3 color = clamp(inputTex.read(gid).rgb, 0.0, 1.0);
    outputTex.write(float4(pow(color, float3(kInvGamma)), 1.0), gid);
}

// S13b: inverse of CPU oriented() — rot90 CCW, then flips, then fine-rot
// (cv2 getRotationMatrix2D / warpAffine INTER_LINEAR BORDER_REPLICATE).
struct GeometryUniforms {
    int rotation;
    int flip_h;
    int flip_v;
    int src_width;
    int src_height;
    int dst_width;
    int dst_height;
    float fine_rotation;
};

inline float4 sample_replicate(
    texture2d<float, access::read> tex,
    float sx,
    float sy,
    int max_x,
    int max_y
) {
    float x0 = floor(sx);
    float y0 = floor(sy);
    float fx = sx - x0;
    float fy = sy - y0;
    int ix0 = clamp(int(x0), 0, max_x);
    int iy0 = clamp(int(y0), 0, max_y);
    int ix1 = clamp(int(x0) + 1, 0, max_x);
    int iy1 = clamp(int(y0) + 1, 0, max_y);
    float4 p00 = tex.read(uint2(ix0, iy0));
    float4 p10 = tex.read(uint2(ix1, iy0));
    float4 p01 = tex.read(uint2(ix0, iy1));
    float4 p11 = tex.read(uint2(ix1, iy1));
    float w00 = (1.0 - fx) * (1.0 - fy);
    float w10 = fx * (1.0 - fy);
    float w01 = (1.0 - fx) * fy;
    float w11 = fx * fy;
    return p00 * w00 + p10 * w10 + p01 * w01 + p11 * w11;
}

kernel void geometry_main(
    texture2d<float, access::read> inputTex [[texture(0)]],
    texture2d<float, access::write> outputTex [[texture(1)]],
    constant GeometryUniforms &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(params.dst_width) || gid.y >= uint(params.dst_height)) {
        return;
    }
    float px = float(gid.x);
    float py = float(gid.y);
    if (params.fine_rotation != 0.0) {
        float cx = float(params.dst_width) * 0.5;
        float cy = float(params.dst_height) * 0.5;
        float dx = px - cx;
        float dy = py - cy;
        float rad = params.fine_rotation * (3.14159265358979323846 / 180.0);
        float c = cos(rad);
        float s = sin(rad);
        px = cx + c * dx - s * dy;
        py = cy + s * dx + c * dy;
    }
    if (params.flip_v != 0) {
        py = float(params.dst_height - 1) - py;
    }
    if (params.flip_h != 0) {
        px = float(params.dst_width - 1) - px;
    }
    int k = params.rotation % 4;
    if (k < 0) {
        k += 4;
    }
    float sx;
    float sy;
    if (k == 0) {
        sx = px;
        sy = py;
    } else if (k == 1) {
        sx = float(params.dst_height - 1) - py;
        sy = px;
    } else if (k == 2) {
        sx = float(params.dst_width - 1) - px;
        sy = float(params.dst_height - 1) - py;
    } else {
        sx = py;
        sy = float(params.dst_width - 1) - px;
    }
    int max_x = params.src_width - 1;
    int max_y = params.src_height - 1;
    outputTex.write(sample_replicate(inputTex, sx, sy, max_x, max_y), gid);
}
