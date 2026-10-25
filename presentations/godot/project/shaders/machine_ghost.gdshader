shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/machine_sampling.gdshaderinc"
void fragment() {
    vec4 c = sample_machine(UV, COLOR);
    ALBEDO = world_output(c.rgb);
    ALPHA = c.a;
}
