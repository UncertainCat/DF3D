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
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func read_stocks(category: int,query: String="",ids: Array=[]) -> Dictionary:
	var reply:=await request("stocks_menu",{"action":C.ManagementAction.StocksMenuRead,"category":category,"query":query,"item_ids":ids})
	check(reply.get("status")==C.ManagementStatus.Ok,"Stocks read failed")
	return reply.get("stocks_menu",{})
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stocks-wire-reference.json"))
	reference.matches=reference.matches.map(func(id):return int(id))
	for group in reference.selection.groups:group.ids=group.ids.map(func(id):return int(id))
	print("STOCKS_STAGE creating_world")
	world=Df3dWorld.new();root.add_child(world)
	print("STOCKS_STAGE world_ready")
	if not check(world.attach(),"Stocks attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	print("STOCKS_STAGE catalog_ready")
	var value:=await read_stocks(-1,"iron")
	if not check(value.get("categories",[]).size()==93,"Stocks catalog missing"):quit(1);return
	for i in 93:
		var row: Dictionary=value.categories[i];var type: int=int(reference.order[i])
		check(row.type==type and row.matches==reference.matches.has(type),"Stocks category order/filter differs")
		var native: Dictionary=reference.display[type]
		for key in ["caption","stored","unavailable"]:check(row[key]==native[key],"Stocks category caption differs")
	print("STOCKS_STAGE categories_ready")
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
	if reference.has("paged"):
		var requested: Array=reference.paged.ids.map(func(id):return int(id))
		var large:=await read_stocks(4,"",requested)
		check(large.get("items",[]).size()==64,"Paged Stocks lost item rows")
		check(large.get("groups",[]).size()==reference.paged.selection.groups.size(),"Paged Stocks lost groups")
		var caption_bytes:=0
		for row in large.get("items",[]):
			check(requested.has(row.id) and row.caption.to_utf8_buffer().size()>=12000,"Paged item caption was truncated")
			caption_bytes+=row.caption.to_utf8_buffer().size()
		check(caption_bytes>512*1024,"Fixture did not exceed mailbox capacity")
		for index in large.get("groups",[]).size():
			var row: Dictionary=large.groups[index];var native: Dictionary=reference.paged.selection.groups[index]
			check(row.caption==native.caption and row.item_ids==native.ids.map(func(id):return int(id)) and str(row.revision)==native.revision,"Paged group snapshot differs from native")
		var evidence:=FileAccess.open(directory+"/stocks-pages-wire-result.json",FileAccess.WRITE)
		evidence.store_string(JSON.stringify({"success":not failed,"item_count":large.get("items",[]).size(),"caption_bytes":caption_bytes,"group_count":large.get("groups",[]).size()}));evidence.close()
	if OS.get_environment("DF3D_STOCKS_CONTENTS_WIRE")=="1":
		var observed: Array=[]
		for expected in reference.contents:
			var response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":int(expected.item_id)})
			var snapshot: Dictionary=response.get("production",{}).get("independent_item",{}).get("snapshot",{})
			if not check(response.get("status")==C.ManagementStatus.Ok and snapshot.has("contents"),"Known native contents missing"):break
			var model=preload("res://scripts/item_sheet_state.gd").new();model.item_id=int(expected.item_id)
			check(model._valid(snapshot),"Controller rejected contents snapshot")
			if not check(snapshot.contents.size()==expected.rows.size(),"Contents count changed across transport"):break
			for index in expected.rows.size():
				var row: Dictionary=snapshot.contents[index];var native: Dictionary=expected.rows[index]
				for key in ["kind","id","caption"]:check(row[key]==native[key],"Contents identity/caption differs: "+key)
				if row.kind==1:
					for key in ["item_type","flags","can_dump","can_melt"]:check(row[key]==native[key],"Contents facts differ: "+key)
					for key in ["material_token","subtype_raw","stack"]:check(row.appearance[key]==native[key],"Contents appearance differs: "+key)
			observed.append(snapshot)
		var saved:=FileAccess.open(directory+"/stocks-contents-wire-result.json",FileAccess.WRITE);saved.store_string(JSON.stringify({"success":not failed,"snapshots":observed}));saved.close()
	print("STOCKS_STAGE items_ready")
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
			var kinds: Array=[24,25,26,27,28,29,60] if OS.get_environment("DF3D_STOCKS_EQUIPMENT_ART")=="1" else [0,2,4,5,30,32]
			if OS.get_environment("DF3D_STOCKS_HOUSEHOLD_ART")=="1":kinds=[6,7,10,11,12,18,22,45]
			if OS.get_environment("DF3D_STOCKS_DOOR_STATES")=="1":kinds=[6]
			for kind in kinds:
				state.select_category(kind)
				if not await ready_state(state):quit(1);return
				var visible_ids: Array=[]
				for row in view.page:
					if row.has("id"):visible_ids.append(row.id)
				check(not visible_ids.is_empty() and visible_ids.all(func(id):return state.items.has(id) and view.icons.has(id) and view.icons[id].texture!=null),"Stocks category artwork unavailable: "+str(kind))
				if kind==6 and OS.get_environment("DF3D_STOCKS_DOOR_STATES")=="1":
					var door_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/stocks-door-states.json"))
					for expected in door_reference.cases:
						var id:=int(expected.id)
						state.first_item=int(expected.row_index)*3;view.refresh()
						if not await ready_state(state):quit(1);return
						check(view.page.any(func(row):return row.get("id",-1)==id),"Controlled door state left visible page")
						var facts: Dictionary=state.items.get(id,{}).get("appearance",{}).get("door",{})
						check(facts.get("open")==expected.open and facts.get("forbidden")==expected.forbidden and facts.get("wear")==int(expected.wear),"Door state lost between simulation and viewer")
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(directory+"/stocks-view-door-state-"+str(id)+".png")
					state.first_item=0;view.refresh()
					if not await ready_state(state):quit(1);return
				if kind==18:check(visible_ids.all(func(id):return state.items[id].appearance.has("bucket_liquid")),"Stocks bucket liquid facts were dropped")
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
	if OS.get_environment("DF3D_STOCKS_FURNITURE_SHEETS")=="1" and not failed:
		if view!=null:view.queue_free();view=null;await process_frame
		state.dispose()
		var host:=Host.new();root.add_child(host)
		var owner=preload("res://scripts/stocks_panel.gd").new();root.add_child(owner)
		if OS.get_environment("DF3D_STOCKS_RENDER")=="1":owner.configure(world,service,host,hover)
		for family in reference.furniture:
			if OS.get_environment("DF3D_STOCKS_RENDER")!="1":
				var response:=await request("production",{"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":int(family.id)})
				var snapshot: Dictionary=response.get("production",{}).get("independent_item",{}).get("snapshot",{})
				var receipt:=FileAccess.open(directory+"/stocks-family-response-"+str(int(family.kind))+".json",FileAccess.WRITE);receipt.store_string(JSON.stringify(response));receipt.close()
				var model=preload("res://scripts/item_sheet_state.gd").new();model.item_id=int(family.id)
				if not check(response.get("status")==C.ManagementStatus.Ok and model._valid(snapshot) and snapshot.has("appearance"),"Headless item family observation invalid: "+str(family.kind)):break
				if int(family.kind)==46 and snapshot.get("material_token","")=="CREATURE:DWARF:TOOTH":
					check(not snapshot.get("appearance",{}).get("corpse_selector",{}).get("layers",[]).is_empty(),"Native tooth selector recipe missing")
				if family.has("skin_facts"):
					check(not snapshot.get("appearance",{}).get("corpse_selector",{}).get("layers",[]).is_empty(),"Native skin selector recipe missing")
				var saved:=FileAccess.open(directory+"/stocks-furniture-wire-"+str(int(family.kind))+".json",FileAccess.WRITE);saved.store_string(JSON.stringify(snapshot));saved.close()
				continue
			owner.open_panel();if not await ready_state(owner.state):break
			owner.state.select_category(int(family.kind));if not await ready_state(owner.state):break
			if family.has("skin_facts"):
				for group in owner.state.groups:owner.state.expansion[owner.state.key(group)]=false
				var group: Dictionary=owner.state.groups[int(family.group_index)]
				owner.state.expansion[owner.state.key(group)]=true
				owner.state.first_item=(int(family.group_index)+int(family.member_index))*3
				owner.panel.refresh();if not await ready_state(owner.state):break
			else:
				if not owner.state.expanded(owner.state.groups[0]):
					await click(Vector2(500,130))
					if not await ready_state(owner.state):break
			var selected_row: int=owner.panel.page.find_custom(func(row):return row.get("id",-1)==int(family.id))
			if not check(selected_row>=0,"Furniture target is outside visible page"):break
			await click(owner.panel.position+owner.panel.item_canvas.position+owner.panel.control_rect(selected_row,-1).get_center())
			deadline=Time.get_ticks_msec()+5000
			while Time.get_ticks_msec()<deadline:
				world.poll();await process_frame
				if owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready:break
			if not check(owner.state.phase==State.Phase.Closed and owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready and owner.item_owner.state.item_id==int(family.id),"Furniture View destination failed: "+str(family.kind)+" stocks="+str(owner.state.phase)+" item="+str(owner.item_owner.state.phase)+" id="+str(owner.item_owner.state.item_id)+" expected="+str(family.id)):break
			var snapshot: Dictionary=owner.item_owner.state.snapshot
			check(snapshot.has("appearance"),"Furniture appearance missing")
			if int(family.kind)==46 and snapshot.get("material_token","")=="CREATURE:DWARF:TOOTH":
				check(not snapshot.get("appearance",{}).get("corpse_selector",{}).get("layers",[]).is_empty(),"Native tooth selector recipe missing")
			if family.has("skin_facts"):
				check(not snapshot.get("appearance",{}).get("corpse_selector",{}).get("layers",[]).is_empty(),"Native skin selector recipe missing")
			var saved:=FileAccess.open(directory+"/stocks-furniture-wire-"+str(int(family.kind))+".json",FileAccess.WRITE);saved.store_string(JSON.stringify(snapshot));saved.close()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/stocks-furniture-view-"+str(int(family.kind))+".png")
			if OS.get_environment("DF3D_STOCKS_CONTENTS_SCROLL")=="1":
				owner.item_owner.state.refresh_remaining=30
				root.size=Vector2i(960,600)
				for frame in 6:await process_frame
				var contents=owner.item_owner.panel.contents_view
				check(contents.page==7 and contents.scrollbar.visible,"Small contents capacity differs")
				for action in ["small","down","page","up","outside","arrow","wide","default"]:
					if action=="down":await wheel(Vector2(450,310))
					elif action=="page":await wheel(Vector2(450,310),false,true)
					elif action=="up":await wheel(Vector2(450,310),true)
					elif action=="outside":await wheel(Vector2(20,20))
					elif action=="arrow":await click(Vector2(648,522))
					elif action=="wide":root.size=Vector2i(1600,900)
					elif action=="default":root.size=Vector2i(1200,800)
					for frame in 6:await process_frame
					var expected: int={"small":0,"down":1,"page":9,"up":8,"outside":8,"arrow":9,"wide":9,"default":9}[action]
					check(contents.scrollbar.first==expected,"Contents scroll differs: "+action+" "+str(contents.scrollbar.first))
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory+"/contents-scroll-view-"+action+".png")
			if OS.get_environment("DF3D_STOCKS_CHILD_FLAGS")=="1":
				var target: int=int(reference.child_flags.id)
				check(int(family.id)==int(reference.child_flags.parent_id),"Wrong child parent fixture")
				var masks: Array=[0x80000,0x200000,0x800000,0x1000000]
				var step:=0
				for operation in 4:
					for restore in [false,true]:
						var prior: Dictionary=owner.item_owner.state.snapshot.duplicate(true)
						var row_index: int=prior.contents.find(prior.contents.filter(func(row):return row.kind==1 and row.id==target)[0])
						var desired: bool=bool(int(reference.child_flags.flags)&masks[operation]) if restore else not bool(int(reference.child_flags.flags)&masks[operation])
						var contents=owner.item_owner.panel.contents_view
						await click(owner.item_owner.panel.position+contents.position+contents.control_rect(row_index,operation+2).get_center())
						deadline=Time.get_ticks_msec()+5000
						while Time.get_ticks_msec()<deadline:
							world.poll();await process_frame
							if owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready:
								var fresh: Array=owner.item_owner.state.snapshot.get("contents",[]).filter(func(row):return row.kind==1 and row.id==target)
								if not fresh.is_empty() and bool(fresh[0].flags&masks[operation])==desired:break
						var fresh: Array=owner.item_owner.state.snapshot.get("contents",[]).filter(func(row):return row.kind==1 and row.id==target)
						if not check(owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready and not fresh.is_empty() and bool(fresh[0].flags&masks[operation])==desired,"Child flag receipt failed"):break
						step+=1
						var step_file:=FileAccess.open(directory+"/stocks-child-flags-step",FileAccess.WRITE);step_file.store_string(str(step));step_file.close()
						deadline=Time.get_ticks_msec()+3000
						while Time.get_ticks_msec()<deadline:
							if FileAccess.file_exists(directory+"/stocks-child-flags-ack") and FileAccess.get_file_as_string(directory+"/stocks-child-flags-ack").strip_edges()==str(step):break
							await create_timer(0.01).timeout
						check(FileAccess.get_file_as_string(directory+"/stocks-child-flags-ack").strip_edges()==str(step),"Child flags not independently verified")
						if step==1:
							owner.item_owner.state.refresh_remaining=10
							var stale:=await request("production",{"action":C.ManagementAction.FarmEdit,"independent_item":true,"item_id":int(family.id),"contents_item_id":target,"expected_revision":prior.revision,"farm_operation":C.FarmOperation.ItemForbid,"item_value":int(not desired)})
							check(stale.get("status")==C.ManagementStatus.Rejected and stale.get("production",{}).get("independent_item",{}).get("outcome")==C.FarmEditOutcome.Stale,"Stale parent revision edited child")
					if failed:break
				check(step==8,"Child flag sequence incomplete")
			if OS.get_environment("DF3D_STOCKS_CHILD_VIEW")=="1":
				var child_id: int=snapshot.contents[0].id
				var contents=owner.item_owner.panel.contents_view
				await click(owner.item_owner.panel.position+contents.position+contents.control_rect(0,1).get_center())
				deadline=Time.get_ticks_msec()+5000
				while Time.get_ticks_msec()<deadline:
					world.poll();await process_frame
					if owner.item_owner.state.item_id==child_id and owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready:break
				check(owner.item_owner.state.item_id==child_id and owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready,"Contained item View failed")
				var child: Dictionary=owner.item_owner.state.snapshot
				check(child.get("carrier",{}).get("id",-1)==int(family.id),"Child lost its container link")
				saved=FileAccess.open(directory+"/stocks-child-wire.json",FileAccess.WRITE);saved.store_string(JSON.stringify(child));saved.close()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/stocks-child-view.png")
				await click(owner.item_owner.panel.position+owner.item_owner.panel.holder_rect().get_center())
				deadline=Time.get_ticks_msec()+5000
				while Time.get_ticks_msec()<deadline:
					world.poll();await process_frame
					if owner.item_owner.state.item_id==int(family.id) and owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready:break
				check(owner.item_owner.state.item_id==int(family.id) and owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready,"Container View return failed")
			owner.item_owner.close_panel();check(owner.state.phase==State.Phase.Closed,"Furniture close reopened Stocks")
		owner.queue_free();host.queue_free();await process_frame
	var f:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"success":not failed,"categories":93,"groups":reference.selection.groups.size(),"items":ids.size(),"edits":2,"controller":true,"rendered":OS.get_environment("DF3D_STOCKS_RENDER")=="1","owner":OS.get_environment("DF3D_STOCKS_OWNER_WIRE")=="1","individual":reference.get("individual",false)}));f.close()
	if view!=null:view.queue_free()
	if hover!=null:hover.queue_free()
	state.dispose();service.queue_free();world.queue_free();await process_frame;quit(1 if failed else 0)
