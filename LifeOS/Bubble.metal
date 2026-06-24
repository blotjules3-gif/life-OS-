//
//  Bubble.metal
//  Real soap-bubble shader. Used as a ShapeStyle fill on a SwiftUI Circle.
//
//  It paints, per pixel, a translucent tinted glass sphere with:
//    - directional 3D volume (lit top-left, shadow bottom-right)
//    - Fresnel film (rim more saturated + denser, like real soap)
//    - a big soft glossy white highlight + a sharp hotspot (wet glass)
//    - a phong sparkle on the rim
//    - inner white rim glow + bottom light wrap
//    - controlled alpha so the background shows through (real translucency)
//
//  Returns PREMULTIPLIED alpha (required by SwiftUI shaders).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[stitchable]] half4 bubble(
    float2 pos,          // pixel position in the shape's local space (0..size)
    float2 size,         // bubble bounding box (square)
    half4  tint,         // jewel-tone base color
    float  coreAlpha,    // center translucency  (lower = more see-through)
    float  rimAlpha,     // edge density / color presence at the rim
    float  specStrength, // sharpness of the phong sparkle
    float  time,         // seconds, for a subtle living shimmer
    float  seed          // per-bubble random so they shimmer out of sync
) {
    // Normalized coords, center origin, range about -1..1
    float2 uv = (pos / size) * 2.0 - 1.0;
    float  r  = length(uv);

    // The Circle shape already clips + anti-aliases the outer edge,
    // so we only need to guard against NaN past the rim.
    if (r > 1.0) { return half4(0.0); }

    // Fake hemisphere normal (gives the sphere its volume)
    float  z      = sqrt(max(0.0, 1.0 - r * r));
    float3 normal = normalize(float3(uv, z));
    float3 viewDir = float3(0.0, 0.0, 1.0);

    // Main light: top-left, slightly toward the viewer
    float3 lightDir = normalize(float3(-0.5, -0.6, 0.85));

    // Directional shading so the bottom-right falls into shadow (3D volume)
    float ndl     = dot(normal, lightDir);
    float diffuse = ndl * 0.5 + 0.5;              // 0 = shadow side, 1 = lit side

    // Fresnel: the rim of a soap bubble is brighter and denser
    float fres = pow(1.0 - z, 2.4);

    // ---- Body color: keep the jewel tone vivid, shade for volume ----
    float3 base    = float3(tint.rgb);
    float3 litCol  = mix(base, float3(1.0), 0.32);   // lit side, a touch brighter
    float3 shadow  = base * 0.52;                     // shadow side, still colorful
    float3 body    = mix(shadow, litCol, diffuse);
    body           = mix(body, base, 0.30);           // pull saturation back to the core

    // Subsurface scattering : la gélatine s'illumine de l'intérieur, plus clair vers le
    // bas où la lumière du haut ressort du gel
    float centerGlow = smoothstep(0.0, 0.90, z) * 0.15;
    body = mix(body, litCol, centerGlow);
    float subsurface = smoothstep(-0.25, 1.0, uv.y) * smoothstep(1.0, 0.15, r) * 0.16;
    body = mix(body, mix(base, float3(1.0), 0.55), subsurface);

    float3 white = float3(1.0);

    // ---- Glossy highlights (the wet-glass look) ----
    // A slow shimmer so the highlight feels alive
    float2 drift = float2(sin(time * 0.5 + seed) * 0.02,
                          cos(time * 0.4 + seed) * 0.02);

    // Gros reflet primaire doux, en haut à gauche — légèrement allongé (gel mouillé),
    // avec un cœur plus net dans le halo doux = reflet plus réaliste
    float2 primUV       = (uv - (float2(-0.28, -0.40) + drift)) * float2(1.0, 1.22);
    float  primaryD     = length(primUV);
    float  primaryGloss = smoothstep(0.50, 0.0, primaryD) * 0.55
                        + smoothstep(0.20, 0.0, primaryD) * 0.45;

    // Petit hotspot net juste à côté
    float  hotD  = length(uv - (float2(-0.14, -0.24) + drift));
    float  hotspot = smoothstep(0.10, 0.0, hotD);

    // Reflet secondaire doux en bas à droite (rebond d'environnement → réalisme)
    float  secD = length((uv - (float2(0.34, 0.32) - drift)) * float2(1.0, 1.18));
    float  secondary = smoothstep(0.32, 0.0, secD) * 0.20;

    // Phong un peu plus doux que du verre (rendu gélatine)
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 55.0) * specStrength;

    // Light wrapping around the bottom rim
    float bottomWrap = smoothstep(0.80, 1.0, r) * smoothstep(0.0, 1.0, uv.y) * 0.45;

    // Inner white rim glow (glows white from the border inward)
    float innerGlow = smoothstep(0.52, 0.96, r) * (1.0 - smoothstep(0.97, 1.0, r));

    // ---- Compose color ----
    float3 col = body;
    col += white * (primaryGloss + hotspot + phong + secondary);
    col += white * bottomWrap;
    col  = mix(col, white, innerGlow * 0.32);
    col  = mix(col, white, fres * 0.22);

    // ---- Alpha: translucent core, denser Fresnel rim ----
    float alpha = mix(coreAlpha, rimAlpha, fres);
    // light features stay opaque so they read as real light, not tinted glass
    alpha = max(alpha, (primaryGloss + hotspot + phong + secondary) * 0.9);
    alpha = max(alpha, innerGlow * rimAlpha);
    alpha = max(alpha, bottomWrap * 0.8);

    // Premultiplied output
    return half4(half3(col) * half(alpha), half(alpha));
}
