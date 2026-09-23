// Only actor MultiMeshes opt into the COLOR payload. Other consumers keep tint.
global uniform bool actor_truescale;
global uniform float actor_view_scale;
uniform bool actor_scale_data = false;
float actor_scale(vec4 payload) {
    if (!actor_scale_data) return 1.0;
    return (actor_truescale ? max(payload.r, 0.00001) : 1.0) * actor_view_scale;
}
float actor_bottom_padding(vec4 payload) {
    return actor_scale_data && actor_truescale ? payload.g : 0.0;
}
