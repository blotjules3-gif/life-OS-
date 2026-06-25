//
//  Bubble.metal
//  TRANSLUCENT soap-bubble / glass shader (SwiftUI ShapeStyle fill on a Circle).
//
//  Reference look: glass spheres you can SEE THROUGH, vivid tint, a big crisp white
//  glossy highlight, a bright thin rim line all around (soap film), bottom light wrap.
//
//  KEY: translucency comes from ALPHA (low center, high rim) — the colour RGB stays a
//  vivid saturated tint (we do NOT mix white into the body, that's what washes it out).
//
//  Returns PREMULTIPLIED alpha (required by SwiftUI shaders).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[stitchable]] half4 bubble(
    float2 pos,
    float2 size,
    half4  tint,
    float  coreAlpha,    // center opacity — LOW = see-through glass
    float  rimAlpha,     // rim opacity — HIGH = dense soap-film edge
    float  specStrength,
    float  time,
    float  seed
) {
    float2 uv = (pos / size) * 2.0 - 1.0;   // -1..1, y down
    float  r  = length(uv);
    if (r > 1.0) { return half4(0.0); }

    float  z       = sqrt(max(0.0, 1.0 - r * r));
    float3 normal  = normalize(float3(uv, z));
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 lightDir = normalize(float3(-0.35, -0.62, 0.70));   // top-left

    float3 base  = float3(tint.rgb);
    float3 white = float3(1.0);

    float  fres = pow(1.0 - z, 2.0);   // 0 at center .. 1 at the rim

    // ---------- Colour: VIVID tint with directional volume (no white veil) ----------
    float  ndl    = dot(normal, lightDir);
    float  shade  = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);   // 0 shadow .. 1 lit
    float3 litCol = mix(base, white, 0.05);             // lit side, presque pas de blanc (reste vif)
    float3 darkCol = base * 0.50;                        // shadow side, profond mais coloré
    float3 col = mix(darkCol, litCol, shade);
    col = mix(col, base, fres * 0.60);                   // rim plus saturé (film de savon)
    // VIVIDNESS boost fort : on écarte la couleur du gris pour des teintes franches
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = clamp(mix(float3(lum), col, 1.90), 0.0, 1.0);   // néon : saturation forte

    // ---------- Glossy white highlights ----------
    float2 drift = float2(sin(time * 0.5 + seed) * 0.012, cos(time * 0.4 + seed) * 0.012);

    // Reflet réaliste : grand "softbox" doux allongé en haut-gauche (réflexion d'environnement)
    float2 sUV = (uv - (float2(-0.26, -0.44) + drift)) * float2(1.45, 0.82);   // ovale vertical
    float  softbox = smoothstep(0.52, 0.12, length(sUV)) * 0.78;

    // reflet net de la source lumineuse, dans le softbox
    float2 pUV = (uv - (float2(-0.30, -0.50) + drift)) * float2(1.10, 1.0);
    float  primaryGloss = softbox + smoothstep(0.13, 0.0, length(pUV)) * 0.65;

    // mini hotspot ultra net (étincelle mouillée)
    float  hotspot = smoothstep(0.045, 0.0, length(uv - (float2(-0.33, -0.55) + drift)));

    // phong sparkle
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 90.0) * specStrength;

    // ---------- Bright thin rim line (soap-film edge), brightest at the top ----------
    float  rimLine    = smoothstep(0.84, 0.985, r) * (1.0 - smoothstep(0.985, 1.0, r));
    float  rimTopBias = 0.45 + 0.55 * smoothstep(0.7, -1.0, uv.y);
    float  rimBright  = rimLine * rimTopBias;

    // bottom light wrap (light bends under the glass)
    float  bottomWrap = smoothstep(0.82, 1.0, r) * smoothstep(0.20, 1.0, uv.y) * 0.30;

    // ---------- Compose colour ----------
    col += white * (primaryGloss + hotspot + phong);
    col += white * (rimBright * 0.85 + bottomWrap);

    // ---------- Alpha: TRANSLUCENT center, opaque vivid rim + opaque light features ----------
    float alpha = mix(coreAlpha, rimAlpha, fres);
    alpha = max(alpha, rimBright * 0.90);
    alpha = max(alpha, (primaryGloss + hotspot + phong) * 0.95);
    alpha = max(alpha, bottomWrap * 0.70);
    alpha = clamp(alpha, 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
