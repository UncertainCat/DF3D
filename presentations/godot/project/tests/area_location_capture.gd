extends SceneTree
# GPU layout evidence using recorded native catalogs; not live pointer acceptance.
func _initialize() -> void:
	call_deferred("run")

func pointer_motion(point: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new(); event.position = point; event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event,true)

func pointer_button(point: Vector2, button: int, pressed: bool, shift := false) -> void:
	var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
	event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(event,true)

func routed_scroll(view, observations: Array) -> bool:
	var bar = view.catalog_view.native_scroll
	var kind: String = "temple" if view.state.catalog_kind == 2 else "guild"
	for observation in observations:
		if observation.kind != kind or str(observation.label).begins_with("STANDARDSCROLL"): continue
		bar.move_to(int(observation.start))
		var point := Vector2(680,float(observation.y))
		var button := MOUSE_BUTTON_LEFT
		var shift := false
		if str(observation.label).begins_with("CONTEXT_SCROLL"):
			button = MOUSE_BUTTON_WHEEL_UP if str(observation.label).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
			shift = "PAGE" in str(observation.label)
		if observation.label == "drag-from-top":
			var start := Vector2(680,142 if kind == "temple" else 136)
			pointer_motion(start); pointer_button(start,MOUSE_BUTTON_LEFT,true)
			pointer_motion(point,true); pointer_button(point,MOUSE_BUTTON_LEFT,false)
		else:
			pointer_motion(point); pointer_button(point,button,true,shift); pointer_button(point,button,false,shift)
		if bar.first != int(observation.after) or bar.dragging:
			push_error("Viewport-routed native scroll differs: %s actual=%d dragging=%s" % [str(observation),bar.first,bar.dragging]); return false
	# Rows must receive the same native wheel increments without also letting the
	# ScrollContainer apply its default pixel-based wheel movement.
	for shift in [false,true]:
		for button in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			bar.move_to(20); var point := Vector2(450,280)
			pointer_motion(point); pointer_button(point,button,true,shift); pointer_button(point,button,false,shift)
			var expected := 20+(-1 if button == MOUSE_BUTTON_WHEEL_UP else 1)*(10 if shift else 1)
			if bar.first != expected or view.catalog_view.scroll.scroll_vertical != expected*36:
				push_error("Wheel over selector row did not preserve native row alignment"); return false
	# A release outside the scrollbar must finish the drag; subsequent movement
	# cannot keep scrolling, nor may a hidden selector retain drag capture.
	bar.move_to(0); pointer_motion(Vector2(680,130)); pointer_button(Vector2(680,130),MOUSE_BUTTON_LEFT,true)
	pointer_motion(Vector2(900,280),true); pointer_button(Vector2(900,280),MOUSE_BUTTON_LEFT,false)
	var released: int = bar.first
	pointer_motion(Vector2(900,400))
	if bar.dragging or bar.first != released: push_error("Scrollbar retained released drag"); return false
	bar.move_to(0); pointer_motion(Vector2(680,130)); pointer_button(Vector2(680,130),MOUSE_BUTTON_LEFT,true)
	view.hide(); pointer_button(Vector2(900,280),MOUSE_BUTTON_LEFT,false); view.show()
	if bar.dragging: push_error("Hidden selector retained drag capture"); return false
	pointer_motion(Vector2(1000,700))
	return true

func list_rows(count: int) -> Array:
	var rows: Array=[]
	for i in count: rows.append({"id":100+i,"location_kind":3,"name":"Fixture %03d" % i,"religion":""})
	return rows

