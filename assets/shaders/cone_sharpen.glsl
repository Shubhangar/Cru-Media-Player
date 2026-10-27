// Cru Media Player: adaptive sharpen.
// Contrast-adaptive weights after AMD FidelityFX CAS (MIT): sharpens soft
// detail while leaving already-crisp edges alone, so no halos.

//!HOOK MAIN
//!BIND HOOKED
//!DESC Cru: adaptive sharpen

#define SHARPNESS 0.6

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 e = c.rgb;
    vec3 b = HOOKED_texOff(vec2( 0.0, -1.0)).rgb;
    vec3 d = HOOKED_texOff(vec2(-1.0,  0.0)).rgb;
    vec3 f = HOOKED_texOff(vec2( 1.0,  0.0)).rgb;
    vec3 h = HOOKED_texOff(vec2( 0.0,  1.0)).rgb;
    vec3 mn = min(min(min(d, e), min(f, b)), h);
    vec3 mx = max(max(max(d, e), max(f, b)), h);
    vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-5)), 0.0, 1.0));
    vec3 w = amp * (-1.0 / mix(8.0, 5.0, SHARPNESS));
    vec3 outc = (b * w + d * w + f * w + h * w + e) / (1.0 + 4.0 * w);
    return vec4(clamp(outc, 0.0, 1.0), c.a);
}
