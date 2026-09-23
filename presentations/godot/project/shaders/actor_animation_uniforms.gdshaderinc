#include "res://shaders/actor_animation.gdshaderinc"
uniform bool actor_animated = false;
global uniform float actor_animation_time;
global uniform float actor_animation_strength;
vec3 actor_world_offset(vec4 parameters) {
    int code = int(parameters.g + 0.5);
    if (!actor_animated || (code != 13 && code != 14 && code != 22) || actor_animation_strength <= 0.0 || abs(parameters.a) > 6.28318530718) return vec3(0.0);
    if (code == 22) {
        float phase = clamp((actor_animation_time - parameters.b) / .25, 0.0, 1.0);
        float recoil = smoothstep(0.0, .16, phase) * (1.0 - smoothstep(.16, 1.0, phase));
        return vec3(cos(parameters.a), 0.0, sin(parameters.a)) * -.045 * recoil * actor_animation_strength;
    }
    if (code == 14) {
        float phase = clamp((actor_animation_time - parameters.b) / .22, 0.0, 1.0);
        float recoil = smoothstep(0.0, .20, phase) * (1.0 - smoothstep(.20, 1.0, phase));
        return vec3(cos(parameters.a), 0.0, sin(parameters.a)) * .08 * recoil * actor_animation_strength;
    }
    float u = clamp((actor_animation_time - parameters.b) / .44, 0.0, 1.0);
    float windup = smoothstep(0.0, .28, u) * (1.0 - smoothstep(.28, .48, u));
    float lunge = smoothstep(.28, .48, u) * (1.0 - smoothstep(.48, 1.0, u));
    return vec3(cos(parameters.a), 0.0, sin(parameters.a)) * (-.025 * windup + .25 * lunge) * actor_animation_strength;
}
vec3 animated_actor_vertex(vec3 vertex, vec4 parameters, bool upright) {
    if (!actor_animated || parameters.g < 0.5 || actor_animation_strength <= 0.0) return vertex;
    vec3 posed = actor_animate(vertex, parameters.g, actor_animation_time - parameters.b, parameters.a, upright);
    return mix(vertex, posed, actor_animation_strength);
}
