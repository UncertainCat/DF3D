#ifndef DF3D_WORLD_COLOR
#define DF3D_WORLD_COLOR
global uniform bool native_world_color;
vec3 world_decode(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045)));
}
vec3 world_encode(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, greaterThan(c, vec3(0.0031308)));
}
vec3 world_output(vec3 linear_color) {
    return native_world_color ? world_encode(linear_color) : linear_color;
}
vec3 world_mix(vec3 a, vec3 b, float alpha) {
    return native_world_color ? world_decode(mix(world_encode(a), world_encode(b), alpha)) : mix(a,b,alpha);
}
#endif
