extends "res://tests/pending_building_scene_live.gd"
func capture_header(kind: int) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.get_region(Rect2i(416,52,488,708)).save_png(directory+"/pending-art-full-"+str(kind)+".png")
	var native:=Image.load_from_file(directory+"/workshop-pending-header-art-"+str(kind)+".png")
	if not check(native!=null,"Native header reference missing"):return
	native.convert(Image.FORMAT_RGB8)
	# This lane qualifies the new header recipe. Full panel captures retain
	# progress/component differences for the separate pending-body work.
	var region:=Rect2i(416,52,488,72)
	check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Native header artwork differs: "+str(kind))
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("pending_building")
	for sample in expected.pending_header_art:
		scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
		owner.open_target(int(sample.id))
		if not await pending_ready():return
		check(not owner.state.snapshot.get("appearance",{}).is_empty(),"Native header recipe missing")
		check(owner.panel.header_texture!=null,"Native header recipe did not resolve installed artwork")
		await capture_header(int(sample.type))
		await key(KEY_ESCAPE);await process_frame
		check(scene._ui.host.active==null and owner.contents.building_id==-1,"Header closure retained authority")
	exercised=true
