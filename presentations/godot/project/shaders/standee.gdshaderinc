// Ground-aligned alpha silhouette geometry supplies world-space thickness.
#include "res://shaders/world_sampling.gdshaderinc"
#ifndef STANDEE_GHOST
#include "res://shaders/batch_sampling.gdshaderinc"
#endif
uniform sampler2D sprite_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 sprite_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 sprite_cell = vec2(0.0);
void fragment() {
#ifdef STANDEE_GHOST
    ALBEDO = sample_world_grid(sprite_tex, UV, sprite_cell).rgb * COLOR.rgb;
    ALPHA = COLOR.a;
#else
    ALBEDO = (batch_texture_enabled ? sample_batch_grid(UV, sprite_cell) : sample_world_grid(sprite_tex, UV, sprite_cell)).rgb * COLOR.rgb;
#endif
}
