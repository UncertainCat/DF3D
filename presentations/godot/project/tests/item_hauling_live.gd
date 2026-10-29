extends "res://tests/areas_acceptance_live.gd"

func settle(model,actions) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if model.ticket==0:return check(model.item_id>=0 and model.last_position!=null,"hauling follow lost target")
		await create_timer(0.01).timeout
	return check(false,"hauling position read timed out")

func exercise() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	if fixture.candidates.is_empty():incomplete("no naturally carried stockpile-hauling item in clone",true);return
	var actions=load("res://scripts/semantic_action_service.gd").new()
	root.add_child(actions);actions.set_process(false);actions.configure(world,true)
	var model=load("res://scripts/item_follow.gd").new();model.configure(actions)
	await hauling_cases(model,actions)
	model.dispose();model.free();actions.free()

func hauling_cases(model,actions) -> void:
	var candidate: Dictionary=fixture.candidates[0]
	var target:=int(candidate.item_id)
	var original:=Vector3i(candidate.position.x,candidate.position.y,candidate.position.z)
	var samples: Array=[];var positions: Array=[original];var moved_carried:=false;var delivered:=false;var after_delivery:=0
	for iteration in 60:
		step="natural hauling sample "+str(iteration)
		if iteration>0:
			if not await request_pause(false):return
			await create_timer(0.3).timeout
			if not await request_pause(true):return
		await native("sample",{"item_id":target})
		if stopped:return
		if iteration==0:model.toggle(target)
		else:model._process(1)
		if not await settle(model,actions):return
		var tile: Vector3i=model.last_position
		var reply:=await native("verify",{"item_id":target,"x":tile.x,"y":tile.y,"z":tile.z})
		if stopped:return
		var observation: Dictionary=reply.observation;samples.append(observation)
		if tile not in positions:positions.append(tile)
		if tile!=original and observation.in_inventory and observation.job_type=="StoreItemInStockpile":moved_carried=true
		if moved_carried and not observation.carried_by_selected_unit and observation.job_id!=candidate.job_id and observation.on_ground and tile==Vector3i(candidate.destination.x,candidate.destination.y,candidate.destination.z):
			delivered=true;after_delivery+=1
		if positions.size()>=4 and delivered and after_delivery>=3:break
	write_json("item-hauling-results.json",{"candidate":candidate,"samples":samples,"distinct_positions":positions.size(),"moved_carried":moved_carried,"delivered":delivered,"after_delivery_samples":after_delivery})
	if not moved_carried or positions.size()<4 or not delivered or after_delivery<3:incomplete("natural hauling did not complete movement and delivery within the bounded run",true)
