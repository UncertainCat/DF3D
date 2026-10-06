extends SceneTree
class Interaction extends Node:
 var construction_active:=false
 var shell_blocked:=false
 var shell_enabled:=false
 var panel:=Control.new()
 var pauses:Array=[]
 func _pause(value):pauses.append(value)
 func _ready():add_child(panel)
 func cancel_selection():pass
 func set_play_enabled(_value):pass
class World extends RefCounted:
 var top:=-1
 func map_size():return Vector3i(200,180,100) # render x,elevation,y
 func set_top_z(value):top=value
 func get_top_z():return top
 func terrain_loaded():return true
 func tile_hover_info(tile):return {"shape":"Floor"} if tile.z==0 else {}
 func inspect_tile(_tile):return []
 func inspect_entity(kind,id):return {"tile":Vector3i(132,70,165)} if kind==1 and id==2905 else {}
class Inspector extends RefCounted:
 var received:Array=[]
 func open_target(tile,kind,id):received.append([tile,kind,id])
class View extends RefCounted:
 var camera_rig
class Service extends RefCounted:
 signal session_changed
 var next:=0
 var detached:Array=[]
 func submit(_domain,_request,_observer):next+=1;return next
 func detach(ticket):detached.append(ticket)
func _initialize():call_deferred("run")
func run():
 var interaction:=Interaction.new();root.add_child(interaction)
 var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
 var service:=Service.new()
 var owner=preload("res://scripts/reports_panel.gd").new();root.add_child(owner)
 # Ownership test injects a plain surface; native artwork is verified in GPU capture.
 owner.panel=Control.new();owner.add_child(owner.panel);owner.panel.hide()
 owner.controller.configure(service);host.register(owner)
 owner.open_panel();assert(host.active==owner and owner.controller.state.opened and interaction.construction_active)
 owner.controller.state.pause_requested.emit();assert(interaction.pauses==[true])
 host.set_overlay_blocked(true);assert(not host.allows_panel_input(owner))
 host.set_overlay_blocked(false);owner.handle_back()
 assert(host.active==null and not owner.controller.state.opened and service.detached==[1])
 owner.controller.state.pause_requested.emit();assert(interaction.pauses==[true])
 owner.open_panel();host.reset_local_views();assert(host.active==null and owner.controller.ticket==0)
 owner.open_panel();service.session_changed.emit();assert(host.active==null and not owner.controller.state.opened)
 owner.open_panel();host.set_play_enabled(false);owner.open_panel()
 assert(host.active==null and not owner.controller.state.opened)
 host.set_play_enabled(true);owner.open_panel();assert(host.active==owner)
 var world:=World.new();owner.world_source=world
 var rig=preload("res://scripts/orbit_camera.gd").new()
 var camera:=Camera3D.new();camera.name="Camera3D";rig.add_child(camera);root.add_child(rig);rig.set_process(false)
 rig.focus_on(Vector3.ZERO,80.0)
 var view:=View.new();view.camera_rig=rig
 var composition=preload("res://scripts/fortress_ui.gd").new();composition.world=world;composition.view=view
 owner.focus_requested.connect(composition.focus_tile)
 var distance:float=rig.current_distance()
 owner.controller.state.rows=[{"id":7,"position_visible":true,"position":Vector3i(-1,50,165)}]
 assert(owner.controller.state.recenter(7))
 assert(host.active==null and not interaction.construction_active and not owner.panel.visible)
 assert(world.top==165 and rig.position==Vector3(0.5,166.0,50.5) and is_equal_approx(rig.current_distance(),distance))
 owner.open_panel();owner.controller.state.rows=[{"id":8,"position2_visible":true,"position2":Vector3i(250,120,190)}]
 assert(owner.controller.state.recenter(8,true))
 assert(world.top==179 and rig.position==Vector3(199.5,180.0,99.5))
 rig.walk_world=world
 for mode in ["df","isometric","free"]:
  for walking in [false,true]:
   world.set_top_z(0);rig.follow_level(0);rig.set_mode(mode);rig.focus_on(Vector3(3.5,1.0,3.5),80.0)
   var zoom:float=camera.size
   if walking:
    rig.set_mode("walk");assert(rig.is_walk_mode() and world.top==4)
   owner.open_panel();owner.controller.state.rows=[{"id":9,"position_visible":true,"position":Vector3i(125,50,165)}]
   assert(owner.controller.state.recenter(9))
   assert(rig.get_mode()==mode and world.top==165 and rig.position==Vector3(125.5,166.0,50.5))
   assert(is_equal_approx(rig.current_distance(),80.0) and is_equal_approx(camera.size,zoom))
 var registry=preload("res://scripts/ui_availability.gd")
 assert(registry.PANEL_ROUTES.Reports=="reports" and registry.allows_launcher("Reports"))
 var inspector:=Inspector.new();composition.controllers.inspector=inspector;composition.controllers.reports=owner;composition.host=host
 owner.speaker_requested.connect(composition.inspect_report_speaker)
 owner.open_panel();owner.controller.state.unit_id=71;owner.controller.state.rows=[{"id":10,"speaker_id":2905,"position":Vector3i(125,50,165)}]
 assert(not owner.controller.state.inspect_speaker(11))
 assert(owner.controller.state.inspect_speaker(10))
 assert(inspector.received==[[Vector3i(132,70,165),1,2905]] and not owner.controller.state.opened)
 assert(rig.position==Vector3(132.5,166.0,70.5))
 owner.open_panel();owner.controller.state.unit_id=71;owner.controller.state.rows=[{"id":11,"speaker_id":2000000000}]
 assert(owner.controller.state.inspect_speaker(11))
 assert(owner.controller.state.opened and host.active==owner and inspector.received.size()==1)
 owner.close_panel()
 composition.free();rig.free()
 owner.free();assert(host.active==null and not interaction.construction_active)
 host.free();interaction.free()
 print("REPORTS_PANEL_PASS");quit()
