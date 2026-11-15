extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "furniture-expected.json"
func result_filename() -> String:return "workshop-wire-result.json"
func rename_to(value: String) -> bool:
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(384,30))
	if not check(owner.panel.name_entry.editing,"Furniture rename did not start"):return false
	for index in 100:key(KEY_BACKSPACE)
	for character in value:key(0,character.unicode_at(0))
	key(KEY_ENTER)
	if not await chest_ready():return false
	return check(owner.state.snapshot.custom_name==value,"Furniture name differs")
func open_furniture(entry: Dictionary) -> bool:
	owner.open_target(int(entry.id))
	return await chest_ready()
func external_removal(value: bool) -> bool:
	# Deliberately bypass the panel model's applied/refresh callbacks.
	var request={"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":owner.state.building_id,
		"expected_revision":owner.state.snapshot.revision,"farm_operation":C.FarmOperation.Remove if value else C.FarmOperation.CancelRemoval}
	var sent: int=actions.submit("production",request,Callable())
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		var receipt: Dictionary=actions.result(sent)
		if not receipt.is_empty():
			if not check(receipt.get("status",-1)==C.ManagementStatus.Ok,"External removal edit rejected"):return false
			if owner.state.phase==owner.state.Phase.Ready and owner.state.snapshot.removing==value and owner.contents.phase==owner.contents.Phase.Ready and owner.contents.snapshot.removing==value:return true
		await create_timer(0.01).timeout
	return check(false,"Open furniture header did not observe external removal change")
