extends "res://tests/workshop_header_scene_live.gd"
func connections_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.connections.phase not in [owner.connections.Phase.Reading,owner.connections.Phase.Resolving,owner.connections.Phase.Applying]:break
		await create_timer(0.01).timeout
	await process_frame;await process_frame
	return check(owner.connections.phase==owner.connections.Phase.Ready,"Connections did not become Ready: "+str(owner.connections.phase))
func connection_capture(label: String,reference: String,height: int) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(400,500);root.push_input(motion,true)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(56,52,328,height)
	var crop:=image.get_region(region);crop.save_png(directory+"/workshop-connections-"+label+"-live.png")
	var native:=Image.load_from_file(directory+"/workshop-connections-"+reference+".png");native.convert(Image.FORMAT_RGB8)
	check(crop.get_data()==native.get_region(region).get_data(),"Connections pixels differ: "+label)
func map_pick(point: Dictionary) -> void:
	var tile:=Vector3i(point.x,point.y,point.z)
	scene._ui.focus_tile(tile)
	for i in 15:await process_frame
	var target:=Vector3(tile.x+0.5,tile.z+float(world.floor_height()),tile.y+0.5)
	var position: Vector2=owner.camera.unproject_position(target)
	check(world.pick_tile(owner.camera.project_ray_origin(position),owner.camera.project_ray_normal(position),world.get_top_z())==tile,"Map ray did not reach target pile")
	await pointer(position)
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("workshop")
	owner.open_workshop(int(expected.building_id),"BUILDING_ICON_WORKSHOP_CARPENTER")
	if not await workshop_ready():return
	await pointer(Vector2(768,82))
	if not await connections_ready():return
	check(owner.connections.rows.size()==1 and owner.connections.rows[0].direction==1,"Initial Give row missing")
	await connection_capture("linked-give","linked-give",420)
	await pointer(Vector2(80,82));await process_frame
	check(owner.connections.picking and not owner.panel.visible,"Give picker did not hide parent")
	await connection_capture("give","give",120)
	await pointer(Vector2(328,82))
	if not await connections_ready():return
	check(owner.panel.visible and not owner.connections.picking,"Cancel did not restore parent")
	await pointer(Vector2(112,82))
	var point: Dictionary=expected.connections_reference.pile_tile
	await map_pick(point)
	if not await connections_ready():return
	check(owner.connections.rows.size()==1 and owner.connections.rows[0].direction==2,"Take selection did not reverse link")
	await pointer(Vector2(352,154))
	if not await connections_ready():return
	check(owner.connections.rows.is_empty(),"Remove button retained link")
	await pointer(Vector2(80,82));await map_pick(point)
	if not await connections_ready():return
	check(owner.connections.rows.size()==1 and owner.connections.rows[0].direction==1,"Give restoration failed")
	await pointer(Vector2(328,82));await process_frame
	check(not owner.connections_view.visible and owner.panel.visible and not owner.modal_input,"Done failed to release Connections")
	await pointer(Vector2(768,82));owner.close_panel();await drain();await process_frame
	check(not owner.connections_view.visible and scene._ui.host.active==null,"Late Connections read reopened owner")
	exercised=true
