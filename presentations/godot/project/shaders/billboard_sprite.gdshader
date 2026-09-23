shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://shaders/world_sampling.gdshaderinc"
uniform sampler2D sprite_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 sprite_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 sprite_cell = vec2(0.0);
uniform bool use_instance_ceiling = false;
uniform float ceiling_y = 1000000.0;
varying float world_height;
varying flat float clip_height;
#include "res://shaders/actor_animation_uniforms.gdshaderinc"
#include "res://shaders/actor_scale.gdshaderinc"
#include "res://shaders/actor_motion.gdshaderinc"
#include "res://shaders/shared_stack.gdshaderinc"
#include "res://shaders/actor_ground.gdshaderinc"
void vertex() {
    float address = COLOR.a;
    bool moving_actor = actor_animated && actor_motion_enabled && address > 0.0;
    vec3 anchor = MODEL_MATRIX[3].xyz;
    vec2 stack = vec2(0.0, length(MODEL_MATRIX[1].xyz) * 0.12);
    vec3 ground = vec3(0.0);
    if (moving_actor) {
        vec3 tile = actor_motion_record(address, 3).xyz;
        stack = shared_stack_interval(tile, actor_motion_record(address, 2).z, 3);
        anchor = actor_motion_position(address) + vec3(0.0, 0.1 + stack.x, 0.0);
        ground = actor_ground_support(address, actor_motion_position(address));
    } else if (!actor_animated && shared_stack_enabled) {
        stack = shared_stack_interval(floor(anchor), INSTANCE_CUSTOM.b, 2);
        ground = shared_ground_support(anchor);
        anchor.y += stack.x;
    }
    anchor.y += ground.y;
    float scaled_ceiling = COLOR.b;
    float body_scale = actor_scale(COLOR);
    float bottom_padding = actor_bottom_padding(COLOR);
    if (actor_scale_data) COLOR = vec4(1.0);
    VERTEX = animated_actor_vertex(VERTEX, INSTANCE_CUSTOM, true);
    VERTEX.xz *= body_scale;
    // Instance basis holds stable dimensions. Camera movement never rewrites it.
    float width = length(MODEL_MATRIX[0].xyz);
    float height = length(MODEL_MATRIX[2].xyz);
    float depth = clamp(stack.y, 0.015, 0.045) / 0.12;
    vec3 right = MAIN_CAM_INV_VIEW_MATRIX[0].xyz;
    vec3 up = MAIN_CAM_INV_VIEW_MATRIX[1].xyz;
    vec3 front = MAIN_CAM_INV_VIEW_MATRIX[2].xyz;
    float lift = clamp(up.y, 0.0, 1.0);
    vec3 point = anchor + right * (VERTEX.x * width)
        + up * ((-VERTEX.z + (0.5 - bottom_padding) * lift * body_scale) * height) + front * (VERTEX.y * depth);
    // Pitch blending must not lower the visible foot edge below its anchor.
    point.y += (0.5 - bottom_padding) * height * body_scale * lift * (1.0 - lift);
    // Corpse/remains/liquid pieces stay on the floor, including mixed batches.
    if (!actor_animated && INSTANCE_CUSTOM.g > 0.5)
        point = anchor + vec3(VERTEX.x * width, VERTEX.y * stack.y / 0.12 + dot(ground.xz, VERTEX.xz * vec2(width,height)), VERTEX.z * height);
    point += actor_world_offset(INSTANCE_CUSTOM);
    POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(point, 1.0);
    world_height = point.y;
    clip_height = use_instance_ceiling ? (actor_scale_data && actor_truescale ? scaled_ceiling : INSTANCE_CUSTOM.r) : ceiling_y;
}
void fragment() {
    if (world_height >= clip_height) discard;
    vec4 texel = sample_world_region(sprite_tex, UV, sprite_region);
    if (texel.a < 0.5) discard;
    ALBEDO = texel.rgb * COLOR.rgb;
}
