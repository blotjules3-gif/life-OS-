//
//  Bubble.metal
//  Bulle de savon : cœur coloré 3D BRILLANT + film irisé très fin au bord.
//
//  - Cœur coloré : teinte vive, fort relief 3D (ombre profonde pour le contraste glossy).
//  - Reflets : gros reflet blanc net + étincelle = surface mouillée/brillante (PAS mate).
//  - Film fin au bord : irisation arc-en-ciel (signature savon), coque très fine.
//
//  Translucidité par l'ALPHA. Retour PRÉMULTIPLIÉ (requis SwiftUI).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[stitchable]] half4 bubble(
    float2 pos,
    float2 size,
    half4  tint,
    float  coreAlpha,    // opacité du cœur coloré (bas = + transparent)
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
    float  fres  = pow(1.0 - z, 2.0);
    float  ndl   = dot(normal, lightDir);

    // ============ CŒUR COLORÉ 3D (sphère 360°, ombre profonde) ============
    float  shade   = clamp(ndl * 0.74 + 0.32, 0.0, 1.0);   // fort dégradé lumière->ombre = volume
    float3 litCol  = mix(base, white, 0.04);
    float3 darkCol = base * 0.26;                          // ombre très profonde -> relief net
    float3 body = mix(darkCol, litCol, shade);
    body = mix(body, base, fres * 0.42);
    float lum = dot(body, float3(0.299, 0.587, 0.114));
    body = clamp(mix(float3(lum), body, 1.95), 0.0, 1.0);  // néon
    body *= 0.74 + 0.26 * smoothstep(-0.5, 0.98, ndl);      // terminateur 3D
    // occlusion ambiante en bas (ancrage de la sphère, dessous plus sombre)
    body *= 1.0 - smoothstep(0.45, 1.0, r) * smoothstep(0.05, 1.0, uv.y) * 0.42;

    // film clair TRÈS FIN au bord : la couleur va presque jusqu'au bord
    float colorMask = smoothstep(0.99, 0.93, r);           // couleur jusqu'à ~0.93, film 0.93-1.0

    // ============ IRISATION film mince (forte, signature savon) ============
    float swirl  = length(uv * float2(1.0, 1.2)) * 6.5 + atan2(uv.y, uv.x) * 1.6;
    float iband  = fres * 8.0 + swirl + sin(time * 0.3 + seed) * 0.8 + seed * 2.0;
    float3 iri   = cos(iband + float3(0.0, 2.094, 4.188));
    float  iristr = 0.18 + 0.65 * smoothstep(0.10, 1.0, fres);   // partout, TRÈS fort au bord (film)
    body = clamp(body + iri * iristr * 0.40, 0.0, 1.0);

    // ============ REFLETS BRILLANTS (surface mouillée, PAS mate) ============
    float2 drift = float2(sin(time * 0.5 + seed) * 0.010, cos(time * 0.4 + seed) * 0.010);

    // gros reflet glossy net et BRILLANT (haut-gauche) — atteint le blanc pur
    float  primD    = length((uv - (float2(-0.30, -0.44) + drift)) * float2(1.18, 0.92));
    float  primary  = smoothstep(0.40, 0.04, primD);            // blob net 0..1
    // étincelle ultra nette
    float  hotspot  = smoothstep(0.085, 0.0, length(uv - (float2(-0.36, -0.52) + drift)));
    // petit reflet d'environnement bas-droite
    float  secondary = smoothstep(0.14, 0.0, length(uv - (float2(0.30, 0.26) - drift))) * 0.55;
    // phong serré (étincelle de bord)
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 140.0) * specStrength;

    // liseré fin et lumineux du bord (film)
    float  rimLine   = smoothstep(0.90, 0.99, r) * (1.0 - smoothstep(0.99, 1.0, r));
    float  rimBright = rimLine * (0.55 + 0.45 * smoothstep(0.7, -1.0, uv.y));

    // ============ COMPOSE ============
    float  gloss = primary + hotspot + phong + secondary;
    float3 col = body * colorMask;
    col += white * (gloss + rimBright * 0.95);             // reflets blancs brillants par-dessus
    col = clamp(col, 0.0, 1.0);

    // ============ ALPHA ============
    float colorA  = mix(coreAlpha, rimAlpha, fres) * colorMask;
    float filmA   = (1.0 - colorMask) * (0.04 + fres * 0.20);   // film très fin et clair
    float glossA  = gloss * 0.96 + rimBright * 0.95;            // reflets opaques = brillants
    float alpha   = clamp(max(max(colorA, filmA), glossA), 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
