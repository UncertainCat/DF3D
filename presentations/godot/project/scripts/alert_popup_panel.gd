extends Node
signal focus_requested(tile:Vector3i)
signal history_requested
var modal_input:=true
var play_enabled:=true
var ui_host
var world_source
var panel:Control
var controller=preload("res://scripts/alert_entries_controller.gd").new()

func _init() -> void:
 add_child(controller)
 controller.state.dismissed.connect(_release)

func configure(world,service,host) -> void:
 world_source=world;ui_host=host;controller.configure(service)
 var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
 panel=preload("res://scripts/alert_entries_view.gd").new();layer.add_child(panel)
 panel.configure(world,controller.state,world.assets_root())
 panel.input_allowed=func():return ui_host!=null and ui_host.allows_panel_input(self)
 panel.unit_requested.connect(func(id,category):controller.state.open_unit(id,category))
 panel.history_requested.connect(_open_history)
 panel.recenter_requested.connect(_recenter)
 host.register(self)

func open_group(group:Dictionary) -> void:
 if not play_enabled or ui_host==null or world_source==null:return
 var session:Dictionary=world_source.poll_session()
 if not bool(session.get("fortress_valid",false)) or int(group.get("fortress_epoch",-1))!=int(session.get("fortress_epoch",-2)):return
 if not ui_host.activate(self):return
 controller.state.open(group)

func allows_minimap_input() -> bool:return play_enabled and controller.state.opened
func close_panel() -> void:controller.state.close()
func handle_back() -> void:controller.state.back()
func _open_history() -> void:
 controller.state.close();history_requested.emit()
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
 focus_requested.emit(Vector3i(clampi(tile.x,0,bounds.x-1),clampi(tile.y,0,bounds.z-1),clampi(tile.z,0,bounds.y-1)))
