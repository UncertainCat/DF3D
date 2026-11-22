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
	# entities.cpp anchors Construction34 between ScrewPump33 and Hatch35.
	for pair in [[3,4],[18,19],[31,32],[32,33],[33,34],[34,55],[35,35],[46,46],[54,54]]:
		ui.world.facts={"building_kind":pair[1],"complete":false}
		ui.open_building_holder(pair[0],278)
		if pending.opened.size()!=1 or not furniture.opened.is_empty():failures+=1;push_error("Unfinished holder mapping differs: "+str(pair))
		pending.opened.clear()
	OS.set_environment("DF3D_FURNITURE_RUNTIME","0")
	for pair in [[7,8],[47,47],[16,17],[17,18],[20,21],[21,22],[22,23],[24,25],[25,26],[26,27],[28,29],[31,32],[48,48],[49,49],[3,4],[18,19],[19,20],[32,33],[33,34],[45,45],[35,35],[36,36],[37,37],[38,38],[39,39],[40,40],[41,41],[42,42],[43,43],[44,44],[46,46],[50,50],[53,53]]:
		ui.world.facts={"building_kind":pair[1],"complete":true}
		if not ui.uses_building_selection(ui.world.facts):failures+=1;push_error("Map selection disagrees with holder route: "+str(pair))
		ui.open_building_holder(pair[0],278)
		if furniture.opened.size()!=1 or not pending.opened.is_empty():failures+=1;push_error("Completed holder remains gated: "+str(pair))
		furniture.opened.clear()
	ui.free()
	if failures==0:print("BUILDING_HOLDER_ROUTING_PASS")
	quit(0 if failures==0 else 1)
