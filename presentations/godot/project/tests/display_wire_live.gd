extends "res://tests/item_carrier_wire_live.gd"
class Interaction extends RefCounted:
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=false
	var panel=Control.new()
	func cancel_selection() -> void:pass
func drain_owner(owner,actions,closed: bool=false) -> bool:
	var until:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<until:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		if closed and owner.state.building_id<0:return true
		if not closed and owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.display.phase==owner.display.Phase.Ready and owner.display.ticket==0:return true
	return check(false,"Display composed owner did not settle")
func exercise_owner(id: int,item: int,actions) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Display owner assets missing"):return
	var interaction=Interaction.new()
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/furniture_panel.gd").new();root.add_child(owner);owner.configure(world,actions,host)
	owner.open_target(id)
	if await drain_owner(owner,actions):
		owner.panel.display_requested.emit()
		if await drain_owner(owner,actions):
			check(owner.display_mode and not owner.panel.visible and interaction.construction_active,"Display picker did not own modal input")
			owner.display.select_category(37)
			if await drain_owner(owner,actions):
				owner.display.toggle_item(item);owner.handle_escape()
				if await drain_owner(owner,actions,true):
					check(host.active==null and not owner.display_view.visible and not interaction.construction_active,"Display close retained parent/input")
					owner.open_target(id)
					if await drain_owner(owner,actions):
						check(owner.display.body.size()==1 and owner.display.body[0].id==item,"Display reopen lost committed assignment")
						owner.display.remove_item(item)
						if await drain_owner(owner,actions):check(owner.display.body.is_empty(),"Display composed removal failed")
	owner.close_panel();owner.queue_free();await process_frame;host.queue_free();interaction.panel.free();await process_frame
func read_display(id: int,category: int,query: String="",ids: Array=[]) -> Dictionary:
	var result:=await request("display",{"action":C.ManagementAction.DisplayRead,"building_id":id,"category":category,"query":query,"item_ids":ids})
	if not check(result.get("status")==C.ManagementStatus.Ok,"Display read failed: "+str(result)):return {}
	return result.get("display",{})
func settle(model,actions) -> bool:
	var until:=Time.get_ticks_msec()+10000
	while model.phase in [model.Phase.Reading,model.Phase.Applying] and Time.get_ticks_msec()<until:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Display controller failed: "+str(model.last_result))
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/display-wire-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Display attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Display catalog failed"):quit(1);return
	var id:=int(expected.id);var item:=int(expected.item_id)
	if expected.has("large_ids"):
		var response:=await request("display",{"action":C.ManagementAction.DisplayRead,"building_id":id,"category":-1,"query":"","item_ids":[]})
		var body: Array=response.get("display",{}).get("body",[])
		check(response.get("status")==C.ManagementStatus.Ok and body.size()==expected.large_ids.size(),"Large Display body incomplete")
		for index in mini(body.size(),expected.large_ids.size()):check(body[index].id==int(expected.large_ids[index]) and body[index].resolved,"Large Display identity/order differs")
		var after:=await request("construction",{"action":C.ManagementAction.Catalog})
		var sequences: int=int(after.get("request_seq",0))-int(response.get("request_seq",0))
		check(sequences>1,"Large Display did not use reply continuations")
		var result_file:=FileAccess.open(directory+"/display-wire-result.json",FileAccess.WRITE)
		result_file.store_string(JSON.stringify({"success":not failed,"large_rows":body.size(),"sequence_delta":sequences}));result_file.close()
		world.queue_free();await process_frame;quit(1 if failed else 0);return
	var parent_capture: Dictionary={}
	var parent:=await read_display(id,-1)
	var initial:=await read_display(id,-2)
	check(initial.get("category")==39 and initial.get("categories",[]).size()==93,"Display initial category differs")
	var page:=await read_display(id,37,"",[item])
	if not page.is_empty():
		check(page.groups.size()==expected.picker.groups.size(),"Display group count differs")
		for i in mini(page.groups.size(),expected.picker.groups.size()):
			var reference: Dictionary=expected.picker.groups[i]
			for key in ["subtype","subcat1","subcat2","amount","expanded","matches","caption"]:check(page.groups[i][key]==reference[key],"Display group differs: "+key)
			check(page.groups[i].item_ids==reference.items.map(func(value):return int(value)),"Display group membership differs")
		check(page.items.size()==1 and page.items[0].has("appearance"),"Display item appearance missing")
		var search:=await read_display(id,37,"steel")
		check(search.get("categories",[]).filter(func(row):return row.matches).size()==17,"Display search categories differ")
		var applied:=await request("display",{"action":C.ManagementAction.DisplayCommit,"building_id":id,"expected_revision":page.inventory_revision,"selected_ids":[item]})
		var assigned: Dictionary=applied.get("display",{})
		if check(assigned.get("outcome")==C.DisplayOutcome.Applied,"Display commit failed: "+str(applied)):
			check(assigned.body.size()==1 and assigned.body[0].id==item and assigned.body[0].status=="Assigned","Display assigned receipt differs")
			parent_capture.display=await read_display(id,-1,"",[item])
			parent_capture.header=(await request("production",{"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":id})).get("production",{}).get("building_header",{}).get("snapshot",{})
			parent_capture.contents=(await request("production",{"action":C.ManagementAction.ProductionInspect,"building_id":id,"contents":true,"cursor":0,"expected_revision":0})).get("production",{}).get("contents",{})
			check(not parent_capture.header.is_empty() and not parent_capture.contents.is_empty(),"Display parent header/contents unavailable")
			var stale:=await request("display",{"action":C.ManagementAction.DisplayRemove,"building_id":id,"expected_revision":parent.revision,"selected_ids":[item]})
			check(stale.get("display",{}).get("outcome")==C.DisplayOutcome.Stale,"Display stale removal accepted")
			var removed:=await request("display",{"action":C.ManagementAction.DisplayRemove,"building_id":id,"expected_revision":assigned.revision,"selected_ids":[item]})
			check(removed.get("display",{}).get("outcome")==C.DisplayOutcome.Applied and removed.display.body.is_empty(),"Display removal failed")
	if not failed:
		var actions=preload("res://scripts/semantic_action_service.gd").new()
		actions.configure(world);root.add_child(actions);actions.set_process(false)
		var claim: int=actions.submit("construction",{"action":C.ManagementAction.Catalog},Callable())
		var until:=Time.get_ticks_msec()+10000
		while actions.result(claim).is_empty() and Time.get_ticks_msec()<until:
			world.poll();actions.poll(0.01);await create_timer(0.01).timeout
		var model=preload("res://scripts/display_state.gd").new();model.configure(actions)
		model.open(id)
		if await settle(model,actions):
			model.open_picker()
			if await settle(model,actions):
				model.select_category(37)
				if await settle(model,actions):
					model.toggle_item(item);model.select_category(39)
					if await settle(model,actions):
						check(model.selected.has(item),"Live category navigation lost draft")
						model.finish_picker()
						if await settle(model,actions):
							check(model.body.size()==1 and model.body[0].id==item,"Live controller assignment missing")
							model.remove_item(item)
							if await settle(model,actions):check(model.body.is_empty(),"Live controller removal missing")
		model.dispose()
		if not failed:await exercise_owner(id,item,actions)
		actions.queue_free();await process_frame
	var all_ids: Array=[]
	for group in page.get("groups",[]):all_ids.append_array(group.item_ids)
	var full_page:=await read_display(id,37,"",all_ids)
	var file:=FileAccess.open(directory+"/display-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"initial":initial,"page":page,"full_page":full_page,"parent_capture":parent_capture}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
