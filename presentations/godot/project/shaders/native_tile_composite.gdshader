shader_type spatial;
render_mode unshaded, cull_disabled;
// Reference top-down compositor. The world renderer does not use this path yet.
// Inputs retain encoded RGB bytes: no source_color conversion before blending.
uniform sampler2D background_tex : filter_nearest, repeat_disable;
uniform sampler2D foreground_tex : filter_nearest, repeat_disable;
uniform int tile_pixels = 32;
uniform int source_tile_pixels = 32;
vec3 native_decode_srgb(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)),
               greaterThan(c, vec3(0.04045)));
}
void fragment() {
    ivec2 dimensions = textureSize(background_tex, 0);
    vec2 cells = vec2(dimensions / source_tile_pixels);
    ivec2 cell = ivec2(floor(UV * cells));
    ivec2 pixel = ivec2(floor(fract(UV * cells) * float(tile_pixels) + 0.001));
    // Native NEAREST maps from the destination pixel's leading edge, not center.
    ivec2 coord = cell * source_tile_pixels + pixel * source_tile_pixels / tile_pixels;
    coord = clamp(coord, ivec2(0), dimensions - ivec2(1));
    vec4 background = texelFetch(background_tex, coord, 0);
    vec4 foreground = texelFetch(foreground_tex, coord, 0);
    // Native SDL output quantizes after each layer. Quantize before decoding,
    // otherwise the HDR intermediate can move near-half values across a byte.
    vec3 encoded = floor(mix(background.rgb, foreground.rgb, foreground.a) * 255.0 + 0.5) / 255.0;
    ALBEDO = native_decode_srgb(encoded);
}
