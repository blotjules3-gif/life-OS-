#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static half3 hsv2rgb(float h, float s, float v) {
    float3 K = float3(1.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 p = abs(fract(float3(h) + K) * 6.0 - 3.0);
    float3 rgb = v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
    return half3(rgb);
}

// Sphère de gel glossy 3D, saturée et lumineuse (comme un rendu) + légère translucidité.
// Sortie premultipliée.
[[ stitchable ]]
half4 bubble(float2 position, float2 size, half4 tint, float2 light) {
    float2 p = (position / size) * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.0) { return half4(0.0h); }

    float z = sqrt(max(0.0, 1.0 - r * r));
    float3 N = normalize(float3(p, z));
    float3 L = normalize(float3(light, 0.85));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 Hh = normalize(L + V);

    float diff  = max(0.0, dot(N, L));
    float spec  = pow(max(0.0, dot(N, Hh)), 120.0);          // point chaud net
    float gloss = pow(max(0.0, dot(N, Hh)), 16.0) * 0.35;    // reflet large
    float rim   = pow(1.0 - z, 2.0);                         // Fresnel bord
    float topCatch = smoothstep(0.80, 1.0, r) * max(0.0, -p.y) * 0.6;

    // CORPS saturé avec volume (clair haut-gauche, sombre bas-droite)
    half3 col = tint.rgb * half(0.55 + 0.85 * diff);

    // bord lumineux (teinte éclaircie) — le "Fresnel" coloré de la réf
    half3 rimCol = mix(tint.rgb, half3(1.0h), 0.55h);
    col = mix(col, rimCol, half(rim * 0.6));

    // fine irisation seulement tout au bord (subtile)
    half3 irid = hsv2rgb(fract(rim * 1.1 + 0.55), 0.5, 1.0);
    col = mix(col, irid, half(smoothstep(0.72, 1.0, rim) * 0.20));

    // reflets blancs
    col += half3(half(spec));
    col += half3(half(gloss));
    col += half3(half(topCatch));

    // ALPHA : corps saturé (un peu translucide) -> bord opaque
    float a = clamp(0.66 + rim * 0.30 + spec, 0.0, 1.0);
    half af = half(a);
    return half4(col * af, af);
}
