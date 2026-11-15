extends "res://tests/pending_selection_scene_live.gd"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("pending_building")
	for sample in expected.pending_layout:
		scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
		owner.open_target(int(sample.id))
		if not await pending_ready():return
		for size in sample.sizes:
			root.size={"small":Vector2i(960,600),"medium":Vector2i(1200,720),"wide":Vector2i(1600,900),"default":Vector2i(1200,800)}[size.label]
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
			var label: String="pending-layout-"+str(int(sample.type))+"-"+size.label
			image.get_region(region).save_png(directory+"/viewer-"+label+".png")
			var native:=Image.load_from_file(directory+"/workshop-"+label+".png");native.convert(Image.FORMAT_RGB8)
			check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Pending resize differs: "+label)
		for probe in sample.hover:
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(probe.x,probe.y);root.push_input(motion,true)
			var wanted: String="contents_"+probe.kind if probe.kind!="" else ""
			await process_frame
			var deadline:=Time.get_ticks_msec()+2000
			while scene._fortress_hud.native_help.displayed!=wanted and Time.get_ticks_msec()<deadline:await process_frame
			check(scene._fortress_hud.native_help.displayed==wanted,"Pending hover differs: "+str(probe))
			if probe.kind!="":
				check(probe.enabled,"Native hover was not enabled")
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/viewer-pending-hover-"+probe.kind+".png")
		await key(KEY_ESCAPE);await process_frame;await process_frame
		check(scene._ui.host.active==null and scene._fortress_hud.native_help.displayed.is_empty(),"Closing pending sheet retained hover authority")
	exercised=true
