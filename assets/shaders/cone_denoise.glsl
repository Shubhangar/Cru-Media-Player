// Cone Player: soften noise. A small edge-preserving (bilateral) blur:
// neighbours that look alike are averaged, edges stay sharp. Good for
// grainy or heavily compressed video.

//!HOOK MAIN
//!BIND HOOKED
//!DESC Cone: soften noise

#define SIMILARITY 60.0

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 sum = c.rgb;
    float total = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            vec3 s = HOOKED_texOff(vec2(float(x), float(y))).rgb;
            vec3 d = s - c.rgb;
            float w = exp(-dot(d, d) * SIMILARITY);
            sum += s * w;
            total += w;
        }
    }
    return vec4(sum / total, c.a);
}
