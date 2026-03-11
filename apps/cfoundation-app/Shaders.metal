// Shaders.metal
// Metal shader pipeline for c=foundation.
// Renders VICE Commodore frames with optional CRT effects.
//
// Frame input: BGRA8Unorm texture (VICE outputs ARGB; the byte order is
// handled by the MTLTextureDescriptor pixel format in VICEMetalView.m).

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen quad: two triangles from 4 vertices (triangle strip)
vertex VertexOut viceVertex(uint vid [[vertex_id]]) {
    const float2 positions[] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
    const float2 texCoords[] = { {0, 1}, {1, 1}, {0, 0}, {1, 0} };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// MARK: - Fragment params (matches VICEMetalView fragment params struct)

struct VICEFragParams {
    float  brightness;
    float  saturation;
    float  contrast;
    uint   scanlinesEnabled;
    float  scanlineTransparency;  // brightness of darkened rows (0=black, 1=off)
    uint   crtCurvatureEnabled;
    float  pad;                   // alignment
};

// MARK: - Fragment

fragment float4 viceFragment(
    VertexOut                  in        [[stage_in]],
    texture2d<float>           tex       [[texture(0)]],
    constant VICEFragParams   &p         [[buffer(0)]])
{
    constexpr sampler nearestSampler(
        filter::nearest,
        address::clamp_to_edge
    );
    constexpr sampler linearSampler(
        filter::linear,
        address::clamp_to_edge
    );

    float2 uv = in.texCoord;

    // Optional CRT barrel distortion
    if (p.crtCurvatureEnabled) {
        float2 center = uv - 0.5;
        float  dist   = dot(center, center);
        uv += center * dist * 0.08;
        if (any(uv < float2(0.0)) || any(uv > float2(1.0))) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    float4 color = tex.sample(nearestSampler, uv);

    // Scanline darkening: dim every odd pixel row
    if (p.scanlinesEnabled) {
        if (fmod(in.position.y, 2.0) < 1.0) {
            color.rgb *= p.scanlineTransparency;
        }
    }

    // Saturation adjustment
    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb  = mix(float3(lum), color.rgb, p.saturation);

    // Contrast
    color.rgb  = ((color.rgb - 0.5) * p.contrast) + 0.5;

    // Brightness
    color.rgb *= p.brightness;

    // Clamp
    color.rgb = saturate(color.rgb);

    return float4(color.rgb, 1.0);
}
