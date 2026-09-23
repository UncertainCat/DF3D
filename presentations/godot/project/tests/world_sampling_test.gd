extends SceneTree
# Procedural adjacent red/green cells catch cross-tile mip bleeding without DF art.
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(256,256)
	assert(root.msaa_3d == Viewport.MSAA_2X)
	assert(root.anisotropic_filtering_level == RenderingServer.VIEWPORT_ANISOTROPY_4X)
	var image := Image.create(8,4,false,Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	image.fill_rect(Rect2i(0,0,4,4),Color.RED)
	image.generate_mipmaps()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/world_sampling.gdshaderinc"
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float repetitions = 1.0;
void fragment() {
    vec2 uv = fract(UV * repetitions) * vec2(.5, 1.0);
    ALBEDO = sample_world_region(tex, uv, vec4(0.0,0.0,.5,1.0)).rgb;
}
"""
	material.shader = shader
	material.set_shader_parameter("tex",ImageTexture.create_from_image(image))
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.material_override = material
	root.add_child(mesh)
	var camera := Camera3D.new()
	camera.position.z = 2
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	root.add_child(camera)
	for repetitions in [1.0,16.0,128.0]:
		material.set_shader_parameter("repetitions",repetitions)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		for y in range(20,236,7):
			for x in range(20,236,7):
				var c := capture.get_pixel(x,y)
				assert(c.r > .9 and c.g < .02 and c.b < .02,"Neighboring atlas cell leaked into sampled region")
	print("WORLD_SAMPLING_TEST_PASS")
	quit()
