extends SceneTree
var failures := 0
class Controls extends Node:
	var panel := PanelContainer.new()
	var construction_active := false
	var shell_enabled := true
	var shell_blocked := false
	func set_play_enabled(value): panel.visible=value
	func cancel_selection(): pass
class World extends RefCounted:
	var demand := 0
	var refreshes := 0
	var data := {}
	func is_live(): return true
	func demand_resident_info(value): demand=value
	func refresh_resident_info(): refreshes+=1
	func resident_info_state():
		var result=data.duplicate()
		result["demand"]=demand
		return result
	func unit_tile(_id): return Vector3i(-1,-1,-1)
func check(value, message):
	if not value: failures += 1; push_error(message)
func _initialize(): call_deferred("run")
func run():
	var controls := Controls.new(); root.add_child(controls); controls.add_child(controls.panel)
	var world := World.new()
	var view = load("res://scripts/read_only_info.gd").new()
	view.world=world; view.interaction=controls; root.add_child(view); view.set_process(false)
	var host=load("res://scripts/ui_host.gd").new();host.interaction=controls;root.add_child(host);host.register(view)
	view.open_panel()
	check(view.panel.visible and controls.construction_active and world.demand==1,"Panel subscribes locally")
	host.set_overlay_blocked(true)
	var cancel := InputEventAction.new();cancel.action="ui_cancel";cancel.pressed=true
	view._unhandled_input(cancel)
	var right := InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
	view._unhandled_input(right)
	check(view.panel.visible and host.active==view and world.demand==1,"Overlay owns cancel and right-click without closing readout or releasing demand")
	host.set_overlay_blocked(false)
	world.data={"world_epoch":7,"generation":1,"complete":true,"rows":{"citizens":[{"id":3,"name":"Urist","profession":"Miner","job":"Dig","can_focus":true}]}}
	view.read_resident_state()
	check(view.people.size()==1,"Completed resident rows displayed")
	world.data.detail_list_revision=7
	world.data.rows.details=[{"index":0,"name":"Miners"},{"index":1,"name":"Custom"}]
	world.data.rows.citizens[0].assigned_details=[{"index":1,"icon":9,"name":""}]
	world.data.generation=2; view.read_resident_state()
	check(view.assigned_detail_name(1)=="Custom","Badge name resolves from revision-guarded definitions")
	check(view.assigned_detail_name(2)=="","Missing definition has no invented badge name")
	world.data.detail_list_revision=0; world.data.generation=3; view.read_resident_state()
	check(view.assigned_detail_name(1)=="","Unguarded definitions cannot label roster badges")
	world.data.detail_list_revision=8; world.data.rows.details[1].name="Renamed"
	world.data.generation=4; view.read_resident_state()
	check(view.assigned_detail_name(1)=="Renamed","New publication replaces badge names")
	check(view.resident_header.visible and not view.refresh_button.visible,"Residents replaces generic footer with native search")
	check(view.resident_mood(50000)==6 and view.resident_mood(-100000)==0,"Original stress art ordering and endpoints")
	view.people=[{"id":4,"name":"Zul"},{"id":2,"name":"Cerol"},{"id":1,"name":"Cerol"}]
	view.set_resident_sort("name")
	check(view.sorted_residents()[0].id==1 and view.sorted_residents()[2].id==4,"Local name sorting has stable identity ties")
	view.set_resident_sort("name")
	check(view.sorted_residents()[0].id==4,"Sort direction toggles")
	view.people=world.data.rows.citizens;view.render_rows()
	var row=view.rows.get_child(0)
	view.read_resident_state()
	check(view.rows.get_child(0)==row,"Unchanged generation reuses widgets")
	view.refresh()
	check(world.refreshes==1,"Refresh expresses demand without requesting transport")
	view.set_info_page("Work Details")
	world.data={"world_epoch":7,"generation":2,"complete":true,"rows":{"citizens":[{"id":3,"name":"Urist"}],"details":[{"index":0,"name":"Miners","mode":3,"assigned_units":[3]}]}}
	view.read_resident_state()
	check(world.demand==2 and view.mode_label.text.contains("Only selected"),"Work detail snapshot and native mode")
	world.data.rows.details.append({"index":1,"name":"Haulers","mode":3,"assigned_units":[],"revision":17})
	world.data.generation=4
	view.read_resident_state(); view.selected_detail=1
	world.data.generation=5
	view.read_resident_state()
	check(view.selected_detail==1,"Unchanged definition revision preserves selection")
	view.set_info_page("Work orders")
	world.data={"world_epoch":7,"generation":3,"complete":true,"rows":{"orders":[{"id":1,"name":"Make bed","remaining":2,"total":5}]}}
	view.read_resident_state()
	check(world.demand==3 and view.orders.size()==1,"Orders read from resident state")
	world.data["stale"]=true;world.data["error"]="Read interrupted"
	view.read_resident_state()
	check(view.orders.size()==1 and view.message.text.contains("previous data"),"Failure retains explicitly stale rows")
	world.data={"world_epoch":8,"generation":0,"complete":false,"rows":{}}
	view.read_resident_state()
	check(view.orders.is_empty(),"World replacement clears old UI")
	check(view.assigned_detail_name(1)=="","World replacement clears badge definitions")
	view.close_panel()
	check(not controls.construction_active and world.demand==0,"Close releases local ownership and interest")
	view.read_resident_state()
	check(not view.panel.visible,"Background publication cannot reopen panel")
	view.free();host.free();controls.free()
	print("READ_ONLY_INFO_PASS" if failures==0 else "READ_ONLY_INFO_FAIL")
	quit(0 if failures==0 else 1)
