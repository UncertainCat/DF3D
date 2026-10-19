shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/world_color.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform bool textured=false;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_energy=1.0;
void fragment() {
    vec4 c=COLOR;
    if(textured)c*=texture(albedo_tex,UV);
    ALBEDO=world_output(c.rgb+emission_color.rgb*emission_energy);
    ALPHA=c.a;
}
