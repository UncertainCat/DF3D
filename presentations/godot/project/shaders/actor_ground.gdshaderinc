// Includes actor_motion and shared_stack first. Horizontal motion samples the
// actual slope. Vertical semantic segments interpolate grounded endpoints;
// adding the lower slope to an already ascending Z would count the rise twice.
vec3 actor_ground_support(float address, vec3 position) {
    vec3 first = actor_motion_record(address, 0).xyz;
    vec3 last = actor_motion_record(address, 1).xyz;
    if (abs(last.y-first.y) < 0.0001) return shared_ground_support(position);
    float t = clamp((position.y-first.y)/(last.y-first.y), 0.0, 1.0);
    return vec3(0.0, mix(shared_ground_support(first).y, shared_ground_support(last).y, t), 0.0);
}