func existing_list(view, state, reference: Dictionary, atlas: Image, requests: Array) -> bool:
	state.clear();requests.clear()
	var bar = view.native_scroll
	for assigned in [false,true]:
		state.area={"id":23,"kind":1,"revision":17,"location_id":999 if assigned else -1}
		state.rows=list_rows(50);state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		for row in reference.input:
			if row.assigned != assigned: continue
			bar.move_to(int(row.start))
			if str(row.label).begins_with("STANDARDSCROLL"):
				var event:=InputEventKey.new();event.pressed=true
				event.keycode={"STANDARDSCROLL_UP":KEY_UP,"STANDARDSCROLL_DOWN":KEY_DOWN,"STANDARDSCROLL_PAGEUP":KEY_PAGEUP,"STANDARDSCROLL_PAGEDOWN":KEY_PAGEDOWN}[row.label]
				root.push_input(event,true);event.pressed=false;root.push_input(event,true)
			else:
				var point:=Vector2(680,float(row.y))
				if row.label=="drag":
					var start:=Vector2(680,float(row.top)+18)
					pointer_motion(start);pointer_button(start,MOUSE_BUTTON_LEFT,true)
					pointer_motion(point,true);pointer_button(point,MOUSE_BUTTON_LEFT,false)
				else:
					var button:=MOUSE_BUTTON_LEFT
					var shift:=false
					if str(row.label).begins_with("CONTEXT_SCROLL"):
						button=MOUSE_BUTTON_WHEEL_UP if str(row.label).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
						shift="PAGE" in str(row.label)
					pointer_motion(point);pointer_button(point,button,true,shift);pointer_button(point,button,false,shift)
			if bar.first!=int(row.after) or bar.dragging or view.scroll.scroll_vertical!=int(row.after)*36:
				push_error("Existing-list native input differs: %s actual=%d scroll=%d" % [row,bar.first,view.scroll.scroll_vertical]);return false
		for shift in [false,true]:
			bar.move_to(20)
			var point:=Vector2(450,300)
			pointer_motion(point);pointer_button(point,MOUSE_BUTTON_WHEEL_DOWN,true,shift);pointer_button(point,MOUSE_BUTTON_WHEEL_DOWN,false,shift)
			if bar.first!=20+(bar.page if shift else 1):push_error("Row wheel does not follow native page size");return false
		if not requests.is_empty():push_error("List scrolling activated a location");return false
		bar.move_to(20)
		await process_frame;await RenderingServer.frame_post_draw
		pointer_motion(Vector2(450,float(bar.global_position.y)+18));pointer_button(Vector2(450,float(bar.global_position.y)+18),MOUSE_BUTTON_LEFT,true);pointer_button(Vector2(450,float(bar.global_position.y)+18),MOUSE_BUTTON_LEFT,false)
		if requests.size()!=1 or int(requests[0].get("location_id",-1))!=120 or int(requests[0].get("expected_revision",0))!=17:
			push_error("Scrolled existing row lost observed identity/revision");return false
		state.mutating=false;requests.clear();state.changed.emit()
	for row in reference.art:
		state.area={"id":23,"kind":1,"revision":17,"location_id":999 if row.assigned else -1}
		state.rows=list_rows(int(row.count));state.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		if bar.visible!=(int(row.count)>int(row.page)) or view.scroll.size.x!=(296 if bar.visible else 312):
			push_error("Native list scrollbar visibility/row width differs");return false
		if not bar.visible:continue
		bar.move_to(int(row.first));bar.hover_cell=floori(float(row.hover)/12) if int(row.hover)>=0 else -1;bar.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image()
		var origin:=int(reference.anchor)-13*64
		for y in int(row.height)/12:
			for column in 2:
				var tile:=int(row.tiles[y].left if column==0 else row.tiles[y].right)-origin
				for py in 12:
					for px in 8:
						if rendered.get_pixel(672+column*8+px,int(row.top)+y*12+py)!=atlas.get_pixel((tile%64)*8+px,(tile/64)*12+py):
							push_error("Existing-list scrollbar pixels differ: count=%d page=%d first=%d hover=%d cell=%d" % [row.count,row.page,row.first,row.hover,y]);return false
	return true

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(77); return
	var reference := OS.get_environment("DF3D_LOCATION_REFERENCE")
	if reference.is_empty(): push_error("Missing recorded native location reference"); quit(1); return
	for required in ["location-transport-comparison.json", "native-location-metadata.json", "native-location-scroll.json", "native-location-scroll-art.json", "native-location-scroll-states.json", "native-list-scroll.json", "provenance.txt"]:
		if not FileAccess.file_exists(reference.path_join(required)): quit(77); return
	var catalogs: Array = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("location-transport-comparison.json")))
	var native_rows: Array = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("native-location-metadata.json")))
	var native_scroll: Array = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("native-location-scroll.json")))
	var native_art: Array = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("native-location-scroll-art.json")))
	var native_states: Array = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("native-location-scroll-states.json")))
	var atlas := Image.load_from_file(OS.get_environment("DF3D_DF_PATH").path_join("data/vanilla/vanilla_interface/graphics/images/interface_bits.png"))
	var directory := ProjectSettings.globalize_path("res://../../../build/qa/location-render")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1200,800)
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	var state = preload("res://scripts/area_locations_state.gd").new()
	var view = preload("res://scripts/area_locations_view.gd").new()
	var requests: Array = []; state.request_ready.connect(func(request): requests.append(request))
	var back_count := [0]; view.done.connect(func(): back_count[0] += 1)
	root.add_child(view); view.configure(assets,state)
	view.add_theme_stylebox_override("panel",view.panel_style())
	view.position = Vector2(368,52); view.size = Vector2(328,420)
	for catalog in catalogs:
		state.area = {"id":1,"kind":1,"revision":1}
		state.catalog_kind = int(catalog.kind)
		state.catalog_rows = catalog.religions if state.catalog_kind == 2 else catalog.guilds
		state.catalog_revision = int(catalog.revision); state.changed.emit()
		await process_frame; await RenderingServer.frame_post_draw
		await process_frame; await RenderingServer.frame_post_draw
		for layout_frame in 8:
			if view.catalog_view.scroll.get_v_scroll_bar().max_value == state.catalog_rows.size()*36: break
			await process_frame; await RenderingServer.frame_post_draw
		var bar = view.catalog_view.native_scroll
		if not routed_scroll(view,native_scroll): quit(1); return
		if not requests.is_empty(): push_error("Scrolling unexpectedly activated a location choice"); quit(1); return
		for observation in native_scroll:
			if observation.kind != ("temple" if state.catalog_kind == 2 else "guild"): continue
			bar.move_to(int(observation.start))
			var event := InputEventMouseButton.new(); event.pressed = true
			event.button_index = MOUSE_BUTTON_LEFT; event.position = Vector2(8,float(observation.y)-100)
			if str(observation.label).begins_with("CONTEXT_SCROLL"):
				event.button_index = MOUSE_BUTTON_WHEEL_UP if str(observation.label).ends_with("UP") else MOUSE_BUTTON_WHEEL_DOWN
				event.shift_pressed = "PAGE" in str(observation.label)
			elif str(observation.label).begins_with("STANDARDSCROLL"):
				bar._gui_input(InputEventKey.new())
				if bar.first != int(observation.after): push_error("Standard scroll changed native selector position"); quit(1); return
				continue
			if observation.label == "drag-from-top":
				event.position.y = 42 if state.catalog_kind == 2 else 36; bar._gui_input(event)
				var motion := InputEventMouseMotion.new(); motion.position = bar.global_position+Vector2(8,float(observation.y)-100)
				bar._input(motion); event.pressed = false; bar._input(event)
			else: bar._gui_input(event)
			event.pressed = false; bar._input(event)
			if bar.first != int(observation.after):
				push_error("Native scrolling differs: %s actual=%d count=%d scroll=%d max=%f page=%f" % [str(observation),bar.first,bar.count,view.catalog_view.scroll.scroll_vertical,view.catalog_view.scroll.get_v_scroll_bar().max_value,view.catalog_view.scroll.get_v_scroll_bar().page]); quit(1); return
		# Native texpos IDs index this installed 64-column 8x12 atlas. Anchor at
		# the captured up-arrow (raw INTERFACE_BITS 0,13), never ship game pixels.
		for observation in native_art:
			if observation.kind != ("temple" if state.catalog_kind == 2 else "guild"): continue
			bar.move_to(int(observation.first)); bar.hover_cell = -1; bar.queue_redraw()
			await process_frame; await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			var origin := int(observation.tiles[0].left)-13*64
			for row in 30:
				for column in 2:
					var tile := int(observation.tiles[row].left if column == 0 else observation.tiles[row].right)-origin
					for y in 12:
						for x in 8:
							var expected := atlas.get_pixel((tile%64)*8+x,(tile/64)*12+y)
							if rendered.get_pixel(672+column*8+x,100+row*12+y) != expected:
								push_error("Native scrollbar pixels differ kind=%d first=%d cell=%d,%d" % [state.catalog_kind,int(observation.first),column,row]); quit(1); return
		var baseline_rows: Array = state.catalog_rows
		for observation in native_states:
			if observation.kind != ("temple" if state.catalog_kind == 2 else "guild"): continue
			var resized: Array = []
			for i in int(observation.count): resized.append(baseline_rows[i%baseline_rows.size()])
			state.catalog_rows = resized; state.changed.emit()
			await process_frame; await RenderingServer.frame_post_draw
			await process_frame; await RenderingServer.frame_post_draw
			bar.move_to(int(observation.first))
			bar.hover_cell = floori((float(observation.hover_y)-100)/12); bar.queue_redraw()
			await process_frame; await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			var origin := int(observation.anchor)-13*64
			for row in 30:
				for column in 2:
					var tile := int(observation.tiles[row].left if column == 0 else observation.tiles[row].right)-origin
					for y in 12:
						for x in 8:
							var expected := atlas.get_pixel((tile%64)*8+x,(tile/64)*12+y)
							if rendered.get_pixel(672+column*8+x,100+row*12+y) != expected:
								push_error("Native scrollbar state differs kind=%d count=%d first=%d hover=%d pressed=%s cell=%d,%d" % [state.catalog_kind,int(observation.count),int(observation.first),int(observation.hover_y),observation.pressed,column,row]); quit(1); return
		state.catalog_rows = baseline_rows; state.changed.emit()
		await process_frame; await RenderingServer.frame_post_draw
		await process_frame; await RenderingServer.frame_post_draw
		for capture in native_rows:
			if capture.kind != ("temple" if state.catalog_kind == 2 else "guild"): continue
			var i := int(capture.index)
			var first := mini(i,state.catalog_rows.size()-10)
			var native_title := str(capture.screen).split("\n")[4+3*(i-first)].substr(0,43).strip_edges()
			if view.catalog_view.choices[i].get_node("Name").text != native_title:
				push_error("Native row caption differs kind=%d index=%d" % [state.catalog_kind,i]); quit(1); return
		var indices: Array[int] = [0]
		for index in state.catalog_rows.size():
			var row: Dictionary = state.catalog_rows[index]
			if (state.catalog_kind == 2 and int(row.kind) == 3) or (state.catalog_kind == 4 and int(row.guild_id) >= 0):
				indices.append(index); break
		for index in indices:
			await process_frame; await RenderingServer.frame_post_draw
			view.catalog_view.native_scroll.move_to(maxi(0,index-9))
			view.catalog_view.choices[index].mouse_entered.emit()
			await process_frame; await RenderingServer.frame_post_draw
			var file := "kind_%d_row_%d.png" % [state.catalog_kind,index]
			if root.get_texture().get_image().save_png(directory.path_join(file)) != OK: quit(1); return
		bar.move_to(20)
		await process_frame; await RenderingServer.frame_post_draw
		await process_frame; await RenderingServer.frame_post_draw
		pointer_motion(Vector2(450,118))
		pointer_button(Vector2(450,118),MOUSE_BUTTON_LEFT,true)
		pointer_button(Vector2(450,118),MOUSE_BUTTON_LEFT,false)
		if requests.size() != 1: push_error("Scrolled row click did not produce exactly one choice request"); quit(1); return
		var request: Dictionary = requests[0]
		var chosen: Dictionary = state.catalog_rows[20]
		if int(request.get("location_kind",0)) != state.catalog_kind or int(request.get("expected_revision",0)) != 1:
			push_error("Scrolled row click lost location kind or area revision"); quit(1); return
		if state.catalog_kind == 2 and (int(request.deity_kind) != int(chosen.kind) or int(request.deity_id) != int(chosen.id)):
			push_error("Scrolled Temple row sent a different practice identity"); quit(1); return
		if state.catalog_kind == 4 and int(request.profession) != int(chosen.profession):
			push_error("Scrolled Guild row sent a different profession"); quit(1); return
		state.mutating = false; state.changed.emit()
		var previous_back: int = back_count[0]
		pointer_motion(Vector2(640,82)); pointer_button(Vector2(640,82),MOUSE_BUTTON_LEFT,true); pointer_button(Vector2(640,82),MOUSE_BUTTON_LEFT,false)
		if back_count[0] != previous_back+1 or requests.size() != 1:
			push_error("Routed Back failed or emitted a mutation"); quit(1); return
		requests.clear(); pointer_motion(Vector2(1000,700))
	if not await existing_list(view,state,JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("native-list-scroll.json"))),atlas,requests): quit(1);return
	view.free(); assets.free(); await process_frame
	print("AREA_LOCATION_CAPTURE_PASS")
	quit()
