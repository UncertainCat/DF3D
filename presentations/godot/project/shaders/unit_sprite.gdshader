shader_type spatial;
render_mode cull_disabled, unshaded;
#include "standee.gdshaderinc"

#include "res://shaders/actor_animation_uniforms.gdshaderinc"
#include "res://shaders/actor_scale.gdshaderinc"
#include "res://shaders/actor_motion.gdshaderinc"
#include "res://shaders/shared_stack.gdshaderinc"
#include "res://shaders/actor_ground.gdshaderinc"
void vertex() {
    batch_layer = CUSTOM0.x;
    float address = COLOR.a;
    bool moving_actor = actor_animated && actor_motion_enabled && address > 0.0;
    float body_scale = actor_scale(COLOR);
    float bottom_padding = actor_bottom_padding(COLOR);
    if (actor_scale_data) COLOR = vec4(1.0);
    VERTEX = animated_actor_vertex(VERTEX, INSTANCE_CUSTOM, false);
    VERTEX.xz *= body_scale;
    vec3 ground = vec3(0.0);
    if (moving_actor) {
        vec2 stack = shared_stack_interval(actor_motion_record(address, 3).xyz, actor_motion_record(address, 2).z, 3);
        VERTEX.y *= stack.y / 0.12;
        vec3 position = actor_motion_position(address);
        ground = actor_ground_support(address, position);
        vec3 offset = mat3(MODEL_MATRIX) * VERTEX;
        offset.y += dot(ground.xz, offset.xz);
        VERTEX = inverse(mat3(MODEL_MATRIX)) * (position + vec3(0.0, 0.1 + stack.x + ground.y, 0.0) + offset - MODEL_MATRIX[3].xyz);
    } else if (!actor_animated && shared_stack_enabled) {
        vec2 stack = shared_stack_interval(floor(MODEL_MATRIX[3].xyz), INSTANCE_CUSTOM.b, 2);
        VERTEX.y = VERTEX.y * stack.y / 0.12 + stack.x;
        ground = shared_ground_support(MODEL_MATRIX[3].xyz);
        VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, ground.y + dot(ground.xz, (mat3(MODEL_MATRIX)*VERTEX).xz), 0.0);
    }
    if (actor_animated && (int(INSTANCE_CUSTOM.g + 0.5) == 13 || int(INSTANCE_CUSTOM.g + 0.5) == 14 || int(INSTANCE_CUSTOM.g + 0.5) == 22))
        VERTEX += inverse(mat3(MODEL_MATRIX)) * actor_world_offset(INSTANCE_CUSTOM);
}
