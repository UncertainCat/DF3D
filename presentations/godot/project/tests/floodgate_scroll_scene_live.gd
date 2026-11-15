extends "res://tests/floodgate_scene_live.gd"
# Approved correction: native has no link scrollbar. Compare row content to
# native, and independently verify scrolling reaches the actual final row.
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture");exercised=true
	var entry: Dictionary=expected.buildings[0]
	owner.open_target(int(entry.id))
	if not await chest_ready():return
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(0).get_center())
	var view=owner.panel.links_view
	check(owner.panel.showing_links and view.scrollbar.visible,"Populated links have no visible scrollbar")
	check(owner.links.snapshot.total==entry.expected_link_items.size() and owner.links.snapshot.total==12,"Controlled linked row count differs")
	var ids: Array=[]
	for row in view.rows:ids.append(row.item_id)
	var expected_ids: Array=[]
	for id in entry.expected_link_items:expected_ids.append(int(id))
	check(ids==expected_ids,"Linked mechanisms lost native order: "+str(ids)+" expected "+str(expected_ids))
	await capture_rows("top",true)
	await pointer(view.get_global_transform_with_canvas()*Vector2(464,view.page*36-6))
	if not await chest_ready():return
	check(view.cell_first==1,"Scrollbar arrow did not move one text cell")
	await capture_rows("partial",false)
	var bottom: int=(int(owner.links.snapshot.total)-view.page)*3
	for index in bottom+2:
		await pointer(view.get_global_transform_with_canvas()*Vector2(100,18),MOUSE_BUTTON_WHEEL_DOWN)
		if not await chest_ready():return
	check(view.cell_first==bottom and view.rows[-1].item_id==int(entry.expected_link_items[-1]),"Scroll did not reach final linked mechanism")
	await capture_rows("tail",true)
	var last: int=view.visible_count()-1
	var last_row: Dictionary=view.rows[last]
	check(last_row.item_id==int(entry.expected_link_items[-1]),"Last visible row is not the final link")
	var calls: Array=[];owner.focus_requested.connect(func(tile):calls.append(tile))
	await pointer(view.get_global_transform_with_canvas()*view.recenter_rect(last).get_center());await drain()
	check(calls==[Vector3i(last_row.x,last_row.y,last_row.z)] and world.get_top_z()==int(last_row.z),"Final linked row recenter changed destination")
	check(scene._ui.host.active==null and owner.links.building_id<0,"Recenter retained panel ownership")
	owner.open_target(int(entry.id))
	if not await chest_ready():return
	check(not owner.panel.showing_links,"Reopen retained linked tab")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(0).get_center())
	check(view.cell_first==0,"Reopen retained old scroll offset")
	key(KEY_ESCAPE);await drain()

func capture_rows(label: String,compare_row: bool) -> void:
	var event:=InputEventMouseMotion.new();event.position=Vector2.ZERO;root.push_input(event,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	image.save_png(directory+"/linked-scroll-"+label+".png")
	if compare_row:
		var view=owner.panel.links_view
		var origin:=Vector2i(view.get_global_transform_with_canvas()*Vector2.ZERO)
		var region:=Rect2i(origin,Vector2i(400,36))
		var native:=Image.load_from_file(directory+"/workshop-furniture-9-links.png");native.convert(Image.FORMAT_RGB8)
		check(image.get_region(region).get_data()==native.get_region(region).get_data(),"Corrected scrollbar changed native row artwork or text: "+label)
