extends "res://tests/trade_exchange_wire_live.gd"
var scene
var owner
func select_item(model,side: int,index: int) -> void:
	await process_frame
	var goods=owner.trade_view.goods
	var canvas: Control=goods.canvases[side]
	var local:=Vector2(goods._row_width(side)-28,(int(model.pages[side].offset)+index)*36-goods.bars[side].first*12+18)
	if not check(Rect2(Vector2.ZERO,canvas.size).has_point(local),"Selected Trade row is outside the visible list"):return
	var point: Vector2=canvas.get_global_transform_with_canvas()*local
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	check(model.phase==model.Phase.Applying and model.ticket>0,"Trade row click did not submit selection")
func initialize_world() -> bool:
	if DisplayServer.get_name()=="headless":return check(false,"Main scene requires rendered execution")
	OS.set_environment("DF3D_FIXTURE","")
	var prefs=preload("res://scripts/presentation_settings.gd");prefs.loaded=true;prefs.ui_scale=1.0;prefs.camera_mode="df"
	root.size=Vector2i(1200,800)
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+60000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	return check(scene._loader.entered,"Main scene did not enter fortress")
func create_models(expected: Dictionary) -> Dictionary:
	var service=scene._ui.actions;service.set_process(false)
	owner=scene._ui.controller("furniture")
	var info: Dictionary=world.inspect_entity(3,int(expected.depot))
	if not check(not info.is_empty(),"Depot is not resident"):return {}
	var tile: Vector3i=info.tile
	scene._ui.focus_tile(tile)
	var camera=scene.camera_rig.get_node("Camera3D")
	var point:=Vector2.ZERO
	var hit: Dictionary={}
	var pick_deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<pick_deadline:
		world.poll();await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if hit.get("id",-1)==int(expected.depot):break
	if not check(hit.get("id",-1)==int(expected.depot),"Map ray did not hit the depot"):return {}
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	var deadline:=Time.get_ticks_msec()+10000
	var chose_depot:=false
	while Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01)
		var selection=scene._ui.tile_selection
		if not chose_depot and selection!=null and selection.navigation.state.phase==selection.navigation.state.Phase.Ready:
			var alternatives: Array=selection.navigation.state.snapshot.get("alternatives",[])
			for index in alternatives.size():
				if alternatives[index].kind==C.SelectionKind.Building and alternatives[index].id==int(expected.depot):
					point=selection.tabs.get_global_transform_with_canvas()*Vector2(24,index*36+18)
					for pressed in [true,false]:
						var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
					chose_depot=true;break
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready:break
		await create_timer(0.01).timeout
	if not check(owner.panel.visible and scene._ui.host.active==owner and owner.state.phase==owner.state.Phase.Ready,"Depot did not own the main scene panel: "+str(owner.state.phase)+" selection="+str(scene._ui.tile_selection.navigation.state.snapshot if scene._ui.tile_selection!=null else {})):return {}
	if not check(scene._ui.tile_selection!=null and scene._ui.tile_selection.navigation.owner.get_ref()==owner,"Map selection did not hand off to depot"):return {}
	owner.trade.limits.assign([64,64])
	point=owner.panel.get_global_transform_with_canvas()*Vector2(64,144)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	return {"service":service,"model":owner.trade}
func configure_view(_model) -> bool:
	view=owner.trade_view
	check(scene._ui.tile_selection.navigation.state.snapshot.is_empty() and not scene._ui.tile_selection.tabs.visible,"Trade retained depot selection tabs")
	return check(owner.trade_mode and view.visible and not owner.panel.visible and scene._ui.host.active==owner,"Trade lost main scene ownership")
func capture_state(label: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-main-scene-"+label+".png")
	var reference: String=directory+"/depot-trade-counteroffer.png" if label=="counter" else OS.get_environment("DF3D_COUNTER_ACCEPTED_NATIVE")
	var native:=Image.load_from_file(reference);native.convert(Image.FORMAT_RGBA8)
	var rect:=Rect2i(32,52,944,708)
	check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Main-scene Trade pixels differ: "+label)
	if label=="counter" and OS.get_environment("DF3D_DEPOT_TRADE_RESIZE")=="1":
		for label_size in ["minimum","small","wide","default"]:
			var reference_image:=Image.load_from_file(directory+"/depot-trade-resize-"+label_size+".png")
			var extent:=reference_image.get_size()
			var sample: Array=[label_size,extent,int(extent.x/8)-48]
			root.size=extent;await process_frame;await process_frame
			var deadline:=Time.get_ticks_msec()+10000
			while Time.get_ticks_msec()<deadline:
				world.poll();scene._ui.actions.poll(0.01)
				if owner.trade.goods_ready() and owner.trade.header.get("columns",0)==sample[2] and not owner.trade.appearance_pending():break
				await create_timer(0.01).timeout
			check(owner.trade.goods_ready() and owner.trade.header.get("columns",0)==sample[2],"Trade resize did not settle: "+sample[0])
			await RenderingServer.frame_post_draw
			rendered=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8);rendered.save_png(directory+"/trade-main-resize-"+sample[0]+".png")
			native=Image.load_from_file(directory+"/depot-trade-resize-"+sample[0]+".png");native.convert(Image.FORMAT_RGBA8)
			rect=Rect2i(Vector2i(view.frame.position),Vector2i(view.frame.size))
			check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Main-scene Trade resize pixels differ: "+sample[0])
func retire_view() -> void:pass
func close_model(_model) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true;root.push_input(event,true)
	check(scene._ui.host.active==null and not owner.trade_mode and not owner.trade_view.visible and owner.state.building_id<0,"Escape retained main-scene Trade ownership")
func dispose_models(_service,_model) -> void:scene.queue_free()
func surface() -> String:return "actual map click to depot to counteroffer to acceptance"
