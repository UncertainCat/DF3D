extends "res://tests/item_carrier_wire_live.gd"
const Contents=preload("res://scripts/building_contents_state.gd")
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/chest-contents-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Chest bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var intent={"action":C.ManagementAction.ProductionInspect,"building_id":int(expected.target_id),"contents":true}
	var response:=await request("production",intent)
	var page: Dictionary=response.get("production",{}).get("contents",{})
	if not check(response.get("status")==C.ManagementStatus.Ok and Contents.valid_page(page,int(expected.target_id)),"Chest contents rejected"):quit(1);return
	check(page.completed and not page.removing and page.rows.size()==expected.contents.size() and page.total==expected.contents.size(),"Chest row count/state differs")
	for index in page.rows.size():
		var row: Dictionary=page.rows[index];var native: Dictionary=expected.contents[index]
		check(row.id==int(native.id) and row.role==int(native.role) and row.item_type==int(native.type),"Chest membership/order/type differs")
		check(row.hidden==native.hidden,"Chest visibility differs")
	var initial:=page.duplicate(true);var receipts: Array=[]
	for row in initial.rows:
		if failed:break
		var old: int=page.revision
		for value in [not row.hidden,row.hidden]:
			var edit={"action":C.ManagementAction.FarmEdit,"building_id":int(expected.target_id),"farm_operation":C.FarmOperation.ItemHidden,"item_id":row.id,"item_value":int(value),"expected_revision":page.revision}
			var result:=await request("production",edit);var production: Dictionary=result.get("production",{})
			if not check(result.get("status")==C.ManagementStatus.Ok and production.get("farm_edit_outcome")==C.FarmEditOutcome.Completed,"Chest edit failed"):break
			page=production.get("contents",{})
			check(Contents.valid_page(page,int(expected.target_id)) and page.rows[0].id==row.id and page.rows[0].hidden==value,"Chest receipt mismatch")
			receipts.append({"id":row.id,"value":value,"revision":str(page.revision)})
			if value!=row.hidden:
				edit.expected_revision=old
				var stale:=await request("production",edit)
				check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("production",{}).get("farm_edit_outcome")==C.FarmEditOutcome.Stale and not stale.get("production",{}).has("contents"),"Stale chest edit granted authority")
	var restored:=await request("production",intent)
	check(restored.get("production",{}).get("contents",{})==initial,"Chest state not restored")
	var foreign={"action":C.ManagementAction.FarmEdit,"building_id":int(expected.target_id),"farm_operation":C.FarmOperation.ItemHidden,"item_id":int(expected.foreign_item),"item_value":1,"expected_revision":initial.revision}
	var rejected:=await request("production",foreign)
	check(rejected.get("status")==C.ManagementStatus.Rejected and not rejected.get("production",{}).has("contents"),"Foreign item accepted")
	var file:=FileAccess.open(directory+"/chest-contents-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"initial":initial,"receipts":receipts,"stale_rejected":true,"foreign_rejected":true,"restored":not failed}));file.close()
	world.detach_live();world.queue_free();await process_frame
	if not failed:print("CHEST_CONTENTS_PASS")
	quit(1 if failed else 0)
