extends SceneTree
var failures := 0
class Controls extends Node:
 var construction_active := false
 var shell_blocked := false
 var shell_enabled := true
 var panel := PanelContainer.new()
 func set_play_enabled(value): panel.visible=value
 func cancel_selection(): pass
class World extends RefCounted:
 var demand := 0
 var epoch := 7
 var creature := {}
 var rows: Array = [{"kind":1,"id":1,"name":"Urist","tile":Vector3i(2,2,2),"age":25,"summary_available":true},{"kind":2,"id":2,"name":"Chair","tile":Vector3i(2,2,2),"stack":1},{"kind":3,"id":3,"name":"Throne","tile":Vector3i(2,2,2),"complete":true}]
 func is_live(): return true
 func ui_texture(_name,_cell=-1): return null
 func selection_icon(_kind,_id): return null
 func resident_info_state(): return {"world_epoch":epoch}
 func demand_resident_info(value): demand=value
 func demand_creature_info(value): demand=1 if value>=0 else 0
 func creature_info_state(_id): return creature

 func inspect_tile(tile): return rows.duplicate() if tile==Vector3i(2,2,2) else []
 func inspect_entity(kind,id):
  for row in rows:
   if row.kind==kind and row.id==id: return row.duplicate()
  return {}
func check(value,message):
 if not value: failures+=1; push_error(message)
func _initialize(): call_deferred("run")
func run():
 # This controller fixture intentionally provides no installed art.
 preload("res://scripts/original_ui.gd")._warned_assets_unavailable = true
 var controls=Controls.new(); root.add_child(controls)
 var world=World.new()
 var view=load("res://scripts/context_inspector.gd").new()
 view.world=world;view.interaction=controls;root.add_child(view);view.set_process(false)
 var host=load("res://scripts/ui_host.gd").new();host.interaction=controls;root.add_child(host);host.register(view)
 await view.open_target(Vector3i(2,2,2),2,2)
 check(view.panel.visible and view.selected.id==2,"Actual hit wins over tile priority")
 var right := InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
 view._input(right)
 check(view.right_down,"Inspector starts local right-click gesture")
 host.set_overlay_blocked(true)
 check(not view.right_down,"Overlay cancels inspector right-click gesture")
 var escape := InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
 view._input(escape)
 right.pressed=false;view._input(right)
 check(view.panel.visible and host.active==view,"Overlay owns Escape and right-click without closing underlying inspector")
 host.set_overlay_blocked(false)
 view._input(right)
 check(view.panel.visible,"Release after overlay cannot complete canceled inspector gesture")
 view.choose(world.rows[0])
 check(world.demand==1,"Unit interest uses resident service")
 var first=view.body.get_child(0)
 world.rows[0]["tick"]=2;world.rows[0]["tile"]=Vector3i(3,2,2)
 view._process(.25);first=view.body.get_child(0)
 view._process(.25)
 check(view.body.get_child(0)==first,"Unchanged facts reuse Controls")
 world.creature={"generation":1,"detail":{"unit_id":1,"name":"Urist","captured_tick":1,"sections":[{"key":"skills","available":true,"records":[{"name":"Axe","facts":[{"key":"skill_class","text":"military weapon"}]},{"name":"Swimming","facts":[{"key":"skill_class","text":"personal"}]}]}]}}
 view._process(.25)
 var sheet=view.creature_sheet
 for group in sheet.recipe.rows:
  for name in group:
   sheet.change_tab(name)
   if sheet.recipe.subtabs.has(name):
    for sub in sheet.recipe.subtabs[name]: sheet.change_tab(sub,true)
 sheet.change_tab("Skills");sheet.change_tab("Combat",true)
 check(sheet.skills_view.kind==1 and sheet.skills_view.rows.is_empty(),"Combat tab must wait for native page, not infer rows from legacy skill facts")
 sheet.change_tab("Other skills",true)
 check(sheet.skills_view.kind==3 and sheet.skills_view.rows.is_empty(),"Other skills tab must wait for native page, not infer rows from legacy skill facts")
 first=view.body.get_child(0)
 world.creature.generation=2;world.creature.detail.captured_tick=2;view._process(.25)
 check(view.body.get_child(0)==first,"Publication-only changes preserve controls")
 var inventory: Array=[]
 for index in 24: inventory.append({"id":100+index,"related_id":100+index,"name":"Item "+str(index),"facts":[]})
 world.creature.detail.sections.append({"key":"inventory","available":true,"records":inventory})
 sheet.change_tab("Items")
 var items=sheet.items_view
 items.scrollbar.move_to(3);items.scrollbar.dragging=true
 world.creature=world.creature.duplicate(true)
 world.creature.detail.sections[-1].records[0].name="Changed item";world.creature.generation=3;view._process(.25)
 check(sheet.items_view==items and items.scrollbar.dragging and items.first==3,"Detail refresh preserves Items gesture and offset")
 check(items.rows[0].name=="Changed item" and items.icons.size()==24,"Retained Items view consumes fresh rows")
 host.set_overlay_blocked(true)
 check(not items.scrollbar.dragging,"Overlay immediately cancels Items drag")
 host.set_overlay_blocked(false);items.scrollbar.dragging=true
 world.creature=world.creature.duplicate(true)
 world.creature.detail.sections[-1].records=[];world.creature.generation=4;view._process(.25)
 check(sheet.items_view==items and items.rows.is_empty() and not items.scrollbar.visible and not items.scrollbar.dragging,"Empty refresh retires scrollbar gesture")
 items.scrollbar.dragging=true;items.scrollbar.hover_cell=1
 view.close_panel()
 check(host.active==null,"Closing inspect releases its host ownership")
 check(not items.scrollbar.dragging and items.scrollbar.hover_cell==-1,"Closing inspect retires Items gesture")
 await view.open_tile(Vector3i(2,2,2))
 world.epoch=8;view._process(.25)
 check(not view.panel.visible,"World replacement closes identity")
 await view.open_tile(Vector3i(2,2,2))
 world.rows.clear();view._process(.25)
 check(not view.panel.visible,"Removed entity closes")
 await view.open_tile(Vector3i.ZERO)
 check(not view.panel.visible,"Empty click stays closed")
 view.free();host.free();controls.panel.free();controls.free()
 print("CONTEXT_INSPECT_PASS" if failures==0 else "CONTEXT_INSPECT_FAIL")
 quit(0 if failures==0 else 1)
