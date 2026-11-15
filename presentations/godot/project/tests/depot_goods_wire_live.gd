extends "res://tests/machinery_wire_live.gd"
const GoodsModel=preload("res://scripts/depot_goods_state.gd")
func controller_commit(intent: Dictionary) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new()
	root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=GoodsModel.new();model.configure(service);model.open(intent.depot_id)
	var result: Dictionary={}
	if await settle_goods(model,service):
		check(model.revision==intent.expected_revision,"Controller draft source changed")
		model.toggle_group(0)
		if await settle_goods(model,service):
			check(model._draft.size()==intent.changes.size() and intent.changes.all(func(row):return model._draft.get(row.id)==row.desired),"Group draft differs from expected commit")
			model.finish()
			var ticket: int=model.ticket
			var deadline:=Time.get_ticks_msec()+5000
			while model.phase==GoodsModel.Phase.Applying and Time.get_ticks_msec()<deadline:
				world.poll();service.poll(0.01);await create_timer(0.01).timeout
			result=service.result(ticket)
			check(model.phase==GoodsModel.Phase.Closed and model.depot_id==-1,"Applied controller commit did not close picker")
	model.dispose();service.queue_free();await process_frame
	return result
func verify_draft_controls(model,service) -> void:
	var ids: Array=model.groups[0].item_ids.duplicate();var other: int=model.categories[1].type
	var source: int=model.revision
	model.toggle_item(ids[1])
	if not await settle_goods(model,service):return
	check(model.items[ids[1]].tag==1 and model.groups[0].item_ids==ids and model.groups[0].flags==2,"Individual draft moved rows or lost mixed group state")
	model.select_category(other)
	if not await settle_goods(model,service):return
	model.select_category(45)
	if not await settle_goods(model,service):return
	check(model.groups[0].item_ids==[ids[1],ids[0]],"Category navigation failed to sort selected item first")
	model.set_query("IRON")
	if not await settle_goods(model,service):return
	check(model.groups[0].item_ids==[ids[1],ids[0]] and model.groups[0].flags==2,"Search lost draft/order")
	model.set_query("")
	if not await settle_goods(model,service):return
	model.toggle_group(0)
	if not await settle_goods(model,service):return
	check(model.groups[0].flags==1,"Mixed group did not select all native members")
	model.toggle_all()
	if not await settle_goods(model,service):return
	check(model.groups[0].flags==2 and model.groups[0].item_ids==[ids[1],ids[0]],"Select All changed sorting basis")
	model.select_category(other)
	if not await settle_goods(model,service):return
	model.select_category(45)
	if not await settle_goods(model,service):return
	model.request_items(ids)
	if not await settle_goods(model,service):return
	check(model.revision==source and model.groups[0].item_ids==ids and model.items.values().all(func(row):return row.tag==0),"Draft roundtrip did not restore native projection")
func verify_commit(read_intent: Dictionary,initial: Dictionary) -> Array:
	var receipts: Array=[];var changes: Array=[]
	for row in initial.items:changes.append({"id":row.id,"desired":true})
	var intent: Dictionary={"action":C.ManagementAction.DepotGoodsCommit,"depot_id":initial.depot_id,"expected_revision":initial.revision,"changes":changes}
	for patch in [{"expected_revision":0},{"changes":[]},{"changes":[changes[0],changes[0]]},{"changes":[{"id":changes[0].id,"desired":1}]}]:
		var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
		check(world.management_request("depot_goods",invalid)==0,"Malformed depot commit reached transport")
	var foreign: Dictionary=intent.duplicate(true);foreign.changes=[{"id":2147483647,"desired":true}]
	var rejected:=await request("depot_goods",foreign)
	check(rejected.get("depot_commit",{}).get("outcome")==C.DepotGoodsCommitOutcome.Rejected,"Foreign depot commit did not reject: "+str(rejected.get("depot_commit",{}))+" "+str(rejected.get("message","")))
	if failed:return receipts
	var applied:=await controller_commit(intent);receipts.append(applied)
	if not check(applied.get("depot_commit",{}).get("outcome")==C.DepotGoodsCommitOutcome.Applied,"Depot batch was not applied"):return receipts
	check(applied.depot_commit.expected_revision==initial.revision and applied.depot_commit.observed_revision==initial.revision,"Commit receipt lost source identity")
	var pending_reply:=await request("depot_goods",read_intent);var pending: Dictionary=pending_reply.get("depot_goods",{})
	if not check(pending.get("items",[]).size()==changes.size() and pending.items.all(func(row):return row.tag==2),"Native pending jobs absent after wire commit"):return receipts
	var stale:=await request("depot_goods",intent);receipts.append(stale)
	check(stale.get("depot_commit",{}).get("outcome")==C.DepotGoodsCommitOutcome.Stale and stale.depot_commit.observed_revision==pending.revision,"Old creation receipt did not reject as stale")
	intent.expected_revision=pending.revision
	for row in intent.changes:row.desired=false
	var cancelled:=await controller_commit(intent);receipts.append(cancelled)
	if not check(cancelled.get("depot_commit",{}).get("outcome")==C.DepotGoodsCommitOutcome.Applied,"Wire cancellation failed"):return receipts
	var restored:=await request("depot_goods",read_intent)
	check(restored.get("depot_goods",{})==initial,"Wire cancellation did not restore native goods facts")
	var late:=await request("depot_goods",intent);receipts.append(late)
	check(late.get("depot_commit",{}).get("outcome")==C.DepotGoodsCommitOutcome.Stale,"Old cancellation receipt did not reject as stale")
	return receipts
