shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
uniform bool textured = false;
uniform bool rock_backing = false;
uniform bool spattered = false;
uniform sampler2D spatter_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 spatter_cell = vec2(0.0);
uniform vec4 rock_backing_color : source_color = vec4(0.25, 0.25, 0.25, 1.0);
void vertex() { batch_layer = CUSTOM0.x; }
void fragment() {
    vec4 c = COLOR;
    if (rock_backing) { c = rock_backing_color; }
    if (textured) { c *= batch_texture_enabled ? sample_batch_grid(UV, albedo_cell) : sample_world_grid(albedo_tex, UV, albedo_cell); }
    if (spattered) {
        vec4 stain = sample_world_grid(spatter_tex, UV2, spatter_cell);
        c.rgb = mix(c.rgb, stain.rgb * COLOR.rgb, stain.a);
    }
    ALBEDO = FRONT_FACING ? c.rgb : vec3(0.0);
}
