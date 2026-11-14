extends "res://tests/workshop_header_scene_live.gd"
func orders_ready() -> bool:
	await drain();await process_frame;await process_frame
	return check(owner.orders.phase==owner.orders.Phase.Ready and owner.orders.rows_available and owner.orders.row_total==12,"Overflow orders unavailable")
func orders_capture(label: String,reference: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var region:=Rect2i((int(root.size.x)/8-98)*8,48+(int(root.size.y)%12)/2,488,(int(root.size.y)/12)*12-84)
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var crop:=image.get_region(region);crop.save_png(directory+"/workshop-orders-"+label+"-live.png")
	var native:=Image.load_from_file(directory+"/workshop-"+reference+".png");native.convert(Image.FORMAT_RGB8)
	check(crop.get_data()==native.get_region(region).get_data(),"Overflow orders pixels differ: "+label)
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("workshop");owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(2).get_center())
	if not await orders_ready():return
	for sample in [["small",Vector2i(960,600)],["wide",Vector2i(1600,900)],["minimum",Vector2i(912,552)],["default",Vector2i(1200,800)]]:
		root.size=sample[1];await process_frame;await process_frame
		await orders_capture(sample[0],"sheet-"+sample[0]+"-Work-orders")
	await pointer(Vector2(880,452));if not await orders_ready():return
	check(owner.orders.row_offset==1,"Orders down arrow failed")
	await orders_capture("arrow","orders-overflow-arrow")
	for i in 20:await pointer(Vector2(880,452))
	if not await orders_ready():return
	check(owner.orders.row_offset==4,"Orders last page unreachable")
	await orders_capture("bottom","orders-overflow-bottom")
	var last: Dictionary=owner.orders.rows[11]
	check(last.id==int(expected.sheet_orders.ids[11]),"Bottom row identity differs")
	for amount in [12,int(expected.sheet_orders.quantity)]:
		await pointer(owner.panel.orders.get_global_transform_with_canvas()*Vector2(328,306))
		for character in str(amount):key(0,character.unicode_at(0))
		key(KEY_ENTER)
		if not await orders_ready():return
		check(owner.orders.rows[11].remaining==amount,"Bottom row amount control edited wrong order")
	for i in 20:await pointer(Vector2(880,178))
	check(owner.orders.row_offset==0,"Orders up arrow failed")
	owner.close_panel();await drain();check(not owner.panel.orders.scrollbar.dragging,"Closed orders retained drag")
	exercised=true