func settle_goods(model,service) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and model.phase==GoodsModel.Phase.Reading:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==GoodsModel.Phase.Ready,"Depot controller did not settle: "+str(model.last_result))
func verify_controller(intent: Dictionary,snapshot: Dictionary) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new()
	root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=GoodsModel.new();model.configure(service);model.open(intent.depot_id)
	if await settle_goods(model,service):
		model.select_category(intent.category)
		if await settle_goods(model,service):
			model.set_query(intent.query)
			if await settle_goods(model,service):
				model.set_options(intent.sort_by_distance,intent.pending_on_top,intent.exclude_prohibited)
				if await settle_goods(model,service):
					model.request_items(intent.item_ids)
					if await settle_goods(model,service):
						check(model.category==snapshot.category and model.revision==snapshot.revision and model.appraisal==snapshot.appraisal,"Controller source identity/knowledge differs")
						check(model.categories==snapshot.categories and model.groups==snapshot.groups,"Controller projection differs from native")
						check(model.items.size()==snapshot.items.size(),"Controller detail count differs")
						for row in snapshot.items:check(model.items.get(row.id)==row,"Controller detail differs")
						if intent.exclude_prohibited and snapshot.groups.all(func(row):return row.item_ids.is_empty()):check(model.row_count()==0,"Controller exposed native empty-list groups")
	if intent.category==45 and intent.query.is_empty() and not intent.exclude_prohibited and snapshot.items.size()==2 and snapshot.items.all(func(row):return row.tag==0):await verify_draft_controls(model,service)
	model.request_appearances(intent.item_ids.slice(0,2))
	var artwork_deadline:=Time.get_ticks_msec()+5000
	while model.appearance_pending() and Time.get_ticks_msec()<artwork_deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(not model.appearance_pending(),"Depot artwork inspection timed out")
	var appearances: Dictionary=model.appearances.duplicate(true)
	for id in intent.item_ids.slice(0,2):check(not appearances.get(id,{}).is_empty(),"Depot native appearance unavailable: "+str(id))
	model.close();model.open(intent.depot_id);var retired: int=model.ticket;service.poll(0.01);model.close()
	var deadline:=Time.get_ticks_msec()+5000
	while service.result(retired).is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(service.result(retired).get("status")==C.ManagementStatus.Ok,"Detached depot read did not finish")
	check(model.phase==GoodsModel.Phase.Closed and model.groups.is_empty(),"Late depot reply revived closed picker")
	model.dispose();service.queue_free();await process_frame
	return appearances
