#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Sphère de gel/verre BRILLANTE et SATURÉE (comme le rendu 3D de la réf).
// Corps coloré opaque + gros reflet haut + croissant lumineux en bas + bord net.
[[ stitchable ]]
half4 bubble(float2 position, float2 size, half4 tint, float2 light) {
    float2 p = (position / size) * 2.0 - 1.0;        // -1..1, y vers le bas
    float r = length(p);
    if (r > 1.0) { return half4(0.0h); }

    float z = sqrt(max(0.0, 1.0 - r * r));
    float3 N = normalize(float3(p, z));
    float3 L = normalize(float3(light, 0.8));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 Hh = normalize(L + V);

    float diff  = clamp(dot(N, L) * 0.55 + 0.52, 0.0, 1.0);  // éclairage enveloppant (haut clair)
    float spec  = pow(max(0.0, dot(N, Hh)), 200.0);          // hotspot net
    float broad = pow(max(0.0, dot(N, Hh)), 9.0) * 0.5;      // grand reflet doux
    float fres  = pow(1.0 - z, 2.6);                          // bord (Fresnel)

    // Croissant lumineux EN BAS : la lumière traverse le verre et ressort en bas
    float3 Lb = normalize(float3(0.05, 1.0, -0.25));
    float back = pow(max(0.0, dot(N, Lb)), 3.0) * smoothstep(0.45, 1.0, r) * 1.4;

    // Corps saturé avec volume 3D
    half3 body = tint.rgb * half(0.60 + 0.65 * diff);
    // bord éclairci (verre)
    half3 rimc = mix(tint.rgb, half3(1.0h), 0.62h);
    half3 col  = mix(body, rimc, half(fres * 0.55));
    // reflets blancs
    col += half3(half(spec + broad));
    // croissant bas (teinte très claire/blanche)
    col += mix(tint.rgb, half3(1.0h), 0.75h) * half(back);

    // Saturé/opaque (un poil de translucidité au tout bord)
    float a = clamp(0.92 + fres * 0.08, 0.0, 1.0);
    half af = half(a);
    return half4(col * af, af);
}
