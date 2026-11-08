extends SceneTree
const State=preload("res://scripts/kitchen_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func response() -> Dictionary:
	var key: Dictionary={"item_type":54,"item_subtype":-1,"mat_type":419,"mat_index":0}
	return {"kitchen_menu":{"outcome":C.KitchenMenuOutcome.None,"rows":[{"receipt":{"key":key,"count":12,"capabilities":3},"name":"fixture food","count_caption":"12?","estimated":true,"excluded":2,"material_token":"PLANT_MAT:MUSHROOM_HELMET_PLUMP:STRUCTURAL"}],"exclusions":[{"key":key,"flags":2}]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_kitchen.json"))
	var navigation:=State.new();navigation.phase=State.Phase.Ready
	for name in native.sort_reference.observations[0].names:navigation.rows.append({"name":name})
	for observation in native.input_reference.scroll:
		var label: String=observation.label
		if label.ends_with("STANDARDSCROLL_DOWN"):navigation.move_selection(1,13)
		elif label.ends_with("STANDARDSCROLL_UP"):navigation.move_selection(-1,13)
		elif label.ends_with("STANDARDSCROLL_PAGEDOWN"):navigation.move_selection(13,13)
		elif label.ends_with("STANDARDSCROLL_PAGEUP"):navigation.move_selection(-13,13)
		check(navigation.selected==int(observation.cursor) and navigation.rows[navigation.first].name==observation.first_food,"Native Kitchen selection/scroll differs: "+label)
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service)
	var retained:=State.new();retained.configure(service);retained.open();service.reply(retained.ticket,response())
	retained.selected=1;retained.first=1;retained.close(true)
	check(retained.rows.is_empty() and retained.exclusions.is_empty(),"Tab retention kept native authority")
	retained.open(true)
	check(retained.selected==1 and retained.first==1 and retained.phase==State.Phase.Reading,"Tab return reset local navigation")
	service.reply(retained.ticket,response())
	check(retained.selected==0 and retained.first==0,"Fresh shorter list failed to clamp retained navigation")
	retained.dispose()
	state.open();service.reply(state.ticket,response())
	check(state.phase==State.Phase.Ready and state.rows.size()==1,"Native read rejected")
	state.selected=1;state.set_search("PLUMP".to_utf8_buffer())
	check(state.selected==0 and state.query.query=="PLUMP" and service.calls[state.ticket].intent.query=="PLUMP","Search altered visible case or retained selection")
	service.reply(state.ticket,response());state.set_search(PackedByteArray());service.reply(state.ticket,response())
	var entry=preload("res://scripts/area_owner_filter.gd").new();root.add_child(entry);entry.byte_limit=26;entry.ascii_only=true;entry.focus_mode=Control.FOCUS_ALL;entry.grab_focus()
	for code in "abcdefghijklmnopqrstuvwxyz0123456789".to_utf32_buffer().size()/4:
		var event:=InputEventKey.new();event.pressed=true;event.unicode="abcdefghijklmnopqrstuvwxyz0123456789".unicode_at(code);entry.feed_key(event)
	check(entry.value.get_string_from_utf8()=="abcdefghijklmnopqrstuvwxyz","Kitchen textbox differs from native26-byte limit")
	var search_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_kitchen.json")).search_bytes_reference
	for observation in search_reference.observations:
		if not observation.has("text_bytes") or observation.label=="accent-backspace":continue
		entry.set_bytes(PackedByteArray())
		for code in str(observation.label).length():
			var event:=InputEventKey.new();event.pressed=true;event.unicode=str(observation.label).unicode_at(code);entry.feed_key(event)
		check(entry.value==PackedByteArray(observation.text_bytes),"Kitchen native byte input differs: "+str(observation.label))
	entry.queue_free()
	var controls: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_kitchen.json")).controls_reference
	for observation in controls.observations:
		var label: String=observation.label
		if label=="initial":continue
		if label.begins_with("right-"):state.cycle_type(1)
		elif label=="left":state.cycle_type(-1)
		else:state.toggle_capability(1 if label.begins_with("cook") else 2)
		check(state.query.type_filter==int(observation.type) and state.query.capability_filter==int(observation.capabilities),"Filter gesture differs from native: "+label)
		service.reply(state.ticket,response())
	state.select_sort(1);check(not state.query.sorts[0].reverse,"First Name sort flipped direction");service.reply(state.ticket,response())
	state.select_sort(1);check(state.query.sorts[0].reverse,"Second Name sort did not flip");service.reply(state.ticket,response())
	state.select_sort(2);check(not state.query.sorts[0].reverse and state.sort_directions[1],"New sort lost stored direction");service.reply(state.ticket,response())
	var q:=state.query.duplicate(true);q.query="plump";q.sorts=[{"column":1,"reverse":true},{"column":2,"reverse":false}]
	state.set_query(q);var old:=state.ticket;q.query="helmets";state.set_query(q);var newer:=state.ticket
	service.reply(old,response());check(state.ticket==newer and state.phase==State.Phase.Reading and service.detached.has(old),"Old query reply published")
	service.reply(newer,response());check(service.calls[newer].intent.sorts==q.sorts,"Sort priorities changed")
	var target: Dictionary=state.rows[0].receipt.duplicate(true);var expected:=state.exclusions.duplicate(true)
	state.toggle(0,1);var pending:=state.ticket
	check(service.calls[pending].intent.target==target and service.calls[pending].intent.expected==expected and state.rows.is_empty(),"Edit lost receipt or retained authority")
	state.toggle(0,2);state.set_query(q);check(state.ticket==pending,"Pending edit replaced")
	service.reply(pending,{"kitchen_menu":{"outcome":C.KitchenMenuOutcome.Applied,"rows":[],"exclusions":[]}})
	check(state.phase==State.Phase.Reading and service.calls[state.ticket].intent.query=="helmets","Successful edit did not refresh current query")
	service.reply(state.ticket,response());state.toggle(0,2)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"kitchen_menu":{"outcome":C.KitchenMenuOutcome.Unknown,"rows":[],"exclusions":[]}})
	var count: int=service.next;state.toggle(0,2)
	check(state.phase==State.Phase.Unknown and state.rows.is_empty() and state.exclusions.is_empty() and service.next==count,"Unknown retained authority or replayed")
	state.open();pending=state.ticket;state.close();service.reply(pending,response())
	check(state.phase==State.Phase.Closed and state.rows.is_empty(),"Closed owner accepted reply")
	state.open();pending=state.ticket;service.session_changed.emit();service.reply(pending,response())
	check(state.phase==State.Phase.Unavailable and state.query.query=="" and state.rows.is_empty(),"Session change retained old state")
	for defect in ["duplicate","capability","key","caption","exclusion"]:
		state.open();var malformed:=response();var value: Dictionary=malformed.kitchen_menu
		if defect=="duplicate":value.rows.append(value.rows[0].duplicate(true))
		if defect=="capability":value.rows[0].receipt.capabilities=0
		if defect=="key":value.rows[0].receipt.key.item_type=1.5
		if defect=="caption":value.rows[0].count_caption=""
		if defect=="exclusion":value.exclusions[0].flags=4
		service.reply(state.ticket,malformed);check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Malformed read accepted: "+defect)
	state.open();service.reply(state.ticket,response());state.toggle(0,1);pending=state.ticket;state.close();state.open();newer=state.ticket
	service.reply(pending,{"kitchen_menu":{"outcome":C.KitchenMenuOutcome.Applied,"rows":[],"exclusions":[]}})
	check(state.ticket==newer and state.phase==State.Phase.Reading,"Late edit replaced new owner")
	service.reply(newer,response());state.toggle(0,1)
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"kitchen_menu":{"outcome":C.KitchenMenuOutcome.Stale,"rows":[],"exclusions":[]}})
	check(state.phase==State.Phase.Rejected and state.exclusions.is_empty(),"Stale retained receipt")
	state.dispose()
	var owner=preload("res://scripts/standing_orders_panel.gd").new();root.add_child(owner)
	var host=preload("res://tests/work_details_state_test.gd").HostStub.new()
	owner.ui_host=host;owner.state.configure(service);owner.chores_state.configure(service);owner.kitchen_state.configure(service)
	owner.open_panel();pending=owner.state.ticket;owner.open_kitchen()
	check(owner.kitchen_active and host.active==owner and service.detached.has(pending),"Kitchen handoff lost owner or old read")
	service.reply(owner.kitchen_state.ticket,response());owner.kitchen_state.toggle(0,1);pending=owner.kitchen_state.ticket
	owner.return_standing();owner.open_chores();owner.request_work_details()
	check(owner.kitchen_active and owner.kitchen_state.ticket==pending,"Navigation retired pending Kitchen mutation")
	service.reply(pending,{"kitchen_menu":{"outcome":C.KitchenMenuOutcome.Applied,"rows":[],"exclusions":[]}});service.reply(owner.kitchen_state.ticket,response())
	owner.return_standing();check(not owner.kitchen_active and owner.state.phase==owner.state.Phase.Reading and host.active==owner,"Standing handoff lost owner")
	owner.open_chores();owner.open_kitchen();check(owner.return_category==5 and not owner.chores_active,"Kitchen lost Chores return")
	owner.return_standing();check(owner.chores_active and not owner.kitchen_active,"Kitchen did not return to Chores")
	owner.open_kitchen();pending=owner.kitchen_state.ticket;owner.close_panel();service.reply(pending,response())
	check(host.active==null and owner.kitchen_state.phase==State.Phase.Closed,"Closed Labor accepted Kitchen reply")
	owner.queue_free()
	if failures==0:print("KITCHEN_STATE_PASS")
	quit(1 if failures else 0)
