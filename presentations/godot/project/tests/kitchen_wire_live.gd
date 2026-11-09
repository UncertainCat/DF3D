extends "res://tests/item_carrier_wire_live.gd"
const State=preload("res://scripts/kitchen_state.gd")
class Interaction extends Node:
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=true
	var panel:=Control.new()
	func _ready() -> void:add_child(panel)
	func cancel_selection() -> void:pass
	func set_play_enabled(_value: bool) -> void:pass
func pointer(view,point: Vector2,shift: bool=false) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.shift_pressed=shift
	event.position=view.get_global_transform_with_canvas()*point;event.global_position=event.position
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while state.phase in [State.Phase.Reading,State.Phase.Applying] and Time.get_ticks_msec()<deadline:
		world.poll();await create_timer(0.01).timeout
	return check(state.phase==State.Phase.Ready,"Kitchen controller failed to obtain fresh authority")

func run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var rendered: bool=OS.get_environment("DF3D_KITCHEN_RENDER")=="1"
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Kitchen attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state:=State.new();var owner;var host
	if rendered:
		if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Kitchen assets unavailable"):quit(1);return
		var interaction:=Interaction.new();root.add_child(interaction)
		host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
		owner=preload("res://scripts/standing_orders_panel.gd").new();root.add_child(owner);owner.configure(world,service,host);owner.open_panel()
		await pointer(owner.panel,owner.panel.kitchen_rect().get_center());state=owner.kitchen_state
		check(owner.kitchen_active and host.active==owner,"Kitchen tab handoff failed")
	else:state.configure(service);state.open()
	if not await ready_state(state):quit(1);return
	var value: Dictionary={"rows":state.rows,"exclusions":state.exclusions}
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/kitchen-native.json"))
	check(value.rows.size()==reference.known.size(),"Kitchen aggregate count differs")
	for row in value.rows:
		var matched:=false
		for native in reference.known:
			var key: Dictionary=row.receipt.key
			if key.item_type==int(native.type) and key.item_subtype==int(native.subtype) and key.mat_type==int(native.mat) and key.mat_index==int(native.matg):
				matched=true;check(row.name==native.name and row.receipt.count==int(native.count) and row.receipt.capabilities==int(native.capabilities),"Kitchen native aggregate differs")
		check(matched,"Kitchen row identity missing")
	var sort_checks:=0
	if FileAccess.file_exists(directory+"/kitchen-sort.json"):
		var sort_reference: Array=JSON.parse_string(FileAccess.get_file_as_string(directory+"/kitchen-sort.json"))
		var columns: Dictionary={"Type":0,"Name":1,"Number":2,"Cook":3,"Brew":4}
		for observation in sort_reference:
			if not str(observation.label).begins_with("controlled-bit1-"):continue
			var query: Dictionary={"type_filter":-1,"capability_filter":0,"query":"","sorts":[]}
			for priority in observation.sorts:query.sorts.append({"column":columns[priority.name],"reverse":bool(observation.directions[priority.name])})
			state.set_query(query)
			if not await ready_state(state):quit(1);return
			var names: Array=[]
			for row in state.rows:names.append(row.name)
			check(names==observation.names,"Kitchen repeated-priority wire order differs: "+str(observation.label));sort_checks+=1
		state.set_query({"type_filter":-1,"capability_filter":0,"query":"","sorts":[{"column":0,"reverse":false}]})
		if not await ready_state(state):quit(1);return
		value={"rows":state.rows,"exclusions":state.exclusions}
	if rendered:
		await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/kitchen-view-root.png")
		# Native seven-priority capture starts with reverse Type, then cumulative
		# Name, Number, Name, Cook, Brew, Name clicks.
		await pointer(owner.kitchen_panel,Vector2(100,owner.kitchen_panel.list_top()+18))
		if not await ready_state(state):quit(1);return
		for x in [180,600,180,696,728,180]:
			await pointer(owner.kitchen_panel,Vector2(x,owner.kitchen_panel.list_top()+18),true)
			if not await ready_state(state):quit(1);return
		check(state.query.sorts.size()==7,"Shift clicks failed to retain seven priorities")
		await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/kitchen-view-seven-priorities.png")
		await pointer(owner.kitchen_panel,Vector2(100,owner.kitchen_panel.list_top()+18))
		if not await ready_state(state):quit(1);return
		await pointer(owner.kitchen_panel.search,Vector2(40,18))
		for code in "plump".length():
			var event:=InputEventKey.new();event.pressed=true;event.unicode="plump".unicode_at(code);Input.parse_input_event(event);await process_frame
		if not await ready_state(state):quit(1);return
		check(state.query.query=="plump" and state.rows.size()==2,"Kitchen pointer search failed")
		value={"rows":state.rows,"exclusions":state.exclusions}
	var edits: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/kitchen-edits.json"))
	var completed:=0
	for step in edits.steps:
		if failed:break
		var target: Dictionary={}
		var index: int=-1
		for i in value.rows.size():
			if value.rows[i].name==step.name:target=value.rows[i].receipt;index=i
		if not check(not target.is_empty(),"Kitchen target missing"):break
		var intent: Dictionary={"action":C.ManagementAction.KitchenApply,"target":target,"permission":int(step.flag),"expected":value.exclusions}
		if rendered:
			if OS.get_environment("DF3D_KITCHEN_KEYS")=="1":
				await pointer(owner.kitchen_panel,Vector2(160,owner.kitchen_panel.rows_top()+index*36+18))
				var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_C if int(step.flag)==1 else KEY_B
				Input.parse_input_event(key);await process_frame
			else:await pointer(owner.kitchen_panel,Vector2(696+(int(step.flag)-1)*32,owner.kitchen_panel.rows_top()+index*36+18))
		else:
			state.toggle(index,int(step.flag));check(state.phase==State.Phase.Applying and state.rows.is_empty(),"Kitchen edit retained authority")
		if not await ready_state(state):break
		if completed==0:
			var stale:=await request("kitchen_menu",intent)
			check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("kitchen_menu",{}).get("outcome")==C.KitchenMenuOutcome.Stale,"Kitchen stale receipt accepted")
		completed+=1
		var f:=FileAccess.open(directory+"/kitchen-wire-step",FileAccess.WRITE);f.store_string(str(completed));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/kitchen-wire-ack") and FileAccess.get_file_as_string(directory+"/kitchen-wire-ack").strip_edges()==str(completed):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/kitchen-wire-ack").strip_edges()==str(completed),"Kitchen independent effects not acknowledged")
		value={"rows":state.rows,"exclusions":state.exclusions}
	check(completed==6,"Kitchen effects incomplete")
	if rendered:
		await pointer(owner.kitchen_panel,Vector2(200,owner.kitchen_panel.list_top()-48))
		check(not owner.kitchen_active and host.active==owner,"Kitchen return tab failed")
		owner.close_panel();check(host.active==null,"Labor close retained input")
	var output:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"success":not failed,"steps":completed,"sort_checks":sort_checks}));output.close()
	state.dispose()
	quit(1 if failed else 0)
