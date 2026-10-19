extends CompositorEffect
# World-only encoded-RGB blending. Run after transparent draws and MSAA resolve,
# before tonemapping and the separate canvas/HUD pass. No screen-texture feedback.
const COMPUTE := """
#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rgba16f, set=0, binding=0) uniform image2D color_image;
void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p,imageSize(color_image)))) return;
    vec4 c=imageLoad(color_image,p);
    vec3 rgb=max(c.rgb,vec3(0.0));
    c.rgb=mix(rgb/12.92,pow((rgb+0.055)/1.055,vec3(2.4)),greaterThan(rgb,vec3(0.04045)));
    imageStore(color_image,p,c);
}
"""
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _attempted := false

func _init():
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color=true
	_rd=RenderingServer.get_rendering_device()

func _render_callback(callback: int, data: RenderData):
	if callback!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or _rd==null:return
	if not _attempted:
		_attempted=true
		var source:=RDShaderSource.new()
		source.source_compute=COMPUTE
		var spirv:=_rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			push_error(spirv.compile_error_compute)
			return
		_shader=_rd.shader_create_from_spirv(spirv)
		_pipeline=_rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():return
	var buffers:RenderSceneBuffersRD=data.get_render_scene_buffers()
	if buffers==null:return
	var size:=buffers.get_internal_size()
	if size.x<=0 or size.y<=0:return
	for view in buffers.get_view_count():
		var uniform:=RDUniform.new()
		uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding=0
		uniform.add_id(buffers.get_color_layer(view))
		var bindings:=UniformSetCacheRD.get_cache(_shader,0,[uniform])
		var commands:=_rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(commands,_pipeline)
		_rd.compute_list_bind_uniform_set(commands,bindings,0)
		_rd.compute_list_dispatch(commands,(size.x+7)/8,(size.y+7)/8,1)
		_rd.compute_list_end()

func _notification(what):
	if what==NOTIFICATION_PREDELETE and _shader.is_valid() and _rd!=null:
		RenderingServer.call_on_render_thread(_free_shader.bind(_shader))

static func _free_shader(shader:RID):
	var device:=RenderingServer.get_rendering_device()
	if device!=null:device.free_rid(shader)
