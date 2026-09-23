shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;
uniform sampler2D status_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
varying flat vec3 owner_screen;
varying flat float state_visible;
global uniform float unit_status_clock;
uniform float capture_phase = -1.0;
global uniform bool actor_truescale;
global uniform float actor_view_scale;
#include "res://shaders/actor_motion.gdshaderinc"
#include "res://shaders/shared_stack.gdshaderinc"
#include "res://shaders/actor_ground.gdshaderinc"
void vertex() {
    float phase = capture_phase >= 0.0 ? capture_phase : mod(unit_status_clock + INSTANCE_CUSTOM.a,7000.0);
    bool primary_window = phase > 5000.0;
    state_visible = INSTANCE_CUSTOM.b < 0.5 || (INSTANCE_CUSTOM.b < 1.5 ? primary_window : !primary_window) ? 1.0 : 0.0;
    float address = INSTANCE_CUSTOM.r;
    vec3 parameters = MODEL_MATRIX[3].xyz;
    vec3 tile = actor_motion_record(address,3).xyz;
    vec2 stack = shared_stack_interval(tile,actor_motion_record(address,2).z,3);
    vec3 anchor = actor_motion_position(address) + vec3(0.0,0.1+stack.x,0.0);
    anchor.y += actor_ground_support(address, actor_motion_position(address)).y;
    // Flat cutouts have physical thickness: test their top, not the underside.
    vec3 visibility_anchor = anchor + vec3(0.0, parameters.z < 0.5 ? stack.y + 0.05 : 0.0, 0.0);
    vec4 owner_view = VIEW_MATRIX * vec4(visibility_anchor,1.0);
    vec4 owner_clip = PROJECTION_MATRIX * owner_view;
    owner_screen = vec3(owner_clip.xy / owner_clip.w * 0.5 + 0.5, -owner_view.z);
    vec3 right = MAIN_CAM_INV_VIEW_MATRIX[0].xyz;
    vec3 up = MAIN_CAM_INV_VIEW_MATRIX[1].xyz;
    vec3 front = MAIN_CAM_INV_VIEW_MATRIX[2].xyz;
    float scale = (actor_truescale ? INSTANCE_CUSTOM.g : 1.0) * actor_view_scale;
    float padding = actor_truescale ? parameters.y : 0.0;
    float lift = parameters.z > 0.5
        ? parameters.x * scale * (0.5 + (0.5-padding)*clamp(up.y,0.0,1.0))
        : parameters.x * scale * 0.5 + 0.38;
    bool movement = INSTANCE_CUSTOM.b != 1.0;
    if (movement) lift = parameters.z > 0.5 ? parameters.x*scale*(0.5-padding)*clamp(up.y,0.0,1.0) : 0.0;
    vec3 point = anchor + right*VERTEX.x + up*(lift+(movement ? 0.0 : 0.12)+VERTEX.y) + front*0.08;
    POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(point,1.0);
}
void fragment() {
    if (state_visible < 0.5) discard;
    // Test the creature's anchor, not the offset annotation: adjacent walls
    // must not slice a bubble, but actors beneath visible floors stay hidden.
    float depth = texture(scene_depth, owner_screen.xy).r;
    vec3 ndc = vec3(owner_screen.xy*2.0-1.0,depth);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z = depth*2.0-1.0;
    #endif
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc,1.0);
    if (owner_screen.z > -scene_view.z/scene_view.w + 0.15) discard;
    vec4 pixel = texture(status_texture,UV);
    if (pixel.a < 0.5) discard;
    ALBEDO = pixel.rgb;
}