func verify_container_controller(intent: Dictionary,snapshot: Dictionary) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new()
	root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=GoodsModel.new();model.configure(service);model.open(intent.depot_id)
	var appearances: Dictionary={}
	if await settle_goods(model,service):
		model.select_category(intent.category)
		if await settle_goods(model,service):
			model.request_items(intent.item_ids)
			if await settle_goods(model,service):
				var parent: int=intent.container_id;var count: int=model.row_count()
				model.toggle_container(parent)
				check(model.row_count()==count+snapshot.container.total,"Controller did not expose child slots")
				model.request_contents(parent,intent.container_offset,intent.container_limit)
				if await settle_goods(model,service):
					for i in snapshot.container.items.size():check(model.contained_item(parent,i)==snapshot.container.items[i],"Controller child differs from native")
					var ids: Array=intent.item_ids.slice(0,4)
					for row in snapshot.container.items:ids.append(row.id)
					model.request_appearances(ids)
					var deadline:=Time.get_ticks_msec()+10000
					while model.appearance_pending() and Time.get_ticks_msec()<deadline:
						world.poll();service.poll(0.01);await create_timer(0.01).timeout
					check(not model.appearance_pending(),"Child artwork read timed out")
					for id in ids:check(not model.appearances.get(id,{}).is_empty(),"Child/parent artwork unavailable: "+str(id))
					appearances=model.appearances.duplicate(true)
					var source: int=model.revision;model.set_query("BIN")
					if await settle_goods(model,service):check(model._container_expanded.get(parent,false) and model.revision==source,"Search discarded expansion/source")
					model.set_query("")
					if await settle_goods(model,service):
						model.select_category(45)
						if await settle_goods(model,service):
							model.select_category(intent.category)
							if await settle_goods(model,service):check(model.row_count()==count+snapshot.container.total,"Category return discarded container expansion")
	model.dispose();service.queue_free();await process_frame
	return appearances
func integers(value):
	if value is float:return int(value)
	if value is Array:
		var result: Array=[]
		for entry in value:result.append(integers(entry))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=integers(value[key])
		return result
	return value
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Depot goods attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var catalog:=await request("construction",{"action":C.ManagementAction.Catalog})
	if not check(catalog.get("status")==C.ManagementStatus.Ok,"Depot goods catalog failed"):quit(1);return
	var expected: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-wire-expected.json")))
	var intent: Dictionary=expected.request;intent.action=C.ManagementAction.DepotGoodsRead
	if intent.has("expected_revision"):intent.expected_revision=int(intent.expected_revision)
	var response:=await request("depot_goods",intent)
	var snapshot: Dictionary=response.get("depot_goods",{})
	var appearances: Dictionary={}
	var commits: Array=[]
	if check(response.get("status")==C.ManagementStatus.Ok and not snapshot.is_empty(),"Depot goods snapshot unavailable: "+str(response)):
		check(snapshot.depot_id==intent.depot_id and snapshot.category==intent.category and snapshot.revision>0 and snapshot.appraisal==expected.appraisal,"Depot goods identity/knowledge differs")
		for key in ["categories","groups","items"]:check(snapshot[key]==expected[key],"Depot goods "+key+" differs: "+str(snapshot[key]))
		if expected.has("container"):check(snapshot.get("container")==expected.container,"Depot container page differs")
		var again:=await request("depot_goods",intent)
		check(again.get("depot_goods",{})==snapshot,"Repeated paused read changed source revision")
		var categories: Dictionary=intent.duplicate(true);categories.category=-1;categories.item_ids=[]
		for key in ["container_id","container_offset","container_limit"]:categories.erase(key)
		var overview:=await request("depot_goods",categories)
		var value: Dictionary=overview.get("depot_goods",{})
		check(value.get("categories")==snapshot.categories and value.get("revision")==snapshot.revision and value.get("groups")==[] and value.get("items")==[],"Depot category-only read differs")
		if not intent.has("expected_revision"):appearances=await verify_controller(intent,snapshot)
		if expected.has("container"):
			appearances=await verify_container_controller(intent,snapshot)
			for patch in [{"expected_revision":2 if snapshot.revision==1 else snapshot.revision-1},{"container_offset":expected.container.total+1},{"container_id":expected.container.items[0].id}]:
				var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
				var rejection:=await request("depot_goods",invalid)
				check(rejection.get("status")==C.ManagementStatus.Rejected and not rejection.has("depot_goods"),"Invalid container source/page retained a snapshot")
	for patch in [{"depot_id":2147483647},{"item_ids":[2147483647]}]:
		var invalid: Dictionary=intent.duplicate(true);invalid.merge(patch,true)
		var rejection:=await request("depot_goods",invalid)
		check(rejection.get("status")==C.ManagementStatus.Rejected and not rejection.has("depot_goods"),"Invalid depot target retained a snapshot")
	if not failed and expected.label=="anvils":commits=await verify_commit(intent,snapshot)
	var file:=FileAccess.open(directory+"/depot-goods-wire-"+str(expected.label)+"-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"label":expected.label,"snapshot":snapshot,"appearances":appearances,"commits":commits}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
