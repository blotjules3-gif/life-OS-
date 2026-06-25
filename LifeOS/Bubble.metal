//
//  Bubble.metal
//  Bulle de savon 2 couches : cœur coloré translucide 3D + coque extérieure transparente.
//
//  - Cœur coloré : teinte vive, ombrage directionnel fort (relief 3D), s'estompe avant
//    le bord pour laisser apparaître la coque.
//  - Coque extérieure : verre clair transparent par-dessus, avec liseré lumineux,
//    reflets (softbox) et irisation film-mince (signature savon).
//
//  Translucidité par l'ALPHA. Retour en alpha PRÉMULTIPLIÉ (requis par SwiftUI).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[stitchable]] half4 bubble(
    float2 pos,
    float2 size,
    half4  tint,
    float  coreAlpha,    // opacité du cœur coloré (bas = + transparent)
    float  rimAlpha,     // opacité couleur vers le bord
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
    float  fres  = pow(1.0 - z, 2.0);            // 0 centre .. 1 bord
    float  ndl   = dot(normal, lightDir);

    // ============ COUCHE 1 — CŒUR COLORÉ 3D ============
    float  shade   = clamp(ndl * 0.62 + 0.44, 0.0, 1.0);   // fort contraste = relief 3D
    float3 litCol  = mix(base, white, 0.05);               // côté éclairé
    float3 darkCol = base * 0.38;                           // ombre profonde = volume
    float3 colorBody = mix(darkCol, litCol, shade);
    colorBody = mix(colorBody, base, fres * 0.50);
    // saturation néon
    float lum = dot(colorBody, float3(0.299, 0.587, 0.114));
    colorBody = clamp(mix(float3(lum), colorBody, 1.90), 0.0, 1.0);
    // terminateur interne : accentue la sphère 3D
    colorBody *= 0.80 + 0.20 * smoothstep(-0.35, 0.95, ndl);

    // le cœur coloré s'estompe AVANT le bord -> anneau extérieur clair (la coque)
    float colorMask = smoothstep(0.90, 0.62, r);           // 1 au centre, 0 sur l'anneau

    // ============ IRISATION film mince (signature savon) ============
    float swirl  = length(uv * float2(1.0, 1.2)) * 6.0 + atan2(uv.y, uv.x) * 1.5;
    float iband  = fres * 7.0 + swirl + sin(time * 0.3 + seed) * 0.7 + seed * 2.0;
    float3 iri   = cos(iband + float3(0.0, 2.094, 4.188));
    float  iristr = 0.14 + 0.50 * smoothstep(0.15, 1.0, fres);

    // ============ COUCHE 2 — COQUE EXTÉRIEURE TRANSPARENTE (reflets) ============
    float2 drift = float2(sin(time * 0.5 + seed) * 0.012, cos(time * 0.4 + seed) * 0.012);

    // reflet softbox (réflexion d'environnement sur la coque), haut-gauche
    float2 sUV     = (uv - (float2(-0.26, -0.44) + drift)) * float2(1.45, 0.82);
    float  softbox = smoothstep(0.52, 0.12, length(sUV)) * 0.80;
    // reflet net de la source
    float  primaryGloss = softbox + smoothstep(0.13, 0.0,
                          length((uv - (float2(-0.30, -0.50) + drift)) * float2(1.10, 1.0))) * 0.65;
    // étincelle ultra nette
    float  hotspot = smoothstep(0.045, 0.0, length(uv - (float2(-0.33, -0.55) + drift)));
    // phong
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 90.0) * specStrength;
    // 2e reflet plus bas-droite = réflexion interne du cœur (profondeur 2 couches)
    float  innerRefl = smoothstep(0.17, 0.0, length(uv - float2(0.20, 0.22))) * 0.35 * colorMask;

    // liseré lumineux de la coque (bord du verre), + fort en haut
    float  rimLine   = smoothstep(0.84, 0.985, r) * (1.0 - smoothstep(0.985, 1.0, r));
    float  rimBright = rimLine * (0.5 + 0.5 * smoothstep(0.7, -1.0, uv.y));
    // light wrap en bas
    float  bottomWrap = smoothstep(0.82, 1.0, r) * smoothstep(0.20, 1.0, uv.y) * 0.30;

    // ============ COMPOSE COULEUR ============
    float3 col = colorBody * colorMask;                    // couleur seulement au cœur
    col = clamp(col + iri * iristr * 0.32, 0.0, 1.0);      // film irisé (partout, fort au bord)
    col += white * (primaryGloss + hotspot + phong + innerRefl);
    col += white * (rimBright * 0.90 + bottomWrap);

    // ============ ALPHA — 2 couches ============
    float colorA   = mix(coreAlpha, rimAlpha, fres) * colorMask;          // cœur coloré translucide
    float shellGl  = (1.0 - colorMask) * (0.05 + fres * 0.22);            // coque : fine teinte verre claire
    float feat     = (primaryGloss + hotspot + phong) * 0.95
                   + rimBright * 0.90 + bottomWrap * 0.70 + innerRefl;    // reflets/liseré opaques
    float alpha    = clamp(max(max(colorA, shellGl), feat), 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
