extends "res://tests/chest_header_live.gd"
var sheet
var contents_model
var rendered:=0
func open_header(id: int) -> void:
	await super.open_header(id)
	if not check(DisplayServer.get_name()!="headless" and world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Chest panel assets/renderer unavailable"):return
	contents_model=preload("res://scripts/building_contents_state.gd").new();contents_model.configure(header_service);contents_model.open(id)
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();header_service.poll(0.01)
		if contents_model.phase!=contents_model.Phase.Reading:break
		await create_timer(0.01).timeout
	if not check(contents_model.phase==contents_model.Phase.Ready,"Chest panel contents unavailable"):return
	root.size=Vector2i(488,708)
	sheet=preload("res://scripts/chest_sheet_view.gd").new();root.add_child(sheet);sheet.configure(world,header_model,null,contents_model)
	sheet.layout(Vector2(1200,800));sheet.position=Vector2.ZERO
	await process_frame;await RenderingServer.frame_post_draw
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/chest-header-expected.json"))
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(directory+"/chest-panel-"+expected.mode+"-"+str(rendered)+".png");rendered+=1
	var native:=Image.load_from_file(directory+"/chest-header-wire-"+expected.mode+".png");native.convert(Image.FORMAT_RGB8)
	check(native.get_region(Rect2i(416,52,488,708)).get_data()==image.get_data(),"Native full chest panel pixels differ")
	var calls: Array=[];sheet.contents.view_requested.connect(func(item):calls.append(item))
	for index in contents_model.snapshot.rows.size():
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
			event.position=sheet.contents.position+sheet.contents.control_rect(index,1).get_center();root.push_input(event,true)
	check(calls==contents_model.snapshot.rows.map(func(row):return row.id),"Chest View input differs, including removal")

	if expected.mode=="idle":
		click_header(Vector2(384,30));check(sheet.name_entry.editing,"Rendered Rename did not start editing")
		for character in "lower chest":
			var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);sheet.feed_name_key(key)
		feed_header_key(KEY_ENTER);await settle_header()
		check(header_model.snapshot.get("custom_name")=="lower chest" and not sheet.name_entry.editing,"Rendered typed name did not finish")
		await compare_panel("renamed","chest-header-renamed")
		click_header(Vector2(384,30))
		for index in 30:feed_header_key(KEY_BACKSPACE)
		feed_header_key(KEY_ENTER);await settle_header()
		check(header_model.snapshot.custom_name==expected.snapshot.custom_name,"Rendered name restore differs")
		click_header(Vector2(416,30));await settle_header();await refresh_contents()
		check(header_model.snapshot.get("removing",false),"Rendered Remove did not act")
		await compare_panel("remove","chest-header-remove")
		click_header(sheet.cancel_rect().get_center());await settle_header();await refresh_contents()
		check(not header_model.snapshot.get("removing",true),"Rendered Cancel removal did not act")
		await compare_panel("restored","chest-header-wire-idle")

func click_header(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)

func feed_header_key(code: Key) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.keycode=code;sheet.feed_name_key(event)

func refresh_contents() -> void:
	contents_model.refresh()
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();header_service.poll(0.01)
		if contents_model.phase!=contents_model.Phase.Reading:break
		await create_timer(0.01).timeout
	check(contents_model.phase==contents_model.Phase.Ready,"Rendered contents refresh failed")

func compare_panel(label: String,reference: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8);image.save_png(directory+"/chest-panel-"+label+".png")
	var native:=Image.load_from_file(directory+"/"+reference+".png");native.convert(Image.FORMAT_RGB8)
	check(native.get_region(Rect2i(416,52,488,708)).get_data()==image.get_data(),"Native chest panel differs after "+label)

func close_header() -> void:
	if sheet!=null:sheet.free();sheet=null
	if contents_model!=null:contents_model.dispose();contents_model=null
	super.close_header()
