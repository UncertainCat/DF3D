extends "res://tests/item_carrier_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stone-use-native.json"))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Stone use bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var reply:=await request("stone_use",{"action":C.ManagementAction.StoneUseRead})
	if not check(reply.get("status")==C.ManagementStatus.Ok,"Stone use read rejected"):quit(1);return
	var value: Dictionary=reply.stone_use
	check(value.rows.size()==reference.provider.size(),"Stone use row count differs")
	for i in mini(value.rows.size(),reference.provider.size()):
		var expected_row: Dictionary=reference.provider[i].duplicate(true)
		expected_row.category=int(expected_row.category);expected_row.index=int(expected_row.index)
		check(value.rows[i]==expected_row,"Stone use metadata differs at row "+str(i))
	var expected_flags: Array=[]
	for flag in reference.edits.before:expected_flags.append(int(flag))
	check(value.restrictions==expected_flags,"Stone use full restriction receipt differs")
	var completed:=0
	for step in reference.edits.steps:
		if failed:break
		var intent: Dictionary={"action":C.ManagementAction.StoneUseApply,"category":int(step.category),"index":int(step.index),"expected":value.restrictions}
		reply=await request("stone_use",intent)
		check(reply.get("status")==C.ManagementStatus.Ok and reply.get("stone_use",{}).get("outcome")==C.StoneUseOutcome.Applied,"Stone use edit rejected")
		check(reply.stone_use.rows.is_empty() and reply.stone_use.restrictions.is_empty(),"Stone use edit returned authority")
		var stale:=await request("stone_use",intent)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("stone_use",{}).get("outcome")==C.StoneUseOutcome.Stale,"Stone use stale receipt accepted")
		reply=await request("stone_use",{"action":C.ManagementAction.StoneUseRead});value=reply.stone_use
		check(value.restrictions[int(step.index)]==int(step.restricted),"Stone use refresh differs")
		completed+=1
		var f:=FileAccess.open(directory+"/stone-use-wire-step",FileAccess.WRITE);f.store_string(str(completed));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/stone-use-wire-ack") and FileAccess.get_file_as_string(directory+"/stone-use-wire-ack").strip_edges()==str(completed):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/stone-use-wire-ack").strip_edges()==str(completed),"Stone use independent effect not acknowledged")
	check(completed==4,"Stone use edits incomplete")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed,"rows":value.rows.size()}));output.close()
	quit(1 if failed else 0)
