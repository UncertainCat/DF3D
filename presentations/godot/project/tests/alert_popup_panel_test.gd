extends SceneTree
class Interaction extends Node:
 var construction_active:=false
 var shell_blocked:=false
 var shell_enabled:=false
 var panel:=Control.new()
 func _ready():add_child(panel)
 func cancel_selection():pass
 func set_play_enabled(_value):pass
class World extends RefCounted:
 var epoch:=37
 func poll_session():return {"fortress_valid":true,"fortress_epoch":epoch}
 func map_size():return Vector3i(200,180,100)
class Service extends RefCounted:
 signal session_changed
 var next:=0
 var detached:Array=[]
 func submit(_domain,_request,_observer):next+=1;return next
 func detach(ticket):detached.append(ticket)
func _initialize():call_deferred("run")
func run():
 var world=World.new();var service=Service.new()
 var interaction=Interaction.new();root.add_child(interaction)
 var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
 var owner=preload("res://scripts/alert_popup_panel.gd").new();root.add_child(owner)
 owner.world_source=world;owner.panel=Control.new();owner.add_child(owner.panel)
 owner.controller.configure(service);host.register(owner)
 var group:={"fortress_epoch":37,"category":20,"unit_reports":[{"unit_id":17,"category":1}],"complete":true}
 var stale:Dictionary=group.duplicate(true);stale.fortress_epoch=36
 owner.open_group(stale);assert(host.active==null and service.next==0)
 host.set_overlay_blocked(true);owner.open_group(group);assert(host.active==null)
 host.set_overlay_blocked(false);owner.open_group(group)
 assert(host.active==owner and interaction.construction_active and service.next==1)
 assert(host.allows_minimap_input())
 var state=owner.controller.state
 assert(state.pending.request.view==6 and state.pending.request.notification_category==20)
 state.accept(state.generation,state.epoch,{"view":6,"notification_category":20,"list_revision":7,"cursor":0,"next_cursor":0,"total":1,"reports":[],"units":[{"unit_id":17,"category":1}]})
 assert(state.open_unit(17,1));assert(host.allows_minimap_input());owner.handle_back()
 assert(host.active==owner and state.unit_id==-1 and state.opened and state.complete)
 owner.handle_back();assert(host.active==null and not state.opened and not interaction.construction_active)
 owner.open_group(group)
 var history:Array=[];owner.history_requested.connect(func():history.append(host.active==null and not state.opened))
 owner._open_history();assert(history==[true])
 owner.open_group(group);service.session_changed.emit();assert(host.active==null and not state.opened)
 owner.open_group(group);host.set_play_enabled(false);assert(host.active==null and not state.opened)
 owner.open_group(group);assert(not state.opened)
 host.set_play_enabled(true);world.epoch=38;owner.open_group(group);assert(host.active==null)
 var centered:Array=[];owner.focus_requested.connect(func(tile):centered.append(tile))
 owner._recenter(Vector3i(250,-4,190));assert(centered==[Vector3i(199,0,179)])
 owner.free();host.free();interaction.free()
 thumb_positions()
 scroll_restore()
 print("ALERT_POPUP_PANEL_PASS");quit()

func scroll_restore() -> void:
 var state=preload("res://scripts/alert_entries_state.gd").new()
 var view=preload("res://scripts/alert_entries_view.gd").new()
 view.state=state;state.changed.connect(view.refresh)
 state.opened=true;state.complete=true;state.loaded=true
 for id in 30:state.rows.append({"kind":"report","data":{"id":id,"text":"Parent fixture"}})
 state.rows.append({"kind":"unit","data":{"unit_id":998,"category":0,"name":"Unit fixture"}})
 state.changed.emit();view.scroll_to(64)
 assert(view.first_line==64)
 assert(state.open_unit(998,0));state.back()
 assert(view.first_line==64 and state.complete)
 # Completed unit navigation preserves the same parent position.
 assert(state.open_unit(998,0))
 assert(state.accept(state.generation,state.epoch,{"view":3,"unit_id":998,"unit_category":0,"list_revision":7,"reports":[{"id":100,"text":"Unit report","text_complete":true}]}))
 assert(view.first_line==0);state.back();assert(view.first_line==64)
 state.close();assert(view.first_line==0 and view._loading_unit==-1)
 view.free()

func thumb_positions() -> void:
 var bar=preload("res://scripts/reports_scrollbar.gd").new()
 bar.use_standalone_sheet=false;bar.size=Vector2(16,348);bar.count=93;bar.page=29
 # Native113212 pixel border positions, converted to12px scrollbar cells.
 var positions:={64:19,63:18,62:18,61:18,60:18,59:18,35:11,34:10,33:10,32:10,1:2,0:1}
 for first in positions:
  bar.first=first;assert(bar.thumb()==Vector2i(positions[first],9))
 bar.use_standalone_sheet=true;bar.first=63
 assert(bar.thumb()==Vector2i(19,9)) # Separate Reports evidence is unchanged.
 bar.free()
