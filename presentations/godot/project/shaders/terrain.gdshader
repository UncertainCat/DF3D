shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
#include "res://shaders/terrain_batch_slice.gdshaderinc"
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
uniform bool textured = false;
uniform bool rock_backing = false;
uniform bool spattered = false;
uniform sampler2D spatter_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 spatter_cell = vec2(0.0);
uniform vec4 rock_backing_color : source_color = vec4(0.25, 0.25, 0.25, 1.0);
varying flat vec4 tile_centers;
void vertex() {
    tile_centers = CUSTOM2;
    batch_layer = CUSTOM0.x;
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    // Every triangle belongs to one source level/alternative. Clipping all its
    // vertices avoids rasterizing hidden levels and needs no geometry upload.
    if (!terrain_batch_visible(CUSTOM1.x)) { POSITION = vec4(2.0, 2.0, 2.0, 1.0); }
}
void fragment() {
    vec4 c = COLOR;
    if (rock_backing) { c = rock_backing_color; }
    vec2 tile_center = tile_centers.xy == vec2(0.0) ? UV : tile_centers.xy;
    if (textured) { c *= batch_texture_enabled ? sample_batch_grid_at(UV, albedo_cell, tile_center) : sample_world_grid_at(albedo_tex, UV, albedo_cell, tile_center); }
    if (spattered) {
        vec2 stain_center = tile_centers.zw == vec2(0.0) ? UV2 : tile_centers.zw;
        vec4 stain = sample_world_grid_at(spatter_tex, UV2, spatter_cell, stain_center);
        c.rgb = world_mix(c.rgb, stain.rgb * COLOR.rgb, stain.a);
    }
    ALBEDO = world_output(FRONT_FACING ? c.rgb : vec3(0.0));
}
