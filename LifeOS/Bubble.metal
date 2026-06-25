//
//  Bubble.metal
//  Bulle de savon réaliste REMPLIE DE SIROP coloré.
//
//  - Film fin transparent + liseré lumineux (vraie bulle de savon).
//  - Intérieur : sirop coloré translucide (teinte de la catégorie) + marbrures
//    IRISÉES organiques (tourbillons arc-en-ciel via bruit fbm + domain warping).
//  - Reflet glossy. Relief 3D léger.
//
//  Retour PRÉMULTIPLIÉ (requis SwiftUI).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ----- bruit pour les marbrures organiques -----
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.02; a *= 0.5; }
    return v;
}

[[stitchable]] half4 bubble(
    float2 pos,
    float2 size,
    half4  tint,
    float  coreAlpha,    // opacité du sirop intérieur (bas = + transparent)
    float  rimAlpha,
    float  specStrength,
    float  time,
    float  seed
) {
    float2 uv = (pos / size) * 2.0 - 1.0;
    float  r  = length(uv);
    if (r > 1.0) { return half4(0.0); }

    float  z       = sqrt(max(0.0, 1.0 - r * r));
    float3 normal  = normalize(float3(uv, z));
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 lightDir = normalize(float3(-0.35, -0.62, 0.70));

    float3 base  = float3(tint.rgb);
    float3 white = float3(1.0);
    float  fres  = pow(1.0 - z, 2.4);
    float  ndl   = dot(normal, lightDir);

    // ============ SIROP coloré 3D (translucide) ============
    float  shade = clamp(ndl * 0.60 + 0.42, 0.0, 1.0);
    float3 syrup = mix(base * 0.40, mix(base, white, 0.05), shade);
    float  lum = dot(syrup, float3(0.299, 0.587, 0.114));
    syrup = clamp(mix(float3(lum), syrup, 1.85), 0.0, 1.0);          // saturation
    syrup *= 1.0 - smoothstep(0.5, 1.0, r) * smoothstep(0.10, 1.0, uv.y) * 0.30;   // occlusion bas (3D)

    // ============ MARBRURES IRISÉES (tourbillons organiques) ============
    float2 q  = uv * 1.6;
    float  w1 = fbm(q * 1.1 + float2(seed, seed * 1.3) + time * 0.05);
    float  w2 = fbm(q * 1.1 + float2(w1 * 1.9, w1 * 1.5) + 4.0);     // domain warping -> swirls
    float  iphase = w2 * 3.2 + fres * 2.0 + r * 1.8 + seed;
    float3 iri = 0.5 + 0.5 * cos(iphase * 6.2831 + float3(0.0, 2.094, 4.188));
    float  iriMask = smoothstep(1.0, 0.12, r) * 0.72 + 0.28;         // partout, + fort à l'intérieur

    // sirop + marbrure (l'arc-en-ciel ondule par-dessus, la teinte sirop reste lisible)
    float3 col = mix(syrup, iri, iriMask * 0.46);
    col = mix(col, syrup, 0.30);

    // ============ REFLETS + LISERÉ (film de savon) ============
    float2 drift = float2(sin(time * 0.5 + seed) * 0.010, cos(time * 0.4 + seed) * 0.010);
    float  primary = smoothstep(0.38, 0.04,
                     length((uv - (float2(-0.28, -0.42) + drift)) * float2(1.15, 0.90)));
    float  hotspot = smoothstep(0.05, 0.0, length(uv - (float2(-0.34, -0.50) + drift)));
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 130.0) * specStrength;
    // liseré fin et brillant du film
    float  rimLine   = smoothstep(0.90, 0.99, r) * (1.0 - smoothstep(0.99, 1.0, r));
    float  rimBright = rimLine * (0.6 + 0.4 * smoothstep(0.7, -1.0, uv.y));

    float  gloss = primary + hotspot + phong;
    col += white * (gloss + rimBright * 0.90);
    col = clamp(col, 0.0, 1.0);

    // ============ ALPHA : film transparent, sirop intérieur, liseré brillant ============
    float interiorA = mix(coreAlpha, rimAlpha, fres);
    float filmFade  = 1.0 - smoothstep(0.80, 0.93, r) * 0.45;        // anneau + transparent juste avant le liseré
    interiorA *= filmFade;
    float alpha = clamp(max(interiorA, max(rimBright * 0.90, gloss * 0.95)), 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
