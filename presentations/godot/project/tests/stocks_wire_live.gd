extends "res://tests/item_carrier_wire_live.gd"
class Host extends Node:
	var active
	func register(owner) -> void:owner.ui_host=self
	func activate(owner) -> bool:
		if is_instance_valid(active) and active!=owner:active.close_panel()
		active=owner;return true
	func release(owner) -> void:
		if active==owner:active=null
	func allows_panel_input(owner) -> bool:return active==owner
const State=preload("res://scripts/stocks_state.gd")
func ready_state(state) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	var settled:=0
	while Time.get_ticks_msec()<deadline and settled<2:
		world.poll();await process_frame
		if state.phase==State.Phase.Ready:settled+=1
		elif state.phase in [State.Phase.Reading,State.Phase.Applying]:settled=0
		else:break
	return check(state.phase==State.Phase.Ready,"Stocks controller did not obtain fresh authority")
func click(point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=point;event.global_position=point
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func wheel(point: Vector2,up:=false,page:=false) -> void:
	var event:=InputEventMouseButton.new();event.pressed=true;event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN;event.shift_pressed=page
	Input.parse_input_event(event);await process_frame
func read_stocks(category: int,query: String="",ids: Array=[]) -> Dictionary:
	var reply:=await request("stocks_menu",{"action":C.ManagementAction.StocksMenuRead,"category":category,"query":query,"item_ids":ids})
	check(reply.get("status")==C.ManagementStatus.Ok,"Stocks read failed")
	return reply.get("stocks_menu",{})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stocks-wire-reference.json"))
	reference.matches=reference.matches.map(func(id):return int(id))
	for group in reference.selection.groups:group.ids=group.ids.map(func(id):return int(id))
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Stocks attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var value:=await read_stocks(-1,"iron")
	if not check(value.get("categories",[]).size()==93,"Stocks catalog missing"):quit(1);return
	for i in 93:
		var row: Dictionary=value.categories[i];var type: int=int(reference.order[i])
		check(row.type==type and row.matches==reference.matches.has(type),"Stocks category order/filter differs")
		var native: Dictionary=reference.display[type]
		for key in ["caption","stored","unavailable"]:check(row[key]==native[key],"Stocks category caption differs")
	var ids: Array=reference.selection.groups[0].ids
	value=await read_stocks(39,"",ids)
	if not check(value.get("groups",[]).size()==reference.selection.groups.size(),"Stocks groups missing"):quit(1);return
	for i in value.groups.size():
		var row: Dictionary=value.groups[i];var native: Dictionary=reference.selection.groups[i]
		for key in ["subtype","subcat1","subcat2","amount","caption","flags","expanded"]:check(row[key]==native[key],"Stocks group differs: "+key)
		check(str(row.revision)==native.revision and row.item_ids==native.ids and row.matches==native.on,"Stocks group membership/revision differs")
	check(value.items.size()==ids.size(),"Stocks visible items missing")
	for i in ids.size():check(value.items[i].id==int(ids[i]) and not value.items[i].caption.is_empty(),"Stocks item row differs")
	for row in value.items:
		var native: Dictionary=reference.appearance[str(row.id)]
		check(row.has("appearance") and row.appearance.stack==int(native.stack) and row.appearance.flags==int(native.flags),"Stocks appearance facts differ from native item")
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	for frame in 5:world.poll();await process_frame
	var state:=State.new();state.configure(service);state.open()
	if not await ready_state(state):quit(1);return
	check(state.category==39,"Stocks controller initial category differs")
	var view;var hover
	if OS.get_environment("DF3D_STOCKS_RENDER")=="1":
		root.size=Vector2i(1200,800)
		if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Stocks assets unavailable"):quit(1);return
		hover=preload("res://scripts/native_hover_view.gd").new();hover.configure(world);hover.layout(Vector2(1200,800))
		view=preload("res://scripts/stocks_view.gd").new();root.add_child(view);view.configure_stocks(world,state,hover);view.layout(Vector2(1200,800));root.add_child(hover)
		await process_frame
		if not await ready_state(state):quit(1);return
		await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/stocks-view-root.png")
		var visible: Array=[]
		for row in view.page:
			if row.has("id"):visible.append(row.id)
		check(visible.all(func(id):return state.items.has(id)),"Stocks visible facts did not settle")
		check(visible.all(func(id):return view.icons.has(id) and view.icons[id].texture!=null),"Stocks Ammunition artwork missing")
		if OS.get_environment("DF3D_STOCKS_HOVER_RENDER")=="1":
			var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_stocks.json"))
			for target in fixture.hover_reference.observations:
				var motion:=InputEventMouseMotion.new();motion.position=Vector2(target.x,target.y);motion.global_position=motion.position
				Input.parse_input_event(motion);await create_timer(0.65).timeout
				var kind: String=str(target.kind).trim_prefix("group-")
				var expected: String=("stocks_" if kind in ["recenter","view"] else "item_")+kind
				check(hover.displayed==expected,"Stocks hover did not activate: "+str(target.kind))
				var lines: Array=hover.STOCKS_HELP[kind] if kind in ["recenter","view"] else hover.ITEM_HELP[kind]
				check(lines==target.lines,"Stocks hover text differs from native cells")
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/stocks-view-help-"+str(target.kind)+".png")
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(500,130);motion.global_position=motion.position
			Input.parse_input_event(motion);await process_frame;await process_frame
			check(view.pointer_position==Vector2(468,78),"Stocks header motion was not delivered")
			check(hover.displayed.is_empty(),"Stocks header retained unrelated hover")
		if OS.get_environment("DF3D_STOCKS_SCROLL_RENDER")=="1":
			await wheel(Vector2(100,130))
			await wheel(Vector2(500,94),false,true)
			if not await ready_state(state):quit(1);return
			check(state.first_category==1 and state.first_item==51,"Rendered wheel offsets differ from native")
			var scrolled_ids: Array=[]
			for row in view.page:
				if row.has("id"):scrolled_ids.append(row.id)
			check(not scrolled_ids.is_empty() and scrolled_ids.all(func(id):return state.items.has(id)),"Scrolling left visible rows without fresh facts")
			check(scrolled_ids.all(func(id):return view.icons.has(id) and view.icons[id].texture!=null),"Scrolling lost ammunition artwork")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/stocks-view-scroll.png")
			await wheel(Vector2(100,130),true)
			await wheel(Vector2(500,94),true,true)
			if not await ready_state(state):quit(1);return
			check(state.first_category==0 and state.first_item==0,"Rendered wheel did not return to initial page")
		if OS.get_environment("DF3D_STOCKS_FILTER_RENDER")=="1":
			await click(Vector2(500,94))
			for byte in [105,114,111,110]:
				var key:=InputEventKey.new();key.pressed=true;key.unicode=byte;key.keycode=byte-32;Input.parse_input_event(key);await process_frame
			if not await ready_state(state):quit(1);return
			var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER;Input.parse_input_event(enter);await process_frame
			check(state.query=="IRON" and not view.search.has_focus() and state.category==39,"Rendered filter text/focus differs")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/stocks-view-filter.png")
			for point in [Vector2(500,94),Vector2(946,94)]:
				var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion)
				await create_timer(0.65).timeout;check(hover.displayed.is_empty(),"Stocks filter invented a native tooltip")
			await click(Vector2(500,94))
			for _byte in 4:
				var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_BACKSPACE;Input.parse_input_event(key);await process_frame
			if not await ready_state(state):quit(1);return
			Input.parse_input_event(enter);await process_frame
			check(state.query.is_empty() and not view.search.has_focus(),"Filter clearing did not restore initial query")
		if OS.get_environment("DF3D_STOCKS_RESIZE_RENDER")=="1":
			for dimensions in [Vector2i(961,721),Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]:
				root.size=dimensions;await process_frame
				view.layout(Vector2(dimensions));hover.layout(Vector2(dimensions))
				if not await ready_state(state):quit(1);return
				check(view.page.all(func(row):return row.has("group") or state.items.has(row.id)),"Resize left visible item facts missing")
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/stocks-view-resize-%dx%d.png"%[dimensions.x,dimensions.y])
		if OS.get_environment("DF3D_STOCKS_ART_RENDER")=="1":
			for kind in ([24,25,26,27,28,29,60] if OS.get_environment("DF3D_STOCKS_EQUIPMENT_ART")=="1" else [0,2,4,5,30,32]):
				state.select_category(kind)
				if not await ready_state(state):quit(1);return
				var visible_ids: Array=[]
				for row in view.page:
					if row.has("id"):visible_ids.append(row.id)
				check(not visible_ids.is_empty() and visible_ids.all(func(id):return state.items.has(id) and view.icons.has(id) and view.icons[id].texture!=null),"Stocks category artwork unavailable: "+str(kind))
				if kind==32:check(visible_ids.all(func(id):return state.items[id].appearance.has("contents")),"Stocks bin contents were dropped before rendering")
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/stocks-view-art-"+str(kind)+".png")
			state.select_category(39)
			if not await ready_state(state):quit(1);return
		var expanded_count: int=view.total_rows
		await click(Vector2(500,130))
		if not await ready_state(state):quit(1);return
		check(not state.expanded(state.groups[0]) and view.total_rows==expanded_count-ids.size(),"Stocks header click did not collapse members")
		await click(Vector2(500,130))
		if not await ready_state(state):quit(1);return
		check(state.expanded(state.groups[0]) and view.total_rows==expanded_count,"Stocks header click did not restore members")
	for step in [1,2]:
		if failed:break
		var group: Dictionary=state.groups[0]
		var desired: bool=not reference.original_hidden if step==1 else reference.original_hidden
		var intent: Dictionary={"action":C.ManagementAction.StocksGroupApply,"category":39,"subtype":group.subtype,"subcat1":group.subcat1,"subcat2":group.subcat2,"expected_revision":group.revision,"operation":C.StocksFlagAction.Hidden,"value":int(desired)}
		if reference.get("individual",false):intent.action=C.ManagementAction.StocksItemApply;intent.item_id=int(ids[0])
		if view!=null:await click(Vector2(916,166 if reference.get("individual",false) else 130))
		else:
			if reference.get("individual",false):state.apply_item(int(ids[0]),C.StocksFlagAction.Hidden,desired)
			else:state.apply_group(state.key(group),C.StocksFlagAction.Hidden,desired)
			check(state.phase==State.Phase.Applying and state.groups.is_empty(),"Stocks edit retained authority")
		if not await ready_state(state):break
		var stale:=await request("stocks_menu",intent)
		check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("stocks_menu",{}).get("outcome")==C.StocksMenuOutcome.Stale,"Stocks stale replay accepted")
		var f:=FileAccess.open(directory+"/stocks-wire-step",FileAccess.WRITE);f.store_string(str(step));f.close()
		deadline=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<deadline:
			if FileAccess.file_exists(directory+"/stocks-wire-ack") and FileAccess.get_file_as_string(directory+"/stocks-wire-ack").strip_edges()==str(step):break
			await create_timer(0.01).timeout
		check(FileAccess.get_file_as_string(directory+"/stocks-wire-ack").strip_edges()==str(step),"Stocks effects not independently verified")
	if OS.get_environment("DF3D_STOCKS_OWNER_WIRE")=="1" and not failed:
		if view!=null:view.queue_free();view=null;await process_frame
		state.dispose()
		var host:=Host.new();root.add_child(host)
		var owner=preload("res://scripts/stocks_panel.gd").new();root.add_child(owner);owner.configure(world,service,host,hover)
		var focused: Array=[];owner.focus_requested.connect(func(tile):focused.append(tile))
		var expected:=Vector3i(int(reference.position[0]),int(reference.position[1]),int(reference.position[2]))
		for inspect in [false,true]:
			owner.open_panel();if not await ready_state(owner.state):break
			await click(Vector2(820 if inspect else 796,166))
			deadline=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline and owner.state.phase!=State.Phase.Closed:world.poll();await process_frame
			check(owner.state.phase==State.Phase.Closed and not owner.panel.visible and not focused.is_empty() and focused[-1]==expected,"Stocks destination did not focus native position and close")
			if inspect:
				while Time.get_ticks_msec()<deadline and owner.item_owner.state.phase==owner.item_owner.state.Phase.Reading:world.poll();await process_frame
				check(owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready and owner.item_owner.state.item_id==int(ids[0]),"Stocks View item sheet unavailable")
				check(owner.item_owner.state.snapshot.get("ammunition_assignment",{})=={"kind":1,"squad_id":-1,"caption":"Assigned to hunters"},"Native hunter assignment missing from sheet")
				var bin_contents: Dictionary=owner.item_owner.state.snapshot.carrier.appearance.get("contents",{})
				check(bin_contents.get("container",false) and bin_contents.get("entries",[]).size()==13 and bin_contents.entries[0].color_token=="COPPER","Complete native bin contents missing from sheet")
				var snapshot_file:=FileAccess.open(directory+"/stocks-view-item-snapshot.json",FileAccess.WRITE);snapshot_file.store_string(JSON.stringify(owner.item_owner.state.snapshot));snapshot_file.close()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/stocks-view-item-sheet.png")
				owner.item_owner.close_panel();check(owner.state.phase==State.Phase.Closed,"Item close returned to Stocks")
			else:check(owner.item_owner.state.item_id==-1,"Recenter opened item sheet")
		owner.queue_free();host.queue_free();await process_frame
	var f:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"success":not failed,"categories":93,"groups":reference.selection.groups.size(),"items":ids.size(),"edits":2,"controller":true,"rendered":OS.get_environment("DF3D_STOCKS_RENDER")=="1","owner":OS.get_environment("DF3D_STOCKS_OWNER_WIRE")=="1","individual":reference.get("individual",false)}));f.close()
	if view!=null:view.queue_free()
	if hover!=null:hover.queue_free()
	state.dispose();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)
