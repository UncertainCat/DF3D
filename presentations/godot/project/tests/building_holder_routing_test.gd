extends SceneTree
class World:
	extends RefCounted
	var facts: Dictionary={}
	func inspect_entity(_kind,_id):return facts
class HolderPanel:
	extends RefCounted
	var opened: Array=[]
	func open_target(id):opened.append(id)
func _initialize() -> void:
	var ui=preload("res://scripts/fortress_ui.gd").new()
	ui.world=World.new();ui.host={"play_enabled":true}
	var pending:=HolderPanel.new();var furniture:=HolderPanel.new()
	ui.controllers={"pending_building":pending,"furniture":furniture}
	var failures:=0
	for pair in [[3,4],[46,46],[31,55],[54,54]]:
		ui.world.facts={"building_kind":pair[1],"complete":false}
		ui.open_building_holder(pair[0],278)
		if pending.opened.size()!=1 or not furniture.opened.is_empty():failures+=1;push_error("Unfinished holder mapping differs: "+str(pair))
		pending.opened.clear()
	OS.set_environment("DF3D_FURNITURE_RUNTIME","0")
	for pair in [[3,4],[46,46]]:
		ui.world.facts={"building_kind":pair[1],"complete":true}
		ui.open_building_holder(pair[0],278)
		if furniture.opened.size()!=1 or not pending.opened.is_empty():failures+=1;push_error("Completed funerary holder remains gated")
		furniture.opened.clear()
	ui.free()
	if failures==0:print("BUILDING_HOLDER_ROUTING_PASS")
	quit(0 if failures==0 else 1)
