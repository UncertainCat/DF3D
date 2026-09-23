shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
uniform bool textured = false;
void vertex() { batch_layer = CUSTOM0.x; }
void fragment() {
    vec4 c = COLOR;
    if (textured) { c *= batch_texture_enabled ? sample_batch_grid(UV, albedo_cell) : sample_world_grid(albedo_tex, UV, albedo_cell); }
    ALBEDO = c.rgb; // Thin foliage has texture on BOTH sides.
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
