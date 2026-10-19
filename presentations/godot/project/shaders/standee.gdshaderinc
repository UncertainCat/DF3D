// Ground-aligned alpha silhouette geometry supplies world-space thickness.
#include "res://shaders/world_sampling.gdshaderinc"
#ifndef STANDEE_GHOST
#include "res://shaders/batch_sampling.gdshaderinc"
#endif
uniform sampler2D sprite_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 sprite_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 sprite_cell = vec2(0.0);
varying flat vec2 sprite_tile_center;
void fragment() {
    vec2 tile_center = sprite_tile_center == vec2(0.0) ? UV : sprite_tile_center;
#ifdef STANDEE_GHOST
    vec4 texel = sample_world_grid_at(sprite_tex, UV, sprite_cell, tile_center);
    ALBEDO = world_output(texel.rgb * COLOR.rgb);
    ALPHA = texel.a * COLOR.a;
#else
    vec4 texel = batch_texture_enabled ? sample_batch_grid_at(UV, sprite_cell, tile_center) : sample_world_grid_at(sprite_tex, UV, sprite_cell, tile_center);
    ALBEDO = world_output(texel.rgb * COLOR.rgb);
#ifdef FURNITURE_ALPHA
    ALPHA = texel.a * COLOR.a;
#endif
#endif
}
