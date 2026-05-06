// SPDX-License-Identifier: AGPL-3.0-only
//
// NV12 (and 10-bit P010 video-range) → BGRA fragment shader, plus a
// fullscreen-quad vertex passthrough.

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
// streams. HDR (BT.2020/PQ) is left for Phase 2 polish — see
// docs/architecture/video-pipeline.md §HDR10 metadata.
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
