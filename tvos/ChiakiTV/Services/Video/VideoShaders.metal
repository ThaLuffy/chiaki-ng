// SPDX-License-Identifier: AGPL-3.0-only
//
// SDR NV12 (BT.709) and HDR10 P010 (BT.2020 + SMPTE-2084 PQ) → fragment
// outputs, plus a fullscreen-quad vertex passthrough.
//
// HDR path notes
// --------------
// The PS5 emits HDR streams as BT.2020 limited-range Y'CbCr with the
// luma+chroma values PQ-encoded in 10 bits per channel
// (`lib/src/launchspec.c:81` `dynamicRange:HDR`). When the renderer
// configures the CAMetalLayer with `bgr10a2Unorm` + the Rec.2020 PQ
// colorspace (`CGColorSpace.itur_2100_PQ`), tvOS expects the pixels we
// write to *also* be PQ-encoded R'G'B' values — no inverse-PQ + tonemap
// + reapply-PQ round trip is necessary, which keeps the shader simple
// and avoids precision loss on the GPU.
//
// All we do for HDR is:
//   1. Sample the 16-bit Y / CbCr planes (P010 stores 10 bits in the
//      MSBs of a 16-bit slot; sampling as `r16Unorm` / `rg16Unorm` and
//      multiplying by `(65535 / 65472)` rebases the limited-range max
//      back to 1.0 — see `kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ`
//      pixel layout).
//   2. Apply the BT.2020 limited-range Y'CbCr → R'G'B' matrix.
//   3. Output R'G'B' directly. The colorspace tag on the metal layer
//      tells the compositor the values are PQ-encoded.

#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vs_quad(uint vid [[vertex_id]]) {
    // Fullscreen triangle strip:
    //   ( -1, -1, u=0,v=1 )
    //   (  1, -1, u=1,v=1 )
    //   ( -1,  1, u=0,v=0 )
    //   (  1,  1, u=1,v=0 )
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VSOut o;
    o.position = float4(positions[vid], 0.0, 1.0);
    o.uv = uvs[vid];
    return o;
}

// BT.709 video-range YCbCr → linear RGB. Adequate for SDR remote-play
// streams (NV12 input, `r8Unorm` + `rg8Unorm` plane textures).
fragment float4 fs_nv12(VSOut in [[stage_in]],
                        texture2d<float, access::sample> ytex [[texture(0)]],
                        texture2d<float, access::sample> uvtex [[texture(1)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float y = ytex.sample(s, in.uv).r;
    float2 uv = uvtex.sample(s, in.uv).rg;

    // Video-range expansion: y ∈ [16/255, 235/255], uv ∈ [16/255, 240/255].
    y  = (y  - 16.0/255.0) * (255.0/219.0);
    uv = (uv - 128.0/255.0) * (255.0/224.0);

    // BT.709
    float r = y + 1.5748 * uv.y;
    float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
    float b = y + 1.8556 * uv.x;
    return float4(r, g, b, 1.0);
}

// HDR10 P010 video-range BT.2020 → R'G'B' (still PQ-encoded). Consumed
// by an `bgr10a2Unorm` + Rec.2020 PQ MTKView. Plane textures are
// `r16Unorm` (Y plane) and `rg16Unorm` (CbCr plane) — P010 stores its
// 10 bits in the high bits of each 16-bit slot.
fragment float4 fs_p010_hdr(VSOut in [[stage_in]],
                            texture2d<float, access::sample> ytex [[texture(0)]],
                            texture2d<float, access::sample> uvtex [[texture(1)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // P010: 10 bits in the top of a 16-bit slot. `r16Unorm` returns the
    // sample as a value in [0, 1] where 1.0 corresponds to 65535. Scale
    // up so 1.0 corresponds to the 10-bit max (1023 << 6 = 65472), which
    // is the actual highest value the codec can emit.
    constexpr float p010_scale = 65535.0 / 65472.0;
    float y    = ytex.sample(s, in.uv).r * p010_scale;
    float2 uv  = uvtex.sample(s, in.uv).rg * p010_scale;

    // 10-bit limited-range expansion: y ∈ [64/1023, 940/1023],
    // uv ∈ [64/1023, 960/1023].
    y  = (y  - 64.0/1023.0) * (1023.0/876.0);
    uv = (uv - 512.0/1023.0) * (1023.0/896.0);

    // BT.2020 NCL Y'CbCr → R'G'B' (no transfer-function change — values
    // remain PQ-encoded for the bgr10a2 + Rec.2020 PQ output surface).
    float cb = uv.x;
    float cr = uv.y;
    float r = y + 1.4746 * cr;
    float g = y - 0.16455 * cb - 0.57135 * cr;
    float b = y + 1.8814 * cb;
    return float4(saturate(r), saturate(g), saturate(b), 1.0);
}
