extends RefCounted
# A main-world lifetime owns the matching shader mode and post-transparent pass.
static var users:=0
var _camera:Camera3D
var _environment:Environment
var _original_background:Color
var _original_compositor:Compositor
var active:=false

func install(camera:Camera3D, environment:Environment):
	if active or RenderingServer.get_rendering_device()==null:return
	_camera=camera
	_environment=environment
	_original_background=environment.background_color
	_original_compositor=camera.compositor
	var compositor:=Compositor.new()
	if _original_compositor!=null:compositor.compositor_effects=_original_compositor.compositor_effects.duplicate()
	var effects:Array[CompositorEffect]=compositor.compositor_effects
	effects.append(preload("res://scripts/world_color_effect.gd").new())
	compositor.compositor_effects=effects
	camera.compositor=compositor
	# Environment's color is decoded by the engine before filling its HDR target.
	environment.background_color=_original_background.linear_to_srgb()
	users+=1
	active=true
	RenderingServer.global_shader_parameter_set("native_world_color",true)

func release():
	if not active:return
	active=false
	if is_instance_valid(_camera):_camera.compositor=_original_compositor
	if is_instance_valid(_environment):_environment.background_color=_original_background
	users=maxi(0,users-1)
	if users==0:RenderingServer.global_shader_parameter_set("native_world_color",false)
