extends "res://tests/farm_read_live.gd"
const Farm=preload("res://scripts/farm_state.gd")
const Actions=preload("res://scripts/semantic_action_service.gd")
var actions
var farm
var applied_count:=0
func settled(expected: int) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if farm.phase not in [Farm.Phase.Reading,Farm.Phase.Applying]:
			return check(farm.phase==expected,"farm controller phase differs: "+str(farm.phase))
		await create_timer(0.01).timeout
	incomplete("farm controller timed out; no replay",true);return false
func verify_farm(seasons: Array) -> void:
	await native("verify",{"seasons":seasons,"fertilization":farm.snapshot})
func exercise() -> void:
	await seed_catalog()
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var id:=int(fixture.id)
	var seasons: Array=[]
	for crop in fixture.seasons:seasons.append(int(crop))
	actions=Actions.new();actions.configure(world,true);farm=Farm.new();farm.configure(actions)
	farm.applied.connect(func():applied_count+=1)
	farm.open(id)
	if not await settled(Farm.Phase.Ready):return
	if not check(farm.season==int(fixture.current_season),"open did not select native current season"):return
	farm.select_season(0)
	if not await settled(Farm.Phase.Ready):return
	farm.choose_crop(-1);farm.select_season(2)
	if not await settled(Farm.Phase.Ready):return
	await verify_farm(seasons)
	if stopped:return
	# Once sent, tab navigation retires its observer but does not replay/cancel DF.
	farm.select_season(0)
	if not await settled(Farm.Phase.Ready):return
	farm.choose_crop(-1);actions.poll();farm.select_season(2)
	if not await settled(Farm.Phase.Ready):return
	seasons[0]=-1
	await verify_farm(seasons)
	if stopped:return
	if not check(applied_count==0,"late edit revived old tab observer"):return
	farm.select_season(0)
	if not await settled(Farm.Phase.Ready):return
	var order: Array=farm.row_order.duplicate()
	farm.choose_crop(int(fixture.seasons[0]))
	if not await settled(Farm.Phase.Ready):return
	seasons[0]=int(fixture.seasons[0])
	if not check(farm.row_order==order,"edit reordered displayed rows"):return
	await verify_farm(seasons)
	if stopped:return
	farm.set_seasonal_fertilization(false)
	if not await settled(Farm.Phase.Ready):return
	await verify_farm(seasons)
	if stopped:return
	farm.set_seasonal_fertilization(true)
	if not await settled(Farm.Phase.Ready):return
	farm.toggle_fertilization()
	if not await settled(Farm.Phase.Ready):return
	if not check(farm.snapshot.pending_fertilization==29,"controller did not queue fertilizer"):return
	await verify_farm(seasons)
	if stopped:return
	farm.toggle_fertilization()
	if not await settled(Farm.Phase.Ready):return
	await verify_farm(seasons)
	if stopped:return
	await native("external_change",{"seasons":seasons,"season":0,"crop":-1})
	if stopped:return
	seasons[0]=-1
	farm.choose_crop(int(fixture.seasons[0]))
	if not await settled(Farm.Phase.Stale):return
	if not check(farm.snapshot.is_empty(),"stale controller retained authority"):return
	farm.toggle_fertilization();actions.poll()
	await native("verify",{"seasons":seasons})
	if stopped:return
	farm.refresh()
	if not await settled(Farm.Phase.Ready):return
	farm.choose_crop(int(fixture.seasons[0]))
	if not await settled(Farm.Phase.Ready):return
	seasons[0]=int(fixture.seasons[0])
	await verify_farm(seasons)
	if stopped:return
	var before_rename: Dictionary=farm.snapshot.duplicate(true)
	farm.rename("controller farm")
	if not await settled(Farm.Phase.Ready):return
	if not check(farm.snapshot.custom_name=="controller farm" and farm.snapshot.header_name=="Controller farm","controller rename receipt differs"):return
	await native("verify",{"seasons":seasons,"name":"controller farm"})
	if stopped:return
	farm.rename("")
	if not await settled(Farm.Phase.Ready):return
	if not check(farm.snapshot==before_rename,"controller clear did not restore original receipt"):return
	var before_observers:=applied_count
	farm.rename("queued name");farm.close();actions.poll();farm.open(id,1)
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":""})
	if stopped:return
	if not check(applied_count==before_observers,"queued retired rename completed"):return
	farm.rename("sent name");actions.poll();farm.close();farm.open(id,1)
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":"sent name"})
	if stopped:return
	if not check(applied_count==before_observers and farm.snapshot.custom_name=="sent name","sent rename revived retired observer or lost effect"):return
	farm.rename("")
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":""})
	if stopped:return
	# The service-owned typing session drains explicit edits after its view ends,
	# before a later queued read can observe a partially entered name.
	var rename_session=preload("res://scripts/farm_rename_session.gd").new()
	actions.add_child(rename_session);rename_session.configure(actions,farm.snapshot)
	var rename_events: Array=[]
	rename_session.finished.connect(func():rename_events.append("finished"))
	rename_session.failed.connect(func(_result):rename_events.append("failed"))
	rename_session.edit("A");actions.poll();rename_session.edit("AB");rename_session.edit("ABC");rename_session.finish()
	farm.close();farm.open(id,1)
	if not await settled(Farm.Phase.Ready):return
	if not check(rename_events==["finished"] and farm.snapshot.custom_name=="ABC","ended typing session lost final text or read before continuation"):return
	await native("verify",{"seasons":seasons,"name":"ABC"})
	if stopped:return
	farm.rename("")
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":""})
	if stopped:return
	var entry=preload("res://scripts/farm_name_entry.gd").new();root.add_child(entry)
	entry.edited.connect(farm.edit_name_entry);entry.submitted.connect(farm.finish_name_entry)
	for ending in ["enter","close","tab"]:
		entry.begin(farm.snapshot.custom_name)
		if not check(farm.begin_name_entry(),"live name workflow could not begin"):return
		for byte in "typed farm".to_utf8_buffer():
			var event:=InputEventKey.new();event.pressed=true;event.unicode=byte;entry.feed_key(event)
			if byte==116:actions.poll()
		entry.finish()
		if ending=="enter":farm.finish_name_entry()
		elif ending=="close":farm.close();farm.open(id,1)
		else:farm.select_season(2)
		if not await settled(Farm.Phase.Ready):return
		if not check(farm.snapshot.custom_name=="typed farm" and farm.snapshot.header_name=="Typed farm","live typed name was lost or misformatted"):return
		await native("verify",{"seasons":seasons,"name":"typed farm"})
		if stopped:return
		farm.rename("")
		if not await settled(Farm.Phase.Ready):return
		await native("verify",{"seasons":seasons,"name":""})
		if stopped:return
	entry.queue_free()
	await disconnect_cases(id,seasons)
	if stopped:return
	await replacement_case(id,seasons)
	if stopped:return
	farm.open(int(fixture.nonfarm),0)
	if not await settled(Farm.Phase.Rejected):return
	farm.dispose();actions.free()
	write_json("farm-controller-results.json",{"initial_current_tab":true,"queued_tab_change_no_effects":true,
		"sent_tab_change_effect_without_old_observer":true,"display_order_retained":true,
		"stale_external_change_refused":true,"rename_and_clear":true,"queued_rename_retired":true,
		"sent_rename_effect_without_old_observer":true,"finished_typing_drains_before_read":true,
		"typed_controller_enter_close_tab":true,"native_checks":handshake,"completed_observers":applied_count})

