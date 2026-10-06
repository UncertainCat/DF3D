extends Node
# Panel ownership adapter. The factory route remains hidden from launchers until
# the complete Reports surface has native interaction acceptance.
signal focus_requested(tile:Vector3i)
signal speaker_requested(unit_id:int)
var world_source
var ui_host
var modal_input:=true
var play_enabled:=true
var panel:Control
var controller=preload("res://scripts/reports_controller.gd").new()

func _init() -> void:
 add_child(controller)
 controller.state.dismissed.connect(_release)
 controller.state.recenter_requested.connect(_recenter)
 controller.state.pause_requested.connect(_pause)
 controller.state.speaker_requested.connect(func(id):speaker_requested.emit(id))

func _pause() -> void:
 if play_enabled and ui_host!=null and controller.state.opened:
  ui_host.interaction._pause(true)

func configure(world,service,host) -> void:
 world_source=world;ui_host=host;controller.configure(service)
 var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
 panel=preload("res://scripts/reports_view.gd").new();layer.add_child(panel)
 panel.configure(world,controller.state,world.assets_root())
 panel.input_allowed=func():return ui_host!=null and ui_host.allows_panel_input(self)
 host.register(self)

func open_panel() -> void:
 if not play_enabled or ui_host==null or not ui_host.activate(self):return
 controller.state.open()

func close_panel() -> void:
 controller.state.close()

func handle_back() -> void:close_panel()
func set_play_enabled(value:bool) -> void:
 play_enabled=value
 if not value:close_panel()
func _release() -> void:
 if panel!=null:panel.hide()
 if ui_host!=null:ui_host.release(self)

func _recenter(tile:Vector3i) -> void:
 if world_source==null:return
 var bounds:Vector3i=Vector3i(world_source.map_size())
 if bounds.x<=0 or bounds.y<=0 or bounds.z<=0:return
 # Df3dWorld.map_size uses render axes (x,elevation,y); report tiles use DF x,y,z.
 focus_requested.emit(Vector3i(clampi(tile.x,0,bounds.x-1),clampi(tile.y,0,bounds.z-1),clampi(tile.z,0,bounds.y-1)))
