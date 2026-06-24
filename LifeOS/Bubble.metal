//
//  Bubble.metal
//  Glossy saturated glass-bubble shader (SwiftUI ShapeStyle fill on a Circle).
//
//  Goal = the reference: crisp, vivid, glossy spheres with a big clean white
//  highlight, a bright top rim, a dark saturated bottom, and a soft colored glow.
//  NOT milky / washed out.
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
    float  coreAlpha,    // center opacity (higher = more solid/saturated)
    float  rimAlpha,     // edge opacity
    float  specStrength, // sharpness of the sparkle
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

    // ---------- Volume: saturated color, dark bottom-right shadow, glossy lit pole ----------
    float ndl   = dot(normal, lightDir);
    float shade = clamp(ndl * 0.55 + 0.52, 0.0, 1.0);   // 0 = shadow side, 1 = lit side
    float3 darkCol = base * 0.46;                        // shadow, still colored
    float3 body = mix(darkCol, base, shade);             // -> pure saturated color in the light
    // glossy bright sheen near the lit pole (top-left)
    body = mix(body, mix(base, white, 0.55), smoothstep(0.72, 1.0, shade) * 0.55);

    // ---------- Glossy white highlights ----------
    float2 drift = float2(sin(time * 0.5 + seed) * 0.012,
                          cos(time * 0.4 + seed) * 0.012);

    // big primary gloss = soft halo + a BRIGHT crisp core (wet-glass reflection)
    float2 pUV = (uv - (float2(-0.18, -0.40) + drift)) * float2(1.08, 1.30);
    float  pd  = length(pUV);
    float  primaryGloss = smoothstep(0.70, 0.10, pd) * 0.62
                        + smoothstep(0.30, 0.02, pd) * 0.50;

    // sharp small hotspot for the wet sparkle
    float  hotspot = smoothstep(0.075, 0.0, length(uv - (float2(-0.30, -0.50) + drift))) * 1.1;

    // bright thin rim catch along the top arc
    float  rimBand = smoothstep(0.82, 0.995, r);
    float  rimTop  = rimBand * smoothstep(0.35, -1.0, uv.y);

    // phong sparkle on the curved rim
    float3 halfDir = normalize(lightDir + viewDir);
    float  phong   = pow(max(0.0, dot(normal, halfDir)), 90.0) * specStrength;

    // bottom light wrap (light bends under the sphere)
    float  bottomWrap = smoothstep(0.83, 1.0, r) * smoothstep(0.15, 1.0, uv.y) * 0.34;

    // fine bright glass edge all around (brightest at the top via rimTop)
    float  glassRim = smoothstep(0.88, 1.0, r) * 0.16;

    // ---------- Compose ----------
    float3 col = body;
    col += white * (primaryGloss + hotspot + phong);
    col += white * (rimTop * 0.80 + bottomWrap + glassRim);

    // ---------- Alpha: saturated bubbles fairly solid, light features opaque ----------
    float fres  = pow(1.0 - z, 2.2);
    float alpha = mix(coreAlpha, rimAlpha, fres);
    alpha = max(alpha, (primaryGloss + hotspot + phong + rimTop) * 0.95);
    alpha = max(alpha, bottomWrap * 0.8);
    alpha = clamp(alpha, 0.0, 1.0);

    return half4(half3(col) * half(alpha), half(alpha));
}
