extends "res://tests/pending_header_art_scene_live.gd"
var tab_handoffs: Array=[]
var handoff: Dictionary={}
func selection_ready(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while model.phase==model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Pending selection did not become ready")
func enter_selection(point: Vector3i,_id: int) -> bool:
	scene._ui.open_tile_selection(point)
	return true
func exercise(expected: Dictionary) -> void:
	var ui=scene._ui
	owner=ui.controller("pending_building")
	tab_handoffs.clear()
	for sample in expected.pending_header_art:
		var point:=Vector3i(sample.tile[0],sample.tile[1],sample.tile[2])
		ui.focus_tile(point)
		var deadline:=Time.get_ticks_msec()+10000
		while world.inspect_entity(3,int(sample.id)).is_empty() and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		if not await enter_selection(point,int(sample.id)):return
		var selection=ui.tile_selection
		var model=selection.navigation.state
		if not await selection_ready(model):return
		if not await pending_ready():return
		check(ui.host.active==owner and owner.state.building_id==int(sample.id),"Selection opened the wrong unfinished building")
		await capture_header(int(sample.type))
		var count: int=selection.tabs.alternatives.size()
		print("PENDING_SELECTION_TABS ",int(sample.id)," count=",count," snapshot=",model.snapshot.get("alternatives",[]))
		var evidence: Dictionary={"selection":model.snapshot,"inspections":[]}
		for entry in model.snapshot.get("alternatives",[]):
			if entry.kind in [1,2,3]:evidence.inspections.append(world.inspect_entity(entry.kind,entry.id))
		var evidence_file:=FileAccess.open(directory+"/pending-selection-facts-"+str(int(sample.type))+".json",FileAccess.WRITE)
		evidence_file.store_string(JSON.stringify(evidence));evidence_file.close()
		if count>0:
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			var region:=Rect2i(896,52,40,count*36)
			image.get_region(region).save_png(directory+"/pending-selection-tabs-"+str(int(sample.type))+".png")
			var native:=Image.load_from_file(directory+"/workshop-pending-header-art-"+str(int(sample.type))+".png");native.convert(Image.FORMAT_RGB8)
			check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Unfinished selection tabs differ: "+str(int(sample.type)))
		if selection.tabs.alternatives.size()>1:
			handoff={"building_id":int(sample.id),"selected":selection.tabs.selected,"complete":false}
			handoff.other=1 if handoff.selected==0 else 0
			handoff.target=model.snapshot.alternatives[handoff.other].duplicate(true)
			print("PENDING_HANDOFF_START ",handoff)
			await pointer(Vector2(920,70+int(handoff.other)*36))
			if not await selection_ready(model):return
			if not check(model.snapshot.kind==handoff.target.kind and model.snapshot.id==handoff.target.id and ui.host.active!=owner and owner.state.building_id==-1,"Tab handoff retained unfinished owner"):return
			await pointer(Vector2(920,70+int(handoff.selected)*36))
			if not await selection_ready(model):return
			if not await pending_ready():return
			check(ui.host.active==owner and owner.state.building_id==int(sample.id),"Building tab did not restore unfinished owner")
			await capture_header(int(sample.type))
			handoff.returned_id=owner.state.building_id;handoff.complete=true
			tab_handoffs.append(handoff.duplicate(true))
		await key(KEY_ESCAPE);await process_frame
		check(ui.host.active==null and model.snapshot.is_empty() and not selection.tabs.visible,"Escape retained unfinished selection")
	var handoffs:=FileAccess.open(directory+"/pending-tab-handoffs.json",FileAccess.WRITE)
	handoffs.store_string(JSON.stringify(tab_handoffs));handoffs.close()
	check(not tab_handoffs.is_empty(),"No alternative tab handoff was exercised")
	exercised=true
