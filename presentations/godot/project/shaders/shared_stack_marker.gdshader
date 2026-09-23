shader_type spatial;
render_mode unshaded;
#include "res://shaders/shared_stack.gdshaderinc"
void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    vec3 tile = floor(origin);
    vec2 interval = shared_stack_interval(tile, INSTANCE_CUSTOM.b, 2);
    vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Marker cubes are centered on a .12-high baseline, unlike cutout meshes.
    point.y = tile.y + 0.1 + interval.x + (point.y - tile.y - 0.1) * interval.y / 0.12;
    vec3 ground = shared_ground_support(origin);
    point.y += ground.y + dot(ground.xz, point.xz-origin.xz);
    POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(point, 1.0);
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a;
}