func disconnect_cases(id: int,seasons: Array) -> void:
	var evidence: Array=[]
	for operation in ["remove","typing"]:
		for sent in [false,true]:
			step="farm disconnect "+operation+" sent="+str(sent)
			await lifecycle_open(id)
			if not await settled(Farm.Phase.Ready):return
			var observers:=applied_count
			await lifecycle_intent(operation)
			if stopped:return
			var pending: int=farm.ticket if operation=="remove" else farm.name_session.ticket
			if not check(pending>0 and actions._requests[pending].sequence==0,"disconnect draft not queued"):return
			if sent:
				actions.poll()
				if not check(actions._requests.has(pending) and actions._requests[pending].sequence>0,"disconnect edit not sent"):return
				var sequence: int=actions._requests[pending].sequence
				var deadline:=Time.get_ticks_msec()+30000
				var receipt: Dictionary={}
				while Time.get_ticks_msec()<deadline:
					world.poll();var candidate: Dictionary=world.poll_management()
					if candidate.get("request_seq")==sequence and candidate.get("status")==S.Ok:receipt=candidate;break
					await create_timer(0.01).timeout
				if not check(not receipt.is_empty() and actions.result(pending).is_empty(),"missing unobserved farm receipt"):return
				write_json("farm-unobserved-"+operation+".json",receipt)
			var expected_name: String="A" if sent and operation=="typing" else ""
			var expected_removing: bool=sent and operation=="remove"
			await native("verify",{"seasons":seasons,"name":expected_name,"removing":expected_removing})
			if stopped:return
			world.detach_live();actions.poll()
			var outcome: Dictionary=actions.result(pending)
			if not check(outcome.get("outcome")==("unknown" if sent else "not_sent"),"disconnect outcome differs"):return
			if not check(farm.phase==Farm.Phase.Unavailable and farm.snapshot.is_empty() and farm.building_id==-1 and farm.ticket==0 and farm.name_session==null,"disconnect retained farm authority"):return
			if not check(actions._requests.is_empty() and actions._queue.is_empty() and actions._active==0,"disconnect retained pending intent"):return
			if not check(world.attach(),"farm reconnect failed"):return
			var deadline:=Time.get_ticks_msec()+60000
			while Time.get_ticks_msec()<deadline:
				world.poll();actions.poll(0.02)
				if world.terrain_loaded() and not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0 and actions._queue.is_empty():break
				await create_timer(0.02).timeout
			if not check(not actions._transport_lost and actions._epoch>0 and not actions._needs_claim and actions._active==0,"farm reconnect not ready"):return
			var next_ticket: int=actions._next_ticket
			for frame in 30:
				world.poll();actions.poll();await process_frame
			if not check(no_farm_requests_since(next_ticket) and applied_count==observers and farm.snapshot.is_empty() and farm.name_session==null,"reconnect replayed edit or revived observer"):return
			await lifecycle_retired("disconnect_"+operation+"_"+str(sent))
			if stopped:return
			await native("verify",{"seasons":seasons,"name":expected_name,"removing":expected_removing})
			if stopped:return
			await lifecycle_open(id)
			if not await settled(Farm.Phase.Ready):return
			if not check(farm.snapshot.custom_name==expected_name and farm.snapshot.removing==expected_removing,"fresh farm read differs"):return
			if expected_removing:farm.cancel_removal()
			elif expected_name!="":farm.rename("")
			if not await settled(Farm.Phase.Ready):return
			await native("verify",{"seasons":seasons,"name":"","removing":false})
			if stopped:return
			evidence.append({"operation":operation,"sent":sent,"outcome":outcome.get("outcome"),"no_replay":true,"fresh_read":true})
	write_json("farm-disconnect-results.json",evidence)

