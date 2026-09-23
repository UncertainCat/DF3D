shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;
global uniform float actor_animation_time;
#include "res://shaders/world_sampling.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_tiles = vec2(4.0, 32.0);
uniform bool upright = false;
instance uniform float start_time = 0.0;
instance uniform float duration = 0.28;
instance uniform float atlas_row = 0.0;
instance uniform vec2 world_direction = vec2(1.0, 0.0);
instance uniform float target_height = 0.0;
varying float elapsed;
varying float resolved_row;
void vertex() {
	elapsed = (actor_animation_time - start_time) / duration;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = upright ? MAIN_CAM_INV_VIEW_MATRIX[0].xyz : vec3(1.0, 0.0, 0.0);
	vec3 up = upright ? MAIN_CAM_INV_VIEW_MATRIX[1].xyz : vec3(0.0, 0.0, -1.0);
	vec3 front = upright ? MAIN_CAM_INV_VIEW_MATRIX[2].xyz : vec3(0.0, 1.0, 0.0);
	float lift = upright ? clamp(up.y, 0.0, 1.0) : 0.0;
	center += up * (0.5 * lift * target_height) + front * (upright ? 0.06 : 0.18);
	// Same pitch blending as billboard_sprite: the body center stays above its
	// foot anchor, so the effect tracks the drawn body rather than sinking.
	center.y += 0.5 * target_height * lift * (1.0 - lift);
	vec3 direction = vec3(world_direction.x, 0.0, world_direction.y);
	float angle = atan(-dot(direction, up), dot(direction, right));
	resolved_row = atlas_row + mod(round(angle / (3.14159265 / 4.0)) + 12.0, 8.0);
	vec3 world = center + right * VERTEX.x + up * VERTEX.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
void fragment() {
	if (elapsed < 0.0 || elapsed >= 1.0) discard;
	float frame = min(3.0, floor(elapsed * 4.0));
	vec2 uv = (vec2(frame, resolved_row) + clamp(UV, vec2(0.002), vec2(0.998))) / atlas_tiles;
	vec4 color = sample_world_region(atlas, uv, vec4(vec2(frame, resolved_row) / atlas_tiles, vec2(1.0) / atlas_tiles));
	if (color.a < 0.1) discard;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
