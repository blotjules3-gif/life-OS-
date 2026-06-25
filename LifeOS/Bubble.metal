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

    // ============ CHROME LIQUIDE — réflexion d'environnement (thème Argent) ============
    // Vraie matière chrome : on dérive la normale d'une GOUTTE organique bombée, on calcule
    // le vecteur de réflexion, et on échantillonne un STUDIO procédural (softbox brillantes,
    // colonnes, noir profond) déformé par la courbure. Le rebord (Fresnel) reflète fort.
    if (metal > 0.5) {
        // ---- forme ORGANIQUE : on déforme le disque en goutte (pas un cercle parfait)
        float ang = atan2(uv.y, uv.x);
        float wob = 1.0
                  - 0.045 * sin(ang * 2.0 + seed * 1.7)
                  - 0.030 * cos(ang * 3.0 - seed * 2.3)
                  - 0.022 * sin(ang * 5.0 + seed * 0.9);
        if (r > wob) { return half4(0.0); }            // hors de la goutte (bord net, pas de stroke)

        // ---- surface bombée : normale recalculée sur la goutte
        float rr = clamp(r / wob, 0.0, 1.0);           // 0 centre .. 1 bord
        float zz = sqrt(max(0.0, 1.0 - rr * rr));
        float3 N = normalize(float3(uv / wob, zz));
        float3 V = float3(0.0, 0.0, 1.0);
        float3 Rf = reflect(-V, N);                    // direction miroir
        float  t  = time * 0.10;                       // dérive lente des reflets

        // ---- ENVIRONNEMENT STUDIO échantillonné par la réflexion (mostly black + softboxes)
        float elev = -Rf.y;                            // +1 vers le haut de la goutte
        float azim = atan2(Rf.x, Rf.z) + t;
        float env  = 0.015;                            // studio NOIR profond
        // softbox brillante (bande en haut) — concentrée, pas étalée
        env += smoothstep(0.22, 0.50, elev) * (1.0 - smoothstep(0.78, 1.04, elev)) * 0.98;
        // reflet de sol étroit (bas)
        env += smoothstep(-0.94, -0.66, elev) * (1.0 - smoothstep(-0.50, -0.28, elev)) * 0.72;
        // colonnes lumineuses verticales (bords de softbox), seulement vers le haut
        float cols = pow(max(0.0, cos(azim * 1.5)), 10.0)
                   + pow(max(0.0, cos(azim * 1.5 + 3.14159)), 10.0);
        env += cols * 0.30 * smoothstep(0.05, 0.55, elev);

        // ---- Fresnel : le rebord reflète -> liseré chromé (pas un anneau blanc plein)
        float fres = pow(1.0 - max(0.0, dot(N, V)), 3.6);
        env += fres * 0.80;

        // ---- spéculaire net (key light studio en haut-gauche)
        float3 L = normalize(float3(-0.45, 0.72, 0.55));   // (uv y vers le bas -> +y = haut)
        float spec = pow(max(0.0, dot(Rf, L)), 240.0);
        env += spec * 1.3;

        // ---- CONTRASTE fort vers le noir (le chrome est sombre + reflets francs)
        float3 col = float3(env);
        col = pow(clamp(col, 0.0, 1.4), float3(1.55));     // assombrit les mid-tones -> plus de noir
        col *= float3(0.95, 0.97, 1.05);                   // argent froid
        col = clamp(col, 0.0, 1.0);
        return half4(half3(col), 1.0h);                    // métal OPAQUE
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

// ============ Dérive liquide (distortionEffect SwiftUI) ============
// Déplacement sinusoïdal MINUSCULE de la surface (< ~1.5 pt) pour donner une
// impression de métal liquide vivant — surtout pas de "jelly".
[[stitchable]] float2 liquidDrift(float2 pos, float time, float amp, float seed) {
    float2 d;
    d.x = amp * sin(pos.y * 0.022 + time * 0.55 + seed);
    d.y = amp * sin(pos.x * 0.019 + time * 0.47 + seed * 1.7);
    return pos + d;
}