func replacement_case(id: int,seasons: Array) -> void:
	step="farm producer replacement"
	await lifecycle_open(id)
	if not await settled(Farm.Phase.Ready):return
	var old_epoch: int=actions._epoch
	var observers:=applied_count
	await lifecycle_intent("typing")
	if stopped:return
	var pending: int=farm.name_session.ticket
	actions.poll()
	if not check(actions._requests.has(pending) and actions._requests[pending].sequence>0,"replacement edit not sent"):return
	# Keep the observer unpolled until the producer has been replaced. Even a
	# completed old receipt cannot authorize buffered text in the new fortress.
	var ack: Dictionary=await replace_producer(old_epoch)
	if stopped or ack.is_empty():return
	var epoch:=int(str(ack.epoch))
	if not check(farm.phase==Farm.Phase.Unavailable and farm.building_id==-1 and farm.snapshot.is_empty() and farm.name_session==null and applied_count==observers,"old farm observer survived replacement"):return
	if not check(actions.result(pending).get("outcome")=="unknown" and not actions._requests.has(pending),"old farm edit was replayed or confirmed"):return
	var next_ticket: int=actions._next_ticket
	for frame in 30:
		world.poll();actions.poll();await process_frame
	if not check(no_farm_requests_since(next_ticket),"old typing resumed in replacement fortress"):return
	await lifecycle_retired("replacement")
	if stopped:return
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	seasons.clear()
	for crop in fixture.seasons:seasons.append(int(crop))
	await native("verify",{"seasons":seasons,"name":"","removing":false})
	if stopped:return
	await lifecycle_open(int(fixture.id))
	if not await settled(Farm.Phase.Ready):return
	farm.rename("fresh")
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":"fresh"})
	if stopped:return
	farm.rename("")
	if not await settled(Farm.Phase.Ready):return
	await native("verify",{"seasons":seasons,"name":""})
	write_json("farm-replacement-results.json",{"old_epoch":str(old_epoch),"new_epoch":str(epoch),"pid":ack.pid,"old_outcome":actions.result(pending).get("outcome"),"no_continuation_replay":true,"fresh_edit_verified":true})

