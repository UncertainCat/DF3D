extends "res://tests/areas_acceptance_live.gd"

func settle(model,follow,actions) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll()
		if model.ticket==0 and follow.ticket==0:return true
		await create_timer(0.01).timeout
	return check(false,"item/follow requests did not settle")

func exercise() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string(directory+"/fixture.json"))
	var actions=load("res://scripts/semantic_action_service.gd").new();root.add_child(actions)
	actions.set_process(false);actions.configure(world,true)
	var model=load("res://scripts/item_sheet_state.gd").new();model.configure(actions)
	var follow=load("res://scripts/item_follow.gd").new();follow.configure(actions)
	await progress_cases(model,follow,actions)
	model.dispose();follow.dispose();follow.free();actions.free()

func progress_cases(model,follow,actions) -> void:
	var opened:=false;var consumed:=false;var samples: Array=[]
	for iteration in 100:
		step="fertilizer sample "+str(iteration)
		if iteration>0:
			if not await request_pause(false):return
			await create_timer(0.3).timeout
			if not await request_pause(true):return
		var sample:=await native("sample");if stopped:return
		samples.append(sample)
		if sample.contained and not opened:
			model.open(int(fixture.building_id),int(fixture.item_id))
			if not await settle(model,follow,actions):return
			if not check(model.phase==model.Phase.Ready,"potash inspection unavailable"):return
			await native("verify",{"snapshot":model.view_snapshot(),"revision_text":str(model.snapshot.revision)})
			if stopped:return
			for hidden in [true,false]:
				model.poll(1) # Explicit action must preempt a queued background read.
				model.set_flag(Contract.FarmOperation.ItemHidden,hidden)
				if not await settle(model,follow,actions):return
				if not check(model.phase==model.Phase.Ready and model.snapshot.hidden==hidden,"potash visibility receipt failed"):return
				await native("flags",{"hidden":hidden})
				if stopped:return
			if fixture.has("action"):
				var observations: Array=[]
				var operation: int=Contract.FarmOperation.ItemForbid if fixture.action=="forbid" else Contract.FarmOperation.ItemDump
				for value in [true,false]:
					model.set_flag(operation,value)
					if not await settle(model,follow,actions):return
					if not check(model.phase==model.Phase.Ready and model.snapshot[fixture.action]==value,"active-job action receipt failed"):return
					var observed:=await native("item_action",{"value":value})
					if stopped:return
					if not check(model.snapshot.in_job==observed.in_job,"fresh item sheet retained old job indicator"):return
					observations.append(observed)
				write_json("farm-item-action-results.json",{"action":fixture.action,"observations":observations,"snapshot":model.view_snapshot()})
				return
			follow.toggle(int(fixture.item_id))
			if not await settle(model,follow,actions):return
			if not check(follow.last_position!=null,"potash follow failed"):return
			opened=true
		elif opened:
			model.poll(1);follow._process(1)
			if not await settle(model,follow,actions):return
			if not sample.present:
				if not check(sample.current>fixture.initial and not sample.contained,"potash vanished without fertilization"):return
				if not check(model.phase==model.Phase.Closed and model.item_id==-1 and model.snapshot.is_empty(),"consumed item sheet retained authority"):return
				if not check(follow.item_id==-1 and follow.last_position==null,"consumed item retained follow"):return
				consumed=true;break
			if not check(model.phase==model.Phase.Ready and model.snapshot.id==int(fixture.item_id),"live potash refresh lost target"):return
	if consumed:
		for i in 3:
			model.poll(1);follow._process(1);world.poll();actions.poll()
			if not check(model.ticket==0 and follow.ticket==0 and model.item_id==-1 and follow.item_id==-1,"consumed target restarted"):return
	write_json("farm-item-progress-results.json",{"opened":opened,"consumed":consumed,"samples":samples})
	if not opened or not consumed:incomplete("fertilizer did not complete inspection and consumption within bounded run",true)
