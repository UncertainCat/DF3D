extends "res://tests/mesh_batch_motion_live.gd"
func run():
	root.size=Vector2i(1200,792)
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	var deadline=Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	assert(scene._loader.entered)
	assert(await set_paused(true))
	# Hold the normal primary window for still screenshots; no semantic state injected.
	scene._unit_status.set_capture_phase(6000.0)
	var evidence := []
	for z in [128,153,72]:
		await go_level(z)
		var flags: PackedInt64Array=scene.world.unit_status_flags()
		var ids: PackedInt64Array=scene.world.unit_ids()
		var positions: PackedVector3Array=scene.world.unit_positions()
		var chosen := -1
		var chosen_score := -1
		var observed := {}
		for i in flags.size():
			if flags[i] != 0: observed[str(flags[i])] = int(observed.get(str(flags[i]),0))+1
			if preload("res://scripts/unit_status_overlay.gd").variant(flags[i]) >= 0:
				var score := 2 if preload("res://scripts/unit_status_overlay.gd").primary_variant(flags[i]) >= 0 else 1
				if flags[i] & ((1<<39)|(1<<13)|(1<<14)|(1<<15)): score=3
				if score > chosen_score: chosen=i;chosen_score=score
		if chosen<0: continue
		var focus: Vector3=positions[chosen]
		var record={"unit":ids[chosen],"flags":flags[chosen],"position":str(focus),"observed_status_counts":observed}
		scene.world.set_top_z(floori(focus.y))
		for mode in ["df","billboard"]:
			scene.camera_rig.set_df_mode(mode=="df")
			scene._sprite_presentation.set_style("billboard" if mode=="billboard" else "classic")
			scene.camera_rig.focus_on(focus,14)
			await settle()
			assert(scene._unit_status.records.has(ids[chosen]),"Observed status has resident badge")
			var before: int=scene._unit_status.uploads
			for j in 30: await process_frame
			assert(scene._unit_status.uploads==before,"Paused unchanged badges never upload")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"-"+str(z)+"-"+mode+".png")
			record[mode+"_uploads"]=before
		evidence.append(record)
	assert(not evidence.is_empty(),"At least one naturally occurring supported status")
	var f=FileAccess.open(output+"-data.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(evidence,"  "))
	print("FLOOR_PROFILE_PASS")
	quit()