func lifecycle_open(id: int) -> void:
	farm.open(id,1)

func lifecycle_intent(operation: String) -> void:
	if operation=="remove":farm.request_removal()
	else:
		if not check(farm.begin_name_entry(),"lifecycle typing could not begin"):return
		farm.edit_name_entry("A");farm.edit_name_entry("AB")

func lifecycle_retired(_label: String) -> void:
	pass

func no_farm_requests_since(first: int) -> bool:
	for collection in [actions._requests,actions._results,actions._outcomes]:
		for request_ticket in collection:
			if int(request_ticket)<first:continue
			var record: Dictionary=collection[request_ticket]
			var intent: Dictionary=record.get("request",record)
			if intent.get("action") in [Contract.ManagementAction.FarmEdit,Contract.ManagementAction.ProductionInspect]:return false
	return true

# Shared protected restart handshake; callers keep their own observers unpolled.
func replace_producer(old_epoch: int) -> Dictionary:
	handshake+=1;write_json("request-%d.json" % handshake,{"op":"reload"})
	var file:=FileAccess.open(directory+"/verify.tmp",FileAccess.WRITE)
	file.store_string(str(handshake));file.close()
	if not check(DirAccess.rename_absolute(directory+"/verify.tmp",directory+"/verify.txt")==OK,"farm restart handshake failed"):return {}
	var deadline:=Time.get_ticks_msec()+690000
	var ack: Dictionary={}
	while ack.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();world.poll_session()
		for state in ["failed","incomplete","ack"]:
			var path:=directory+"/%s-%d" % [state,handshake]
			if not FileAccess.file_exists(path):continue
			var reply: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
			if state=="failed":check(false,"farm restart: "+str(reply.reason));return {}
			if state=="incomplete":incomplete("farm restart: "+str(reply.reason),true);return {}
			ack=reply
		await create_timer(0.02).timeout
	if not check(not ack.is_empty(),"farm restart timed out; no replay"):return {}
	var epoch:=int(str(ack.epoch))
	if not check(epoch!=old_epoch and (epoch>>32)==int(ack.pid),"farm replacement identity invalid"):return {}
	deadline=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.02)
		if actions._epoch==epoch and not actions._needs_claim and actions._active==0 and actions._queue.is_empty():break
		await create_timer(0.02).timeout
	if not check(actions._epoch==epoch and actions._active==0 and actions._queue.is_empty(),"farm replacement service not ready"):return {}
	return ack
