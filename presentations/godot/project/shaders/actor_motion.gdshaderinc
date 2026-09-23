global uniform vec2 actor_motion_clock;
uniform sampler2DArray actor_motion_texture : filter_nearest, repeat_disable;
uniform bool actor_motion_enabled = false;
vec4 actor_motion_record(float address, int column) {
    int slot = int(address + 0.5) - 1;
    return texelFetch(actor_motion_texture, ivec3(column, slot % 32, slot / 32), 0);
}
vec3 actor_motion_position(float address) {
    vec4 first = actor_motion_record(address, 0);
    vec4 last = actor_motion_record(address, 1);
    vec4 info = actor_motion_record(address, 2);
    float duration = (info.y - info.x) * 4096.0 + last.w - first.w;
    float elapsed = (actor_motion_clock.x - info.x) * 4096.0 + actor_motion_clock.y - first.w;
    return mix(first.xyz, last.xyz, duration > 0.0 ? clamp(elapsed / duration, 0.0, 1.0) : 0.0);
}
