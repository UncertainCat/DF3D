extends RefCounted
# Small unshaded world overlays participate in the same world color pass.
static var _shaders:Dictionary={}
static func create(color:=Color.WHITE, vertex_color:=false, no_depth:=false, texture:Texture2D=null, transparent:=false, repeat_texture:=false) -> ShaderMaterial:
	var key:=[transparent,no_depth,repeat_texture]
	if not _shaders.has(key):
		var shader:=Shader.new()
		shader.code="shader_type spatial;\nrender_mode unshaded, cull_disabled"+( ", depth_test_disabled" if no_depth else "")+";\n#include \"res://shaders/world_color.gdshaderinc\"\nuniform sampler2D albedo_tex : source_color, filter_nearest, "+("repeat_enable" if repeat_texture else "repeat_disable")+";\nuniform vec4 albedo_color : source_color = vec4(1.0);\nuniform bool textured=false;\nuniform bool vertex_color=false;\nvoid fragment(){ vec4 c=albedo_color; if(vertex_color)c*=COLOR; if(textured)c*=texture(albedo_tex,UV); ALBEDO=world_output(c.rgb);"+(" ALPHA=c.a;" if transparent else "")+" }"
		_shaders[key]=shader
	var material:=ShaderMaterial.new()
	material.shader=_shaders[key]
	material.set_shader_parameter("albedo_color",color)
	material.set_shader_parameter("vertex_color",vertex_color)
	material.set_shader_parameter("textured",texture!=null)
	if texture!=null:material.set_shader_parameter("albedo_tex",texture)
	return material