func external_forbid(value: bool) -> bool:
	var request={"action":C.ManagementAction.FarmEdit,"building_id":owner.contents.building_id,
		"expected_revision":owner.contents.snapshot.revision,"farm_operation":C.FarmOperation.ItemForbid,
		"item_id":owner.contents.snapshot.rows[0].id,"item_value":int(value)}
	var sent: int=actions.submit("production",request,Callable())
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		var receipt: Dictionary=actions.result(sent)
		if not receipt.is_empty():
			if not check(receipt.get("status",-1)==C.ManagementStatus.Ok,"External item edit rejected"):return false
			if owner.state.phase==owner.state.Phase.Ready and owner.state.snapshot.forbidden==value and owner.contents.phase==owner.contents.Phase.Ready and owner.contents.snapshot.rows[0].forbid==value:return true
		await create_timer(0.01).timeout
	return check(false,"Open furniture contents did not observe external item change")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		if entry.get("watch_membership",false):
			for stage in ["ready","absent-seen","restored-seen"]:
				if stage!="ready":
					var deadline:=Time.get_ticks_msec()+10000
					var observed:=false
					while Time.get_ticks_msec()<deadline:
						world.poll();actions.poll(0.01)
						var present:=false
						for row in owner.contents.rows():
							if row.id==int(entry.item_id):present=true
						if owner.contents.phase==owner.contents.Phase.Ready and present==(stage=="restored-seen"):observed=true;break
						await create_timer(0.01).timeout
					if not check(observed,"Contents membership did not refresh: "+stage):return
					await panel_capture("membership-"+stage,"furniture-membership-"+("absent" if stage=="absent-seen" else "restored"))
				var marker:=FileAccess.open(directory+"/membership-"+stage,FileAccess.WRITE)
				marker.store_string("ready");marker.close()
			key(KEY_ESCAPE);await drain();continue
		if entry.get("watch_demolition",false):
			check(owner.state.snapshot.removing,"Demolition watcher did not open queued removal")
			var marker:=FileAccess.open(directory+"/demolition-view-ready-"+str(int(entry.id)),FileAccess.WRITE)
			marker.store_string("ready");marker.close()
			var deadline:=Time.get_ticks_msec()+120000
			while owner.state.building_id>=0 and Time.get_ticks_msec()<deadline:
				world.poll();actions.poll(0.01);await create_timer(0.01).timeout
			await process_frame
			if not check(owner.state.building_id==-1 and owner.contents.building_id==-1 and not owner.panel.visible and scene._ui.host.active==null,"Completed demolition did not retire panel and input ownership"):return
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/furniture-closed-"+str(int(entry.id))+".png")
			continue
		if entry.has("reference"):
			var body: Dictionary=owner.state.snapshot.get("funerary",{})
			for field in ["unit_id","historical_figure_id","room_id","room_type","introduction","name","room_introduction","room_name","deceased","notices"]:
				check(body.get(field)==entry.body.get(field),"Funerary variant fact differs: "+field)
			await panel_capture(entry.reference,entry.reference)
			if entry.get("cancel_removal",false):
				check(owner.state.snapshot.removing and owner.state.snapshot.has_worker,"Assigned demolition worker absent from header")
				await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
				if not await chest_ready():return
				check(not owner.state.snapshot.removing,"Worker-owned removal cancellation not confirmed")
				await panel_capture(entry.cancel_reference,entry.cancel_reference)
			key(KEY_ESCAPE);await drain()
			check(scene._ui.host.active==null and not owner.panel.visible,"Funerary variant retained input")
			continue
		var prefix: String="workshop-furniture-"+str(int(entry.type))+"-"
		check(owner.state.snapshot.type==int(entry.type) and owner.state.snapshot.has("appearance"),"Furniture header lacks native type/artwork")
		await panel_capture(str(int(entry.id))+"-initial",prefix+"initial")
		if OS.get_environment("DF3D_FURNITURE_REFRESH")=="1":
			if not await external_removal(true):return
			await panel_capture(str(int(entry.id))+"-external-removing",prefix+"removing")
			if not await external_removal(false):return
			await panel_capture(str(int(entry.id))+"-external-restored",prefix+"restored")
			if not await external_forbid(true):return
			await panel_capture(str(int(entry.id))+"-external-forbidden",prefix+"forbidden")
			if not await external_forbid(false):return
			await panel_capture(str(int(entry.id))+"-external-unforbidden",prefix+"restored")
		if int(entry.type)==3 and OS.get_environment("DF3D_FUNERARY_HOVER")=="1":
			var content_view=owner.panel.contents
			var motion:=InputEventMouseMotion.new()
			motion.position=content_view.get_global_transform_with_canvas()*content_view.control_rect(1,0).get_center()
			root.push_input(motion,true)
			await create_timer(0.6).timeout
			var help=content_view.hover_help
			check(help.displayed=="contents_resting" and help.visible,"Coffin burial tooltip did not appear on its visible indicator")
			check(help.CONTENTS_HELP.resting==entry.funeral.burial_hover.lines.slice(0,2),"Coffin tooltip differs from native text")
		if not await rename_to("Furniture reference"):return
		await panel_capture(str(int(entry.id))+"-renamed",prefix+"renamed")
		if not await rename_to(String(entry.actions[0].name)):return
		var contents=owner.panel.contents
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,2).get_center())
		if not await chest_ready():return
		check(owner.state.snapshot.forbidden and owner.contents.snapshot.rows[0].forbid,"Furniture Forbid did not refresh header and item")
		await panel_capture(str(int(entry.id))+"-forbidden",prefix+"forbidden")
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,2).get_center())
		if not await chest_ready():return
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30))
		if not await chest_ready():return
		check(owner.state.snapshot.removing,"Furniture removal not confirmed")
		await panel_capture(str(int(entry.id))+"-removing",prefix+"removing")
		if OS.get_environment("DF3D_FURNITURE_REMOVAL_CONTROLS")=="1":
			for control in [[2,"forbid"],[3,"dump"],[4,"melt"],[5,"hidden"]]:
				var before: bool=owner.contents.snapshot.rows[0][control[1]]
				for attempt in [1,2]:
					await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,control[0]).get_center())
					if not await chest_ready():return
					check(owner.contents.snapshot.rows[0][control[1]]==(before if control[1]=="melt" or attempt==2 else not before),"Removal component flag differs: "+control[1])
					check(owner.state.snapshot.removing and owner.contents.snapshot.removing,"Component edit lost demolition state")
					var label: String="removing-"+control[1]+"-"+str(attempt)
					await panel_capture(str(int(entry.id))+"-"+label,prefix+label)
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		check(not owner.state.snapshot.removing,"Furniture removal cancellation not confirmed")
		await panel_capture(str(int(entry.id))+"-restored",prefix+"restored")
		await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,1).get_center())
		if not await settle(owner.item_owner.state):return
		check(owner.item_owner.state.item_id==int(entry.actions[0].item_id) and scene._ui.host.active==owner.item_owner and not owner.panel.visible,"Furniture View did not transfer ownership to its component")
		await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Item holder returned to a different building")
		await panel_capture(str(int(entry.id))+"-holder-return",prefix+"restored")
		if int(entry.type)==14 and entry.get("contents",[]).size()>6:
			for direction in [["tail",MOUSE_BUTTON_WHEEL_DOWN],["top",MOUSE_BUTTON_WHEEL_UP]]:
				for step in 45:
					await pointer(contents.get_global_transform_with_canvas()*Vector2(200,18),direction[1])
					if not await chest_ready():return
				check(contents.cell_first==(int(owner.contents.snapshot.total)*3-contents.page*3 if direction[0]=="tail" else 0),"Cabinet did not reach contents boundary")
				await panel_capture("cabinet-"+direction[0],"workshop-furniture-14-contents-"+direction[0])
		if int(entry.type) in [1,3,9,46] and OS.get_environment("DF3D_FURNITURE_RESIZE")=="1":
			for size_case in [["small",Vector2i(960,600)],["medium",Vector2i(1200,720)],["wide",Vector2i(1600,900)],["default",Vector2i(1200,800)]]:
				root.size=size_case[1];await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
				var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
				var native:=Image.load_from_file(directory+"/workshop-furniture-"+str(int(entry.type))+"-resize-"+size_case[0]+".png");native.convert(Image.FORMAT_RGB8)
				var crop:=image.get_region(region);crop.save_png(directory+"/furniture-"+str(int(entry.type))+"-resize-"+size_case[0]+".png")
				check(crop.get_data()==native.get_region(region).get_data(),"Furniture resize differs: "+size_case[0])
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null and not owner.panel.visible,"Furniture Escape retained input")
	exercised=true
