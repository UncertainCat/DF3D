shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
#include "res://shaders/terrain_batch_slice.gdshaderinc"
global uniform int machinery_calendar_tick;
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
varying flat vec2 tile_center;
varying flat vec2 frame_offset;
void vertex() {
    tile_center = CUSTOM2.xy;
    frame_offset = CUSTOM2.zw;
    batch_layer = CUSTOM0.x;
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    if (!terrain_batch_visible(CUSTOM1.x)) { POSITION = vec4(2.0, 2.0, 2.0, 1.0); }
}
void fragment() {
    // Native fortress rule: nonzero pump energy and (year_tick + 10*y1)%20 >=10.
    // Activity is encoded by a nonzero displacement; its sign holds row parity.
    int parity = frame_offset.x + frame_offset.y < 0.0 ? 10 : 0;
    vec2 shift = vec2(0.0);
    if (machinery_calendar_tick >= 0 && (machinery_calendar_tick + parity) % 20 >= 10) {
        shift = abs(frame_offset);
    }
    vec2 center = (tile_center == vec2(0.0) ? UV : tile_center) + shift;
    vec4 c = COLOR * (batch_texture_enabled
        ? sample_batch_grid_at(UV + shift, albedo_cell, center)
        : sample_world_grid_at(albedo_tex, UV + shift, albedo_cell, center));
    ALBEDO = world_output(c.rgb);
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
