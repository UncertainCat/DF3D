shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
#include "res://shaders/terrain_batch_slice.gdshaderinc"
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
uniform bool textured = false;
varying flat vec2 tile_center;
void vertex() {
    tile_center = CUSTOM2.xy;
    batch_layer = CUSTOM0.x;
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    // Every triangle belongs to one source level/alternative. Clipping all its
    // vertices avoids rasterizing hidden levels and needs no geometry upload.
    if (!terrain_batch_visible(CUSTOM1.x)) { POSITION = vec4(2.0, 2.0, 2.0, 1.0); }
}
void fragment() {
    vec4 c = COLOR;
    vec2 center = tile_center == vec2(0.0) ? UV : tile_center;
    if (textured) { c *= batch_texture_enabled ? sample_batch_grid_at(UV, albedo_cell, center) : sample_world_grid_at(albedo_tex, UV, albedo_cell, center); }
    ALBEDO = world_output(c.rgb); // Thin foliage has texture on BOTH sides.
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
