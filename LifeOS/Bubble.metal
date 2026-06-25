//
//  Bubble.metal
//  Vraie bulle de savon TRANSPARENTE dont le film est coloré (+ irisé).
//
//  - Centre see-through (on voit le fond à travers) — AUCUNE matière à l'intérieur.
//  - Le film/membrane porte la couleur de la catégorie, plus dense au bord (Fresnel),
//    avec une fine irisation arc-en-ciel sur le film.
//  - Reflets glossy + liseré brillant (la pellicule de savon).
//
//  Retour PRÉMULTIPLIÉ (requis SwiftUI).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

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
    for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.02; a *= 0.5; }
    return v;
}

[[stitchable]] half4 bubble(
    float2 pos,
    float2 size,
    half4  tint,
    float  coreAlpha,    // opacité du CENTRE (bas = très transparent)
    float  rimAlpha,     // opacité du FILM au bord (la couleur vit ici)
    float  specStrength,
    float  time,
    float  seed,
    float  metal         // 0 = bulle de savon colorée ; 1 = chrome liquide (thème Argent)
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
    float  fres  = pow(1.0 - z, 2.2);     // 0 centre .. 1 bord (épaisseur de film vue)
    float  ndl   = dot(normal, lightDir);

    // ============ FILM COLORÉ + irisation (pas de matière intérieure) ============
    // fine irisation qui ondule sur le film
    float  w = fbm(uv * 2.0 + time * 0.04 + seed);
    float  iphase = w * 2.0 + fres * 3.5 + atan2(uv.y, uv.x) * 0.4 + seed;
    float3 iri = 0.5 + 0.5 * cos(iphase * 6.2831 + float3(0.0, 2.094, 4.188));

    // la couleur de catégorie, vive ; l'irisation se mêle surtout vers le bord
    float3 film = clamp(base * 1.12, 0.0, 1.0);
    film = mix(film, iri, fres * 0.40);            // shimmer irisé sur le film
    film *= 0.88 + 0.12 * (ndl * 0.5 + 0.5);        // léger relief

    // ============ REFLETS BRILLANTS + LISERÉ (pellicule) ============
    float2 drift = float2(sin(time * 0.5 + seed) * 0.010, cos(time * 0.4 + seed) * 0.010);
    float  primary = smoothstep(0.34, 0.04,
                     length((uv - (float2(-0.30, -0.44) + drift)) * float2(1.18, 0.90)));
    float  hotspot = smoothstep(0.05, 0.0, length(uv - (float2(-0.34, -0.52) + drift)));
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 120.0) * specStrength;
    // liseré fin brillant du bord
    float  rimLine   = smoothstep(0.90, 0.99, r) * (1.0 - smoothstep(0.99, 1.0, r));
    float  rimBright = rimLine * (0.6 + 0.4 * smoothstep(0.7, -1.0, uv.y));

    // ============ MODE CHROME LIQUIDE (thème Argent) ============
    if (metal > 0.5) {
        float up = -normal.y;                         // +1 au sommet, -1 en bas
        // réflexion d'environnement façon miroir : ciel clair haut, bande NOIRE au milieu,
        // sol clair en bas (fort contraste = chrome poli)
        float sky    = smoothstep(0.18, 0.92, up);                 // reflet haut net
        float ground = smoothstep(-0.92, -0.55, up) * (1.0 - smoothstep(-0.55, -0.22, up));
        float ripple = 0.5 + 0.5 * sin(up * 6.0 + w * 3.0 + time * 0.2);
        float3 chrome = float3(0.015);                // base quasi noire
        chrome += float3(1.0) * sky * (0.78 + 0.22 * ripple);     // gros reflet blanc haut
        chrome += float3(0.95) * ground;                          // reflet du sol
        chrome += float3(1.0) * pow(fres, 1.35) * 1.05;           // rim chromé très brillant
        // reflets spéculaires nets (source lumineuse)
        float sphong = pow(max(0.0, dot(normal, normalize(lightDir + viewDir))), 220.0);
        chrome += white * (primary * 1.25 + hotspot * 1.3 + sphong);
        chrome *= float3(0.96, 0.98, 1.03);            // teinte argent froide
        chrome = clamp(chrome, 0.0, 1.0);
        return half4(half3(chrome), 1.0h);             // métal opaque
    }

    float  gloss = primary + hotspot + phong;
    float3 col = film;
    col += white * (gloss + rimBright * 0.90);
    col = clamp(col, 0.0, 1.0);

    // ============ ALPHA : bulle TRANSPARENTE, film coloré au bord ============
    // centre très see-through, film plus dense au bord (Fresnel)
    float filmA = mix(coreAlpha, rimAlpha, fres);
    float alpha = clamp(max(filmA, max(rimBright * 0.90, gloss * 0.96)), 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
