shader_type spatial;
render_mode unshaded;
#include "res://shaders/actor_motion.gdshaderinc"
#include "res://shaders/shared_stack.gdshaderinc"
#include "res://shaders/actor_ground.gdshaderinc"
void vertex() {
    float address = COLOR.a;
    COLOR.a = 1.0;
    if (actor_motion_enabled && address > 0.0) {
        vec2 stack = shared_stack_interval(actor_motion_record(address, 3).xyz, actor_motion_record(address, 2).z, 3);
        vec3 point = actor_motion_position(address) + vec3(VERTEX.x, 0.1 + stack.x + (VERTEX.y / 0.8 + 0.5) * stack.y, VERTEX.z);
        vec3 ground = actor_ground_support(address, actor_motion_position(address));
        point.y += ground.y + dot(ground.xz, VERTEX.xz);
        POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(point, 1.0);
    }
}
void fragment() { ALBEDO = COLOR.rgb; }
