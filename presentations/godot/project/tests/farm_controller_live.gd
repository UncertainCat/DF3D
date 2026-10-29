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
	farm.open(int(fixture.nonfarm),0)
	if not await settled(Farm.Phase.Rejected):return
	farm.dispose();actions.free()
	write_json("farm-controller-results.json",{"initial_current_tab":true,"queued_tab_change_no_effects":true,
		"sent_tab_change_effect_without_old_observer":true,"display_order_retained":true,
		"stale_external_change_refused":true,"rename_and_clear":true,"queued_rename_retired":true,
		"sent_rename_effect_without_old_observer":true,"native_checks":handshake,"completed_observers":applied_count})
