// Cru Media Player: darken line art (for animation). Finds edges with a Sobel
// filter and deepens only the dark side of each edge, so outlines get
// crisper without darkening flat colour.

//!HOOK MAIN
//!BIND HOOKED
//!DESC Cru: darken line art

#define STRENGTH 0.55

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    float tl = luma(HOOKED_texOff(vec2(-1.0, -1.0)).rgb);
    float t  = luma(HOOKED_texOff(vec2( 0.0, -1.0)).rgb);
    float tr = luma(HOOKED_texOff(vec2( 1.0, -1.0)).rgb);
    float l  = luma(HOOKED_texOff(vec2(-1.0,  0.0)).rgb);
    float r  = luma(HOOKED_texOff(vec2( 1.0,  0.0)).rgb);
    float bl = luma(HOOKED_texOff(vec2(-1.0,  1.0)).rgb);
    float b  = luma(HOOKED_texOff(vec2( 0.0,  1.0)).rgb);
    float br = luma(HOOKED_texOff(vec2( 1.0,  1.0)).rgb);
    float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
    float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
    float edge = clamp(length(vec2(gx, gy)) - 0.12, 0.0, 1.0);
    float darker = step(luma(c.rgb), (t + l + r + b) * 0.25);
    return vec4(c.rgb * (1.0 - STRENGTH * edge * darker), c.a);
}
