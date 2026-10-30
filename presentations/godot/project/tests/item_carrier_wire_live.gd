extends SceneTree
const C=preload("res://scripts/management_contract.gd")
var world
var failed:=false
var directory: String
func inspect_render(_snapshot: Dictionary) -> void:pass
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> bool:
	if not ok:failed=true;push_error(message)
	return ok
func request(domain: String,data: Dictionary) -> Dictionary:
	world.poll()
	var sequence: int=world.management_request(domain,data)
	if not check(sequence>0,"Carrier command not sent"):return {}
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();var result: Dictionary=world.poll_management()
		if result.get("request_seq",0)==sequence and result.get("status",0) in [C.ManagementStatus.Ok,C.ManagementStatus.Rejected]:return result
		await create_timer(0.01).timeout
	check(false,"Carrier outcome unknown; no replay");return {}
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/carrier-expected.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Carrier bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Carrier catalog failed"):quit(1);return
	var intent: Dictionary={"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":int(expected.snapshot.id)}
	var response:=await request("production",intent)
	var snapshot: Dictionary=response.get("production",{}).get("independent_item",{}).get("snapshot",{})
	if not check(response.get("status")==C.ManagementStatus.Ok and not snapshot.is_empty(),"Carrier read failed"):quit(1);return
	check(str(snapshot.revision)==expected.snapshot.revision,"Carrier exact revision changed across wire")
	for key in ["id","item_type","description","weight"]:check(snapshot.get(key)==expected.snapshot[key],"Independent item field differs: "+key)
	if expected.snapshot.has("appearance"):
		for key in ["material_token","subtype_raw","color_token","stack","flags"]:check(snapshot.get("appearance",{}).get(key)==expected.snapshot.appearance[key],"Item appearance differs: "+key)
	if expected.snapshot.get("appearance",{}).has("instrument"):
		for key in ["family","placed"]:check(snapshot.appearance.get("instrument",{}).get(key,-1)==int(expected.snapshot.appearance.instrument[key]),"Instrument appearance differs: "+key)
	if expected.snapshot.has("carrier"):
		for key in ["kind","id","item_type","name"]:check(snapshot.get("carrier",{}).get(key)==expected.snapshot.carrier[key],"Carrier field differs: "+key)
	if expected.snapshot.has("holder"):
		for key in ["id","type"]:check(snapshot.get("holder",{}).get(key,-1)==int(expected.snapshot.holder[key]),"Independent item holder differs: "+key)
		check(snapshot.get("holder",{}).get("name","")==expected.snapshot.holder.name,"Independent item holder name differs")
	if snapshot.get("carrier",{}).get("kind",0)==1:
		for key in ["material_token","subtype_raw","color_token","stack","flags"]:
			check(snapshot.carrier.get("appearance",{}).get(key)==expected.snapshot.carrier.appearance[key],"Carrier appearance differs: "+key)
	var model=preload("res://scripts/item_sheet_state.gd").new();model.item_id=int(expected.snapshot.id)
	check(model._valid(snapshot),"Controller rejected native carrier snapshot")
	await inspect_render(snapshot)
	if expected.has("prior_revision"):
		var stale:=intent.duplicate();stale.action=C.ManagementAction.FarmEdit;stale.farm_operation=C.FarmOperation.ItemHidden;stale.item_value=1;stale.expected_revision=int(expected.prior_revision)
		var result:=await request("production",stale)
		var state: Dictionary=result.get("production",{}).get("independent_item",{})
		check(result.get("status")==C.ManagementStatus.Rejected and state.get("outcome")==C.FarmEditOutcome.Stale and not state.has("snapshot"),"Old carrier revision granted authority")
	var receipts: Array=[]
	for value in [not snapshot.hidden,snapshot.hidden]:
		if failed:break
		var edit:=intent.duplicate();edit.action=C.ManagementAction.FarmEdit;edit.farm_operation=C.FarmOperation.ItemHidden;edit.item_value=int(value);edit.expected_revision=snapshot.revision
		var result:=await request("production",edit)
		var state: Dictionary=result.get("production",{}).get("independent_item",{})
		if not check(result.get("status")==C.ManagementStatus.Ok and state.get("outcome")==C.FarmEditOutcome.Completed,"Carrier edit not confirmed"):break
		snapshot=state.get("snapshot",{})
		check(model._valid(snapshot) and snapshot.hidden==value and snapshot.id==int(expected.snapshot.id),"Carrier receipt mismatch")
		var receipt={"value":value,"revision":str(snapshot.revision),"id":snapshot.id}
		if snapshot.has("carrier"):
			check(snapshot.carrier.id==int(expected.snapshot.carrier.id),"Carrier receipt identity differs")
			receipt.carrier=snapshot.carrier
		if snapshot.has("holder"):receipt.holder=snapshot.holder
		receipts.append(receipt)
	var file:=FileAccess.open(directory+"/carrier-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts,"stale_checked":expected.has("prior_revision")}));file.close()
	world.detach_live();world.queue_free();await process_frame
	if not failed:print("ITEM_CARRIER_WIRE_PASS")
	quit(1 if failed else 0)
