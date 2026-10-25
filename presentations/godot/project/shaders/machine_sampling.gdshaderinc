#include "res://shaders/world_sampling.gdshaderinc"
#include "res://shaders/batch_sampling.gdshaderinc"
#include "res://shaders/terrain_batch_slice.gdshaderinc"
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 albedo_cell = vec2(0.0);
uniform sampler2D machine_positions : filter_nearest, repeat_disable;
varying flat vec2 tile_center;
varying flat vec2 machine_cell;
void vertex() {
    tile_center = CUSTOM2.xy;
    machine_cell = CUSTOM2.zw;
    batch_layer = CUSTOM0.x;
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    if (!terrain_batch_visible(CUSTOM1.x)) { POSITION = vec4(2.0, 2.0, 2.0, 1.0); }
}
vec4 sample_machine(vec2 uv, vec4 color) {
    vec2 shift = vec2(0.0);
    vec2 cell_uv = albedo_cell / vec2(textureSize(albedo_tex, 0));
    if (machine_cell.y >= 0.0) {
        int code = int(round(machine_cell.y));
        int direction = code / 3;
        int coordinate = code % 3;
        int position = int(round(textureLod(machine_positions, vec2(machine_cell.x, 0.5), 0.0).r));
        // Shader modulo may use floor semantics for negative values; DF uses
        // signed C++ remainder (truncation toward zero).
        if (code == 14) {
            shift = vec2(float(position % 2)*3.0,float(position / 2)*4.0)*cell_uv;
        } else if (code >= 12) {
            // DF selects frame two only for positive odd signed remainder.
            if (position > 0 && position % 2 == 1) {
                shift = code == 12 ? vec2(0.0, 2.0 * cell_uv.y) : vec2(cell_uv.x, 0.0);
            }
        } else {
            int phase = position == -129 ? 0 : (position < 0 ? -(abs(position) % 3) : position % 3);
            int target = direction == 1 || direction == 2 ? phase : 2 - phase;
            // Both installed stone/wood frames occupy adjacent rows on the same page.
            if (coordinate != target) { shift.y = cell_uv.y; }
        }
    }
    vec2 center = (tile_center == vec2(0.0) ? uv : tile_center) + shift;
    vec4 c = color * (batch_texture_enabled
        ? sample_batch_grid_at(uv + shift, albedo_cell, center)
        : sample_world_grid_at(albedo_tex, uv + shift, albedo_cell, center));
    return c;
}
