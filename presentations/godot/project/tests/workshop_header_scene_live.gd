extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "workshop-native.json"
func result_filename() -> String:return "workshop-wire-result.json"
func workshop_ready() -> bool:
	if not await chest_ready():
		print("WORKSHOP_HEADER_STATE ",owner.state.phase," contents ",owner.contents.phase)
		return false
	if not owner.state.snapshot.removing and not await settle(owner.tasks):return false
	return true
func capture_header(label: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(416,52,488,708)
	var crop:=image.get_region(region);crop.save_png(directory+"/workshop-header-"+label+"-live.png")
	var native:=Image.load_from_file(directory+"/workshop-header-"+label+".png");native.convert(Image.FORMAT_RGB8)
	check(crop.get_data()==native.get_region(region).get_data(),"Main workshop header pixels differ: "+label)
func type_text(value: String) -> void:
	for character in value:key(0,character.unicode_at(0))
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("workshop")
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	await pointer(Vector2(800,82));type_text("lower workshop");key(KEY_ENTER)
	await drain()
	if not await workshop_ready():return
	check(owner.state.snapshot.custom_name==expected.header_reference.original_name+"lower workshop","Workshop rename did not commit")
	await capture_header("renamed")
	await pointer(Vector2(800,82));type_text(" appended");key(KEY_ESCAPE)
	await drain();await process_frame
	check(scene._ui.host.active==null and owner.state.building_id==-1,"Escape retained workshop ownership")
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	check(owner.state.snapshot.custom_name==expected.header_reference.original_name+"lower workshop appended","Escape lost typed workshop name")
	await pointer(Vector2(800,82))
	for i in 100:key(KEY_BACKSPACE)
	type_text(expected.header_reference.original_name);key(KEY_ENTER);await drain()
	if not await workshop_ready():return
	await capture_header("restored")
	await pointer(Vector2(832,82))
	if not await workshop_ready():return
	check(owner.state.snapshot.removing and not owner.panel.tasks.visible,"Removal retained editable task body")
	await capture_header("remove")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await workshop_ready():return
	check(not owner.state.snapshot.removing and owner.tasks.jobs().is_empty(),"Cancel removal did not restore empty workshop")
	await capture_header("cancel")
	owner.close_panel();owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER");owner.close_panel();await drain();await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible and owner.tasks.building_id==-1,"Late read revived closed workshop")
	exercised=true
