extends RefCounted
# Replay protected native discrete-input observations through the viewport.
static func replay_activation(tree: SceneTree,view,rows: Array) -> bool:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_keys.json"))
	var observed: Dictionary={"chosen":[],"cancelled":0}
	var choose=func(id):observed.chosen.append(id)
	var cancel=func():observed.cancelled+=1
	view.unit_chosen.connect(choose);view.cancelled.connect(cancel)
	var valid:=true
	for sample in reference.cases:
		if sample.action not in ["OS_ENTER","_MOUSE_R"]:continue
		view.display_rows([]);view.display_rows(rows);view.actions_enabled=true
		view.filter_focused=bool(sample.before.focused)
		for i in view.rows.size():
			if int(view.rows[i].unit_id)==int(sample.before.selected_unit_id):view.selected=i;break
		observed.chosen.clear();observed.cancelled=0
		if sample.action=="OS_ENTER":
			var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true
			tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
			var expected: Array=[]
			if int(sample.after.unit_id)>=0:expected.append(int(sample.after.unit_id))
			valid=valid and observed.chosen==expected and observed.cancelled==0 and view.filter_focused==bool(sample.after.focused)
			# REPEAT_NOT: a key echo after textbox defocus must not assign.
			event.pressed=true;event.echo=true;tree.root.push_input(event,true)
			valid=valid and observed.chosen==expected
		else:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true
			event.position=Vector2(20,20);event.global_position=event.position
			tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
			valid=valid and observed.chosen.is_empty() and observed.cancelled==1 and not bool(sample.after.active)
	# Unready and empty lists cannot activate, even though Enter is consumed.
	for empty in [false,true]:
		view.display_rows([] if empty else rows);view.filter_focused=false;view.actions_enabled=empty
		observed.chosen.clear()
		var event:=InputEventKey.new();event.keycode=KEY_KP_ENTER;event.pressed=true
		tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
		valid=valid and observed.chosen.is_empty()
	view.unit_chosen.disconnect(choose);view.cancelled.disconnect(cancel)
	view.actions_enabled=false;view.display_rows([])
	if not valid:push_error("Native selector activation/cancellation differs")
	return valid

static func replay(tree: SceneTree, view, rows: Array) -> bool:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_scroll.json"))
	if rows.size()!=int(reference.total):push_error("Scroll fixture population differs");return false
	for sample in reference.cases:
		view.display_rows(rows,int(sample.start_first),int(sample.start_cursor))
		await tree.process_frame
		var action:=str(sample.action)
		if action.begins_with("STANDARDSCROLL") or action.begins_with("pagedown_") or action.begins_with("pageup_"):
			var event:=InputEventKey.new();event.pressed=true
			event.keycode=KEY_PAGEDOWN if "PAGEDOWN" in action or action.begins_with("pagedown_") else KEY_PAGEUP if "PAGEUP" in action or action.begins_with("pageup_") else KEY_DOWN if action.ends_with("DOWN") else KEY_UP
			tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
		else:
			var point:=Vector2(800,300)
			var button:=MOUSE_BUTTON_WHEEL_UP if action.ends_with("up") else MOUSE_BUTTON_WHEEL_DOWN
			if action.begins_with("single_"):
				button=MOUSE_BUTTON_LEFT
				point=Vector2(944,{"single_arrow_down":682,"single_arrow_up":94,"single_track_below":500,"single_track_above":112}[action])
			var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;tree.root.push_input(motion,true)
			var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
			event.button_index=button;event.shift_pressed="page" in action;event.pressed=true
			tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
		if view.first!=int(sample.first) or view.selected!=int(sample.cursor) or view.scrollbar.first!=int(sample.first):
			push_error("Native selector scroll differs: "+str(sample)+" actual="+str([view.first,view.selected,view.scrollbar.first]));return false
	return true

static func order_reference(location_id: int,role: int) -> Dictionary:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_order.json"))
	for sample in data.cases:
		if int(sample.location_id)==location_id and int(sample.role)==role:return sample
	return {}

# Only offline visual fixtures use this join. The live driver must supply its
# actual transported keys and passes them unchanged to replay_headers.
static func recorded_order_rows(rows: Array,location_id: int,role: int) -> Array:
	var reference:=order_reference(location_id,role)
	var result:=rows.duplicate(true)
	var by_id: Dictionary={}
	for row in reference.rows:by_id[int(row.unit_id)]=row
	for row in result:
		var facts: Dictionary=by_id[int(row.unit_id)]
		for key in ["source_index","profession_order","status_order","score"]:row[key]=int(facts[key])
		for key in ["name_sort_key","profession_sort_key"]:row[key]=PackedByteArray(facts[key])
	return result

static func replay_headers(tree: SceneTree,view,rows: Array,location_id: int,role: int) -> bool:
	var sample:=order_reference(location_id,role)
	if sample.is_empty() or rows.size()!=sample.rows.size():push_error("Header fixture population differs");return false
	var by_id: Dictionary={}
	for row in sample.rows:by_id[int(row.unit_id)]=row
	for row in rows:
		if not by_id.has(int(row.unit_id)):push_error("Header fixture actor missing");return false
		var facts: Dictionary=by_id[int(row.unit_id)]
		for key in ["source_index","profession_order","status_order","score"]:
			if int(row[key])!=int(facts[key]):push_error("Native ordering fact differs: "+key);return false
		for key in ["name_sort_key","profession_sort_key"]:
			if row[key]!=PackedByteArray(facts[key]):push_error("Native ordering bytes differ: "+key);return false
	view.display(rows.size(),0,3,[true,true,true,true]);view.display_rows(rows)
	for step in sample.states:
		if step.action=="scrolled":
			for n in 2:
				var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_PAGEDOWN
				tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
		elif step.action!="initial":
			var point:=Vector2([452,532,612,684][int(step.header)],66)
			var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;tree.root.push_input(motion,true)
			var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
			event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;tree.root.push_input(event,true)
			event.pressed=false;tree.root.push_input(event,true)
		await tree.process_frame;await RenderingServer.frame_post_draw
		if view.first!=int(step.first) or view.selected!=int(step.cursor) or view.scrollbar.first!=int(step.first) or view.active_header!=int(step.header) or view.descending!=step.directions:
			push_error("Native header state differs: "+str(step.action));return false
		if view.rows.size()!=step.ids.size():push_error("Native header row count differs");return false
		for index in view.rows.size():
			if int(view.rows[index].unit_id)!=int(step.ids[index]):
				push_error("Native header order differs role="+str(role)+" action="+str(step.action)+" index="+str(index));return false
	return true

# Semantic query replay only: no claim of text-entry/focus or filtered pixels.
static func replay_filter_keys(tree: SceneTree,view,rows: Array) -> bool:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_filter.json"))
	view.display_rows([])
	view.display_rows(rows)
	# Native editing capture starts filtering after two PageDown actions.
	view.move_selection(32)
	if view.selected!=32 or view.first!=17:
		push_error("Filter reset control did not begin scrolled");return false
	for sample in reference.cases:
		# Current controls use ASCII query bytes, including uppercase normalization
		# already observed from native. Non-ASCII query editing is not inferred.
		view.apply_filter_key(str(sample.normalized_query).to_ascii_buffer())
		await tree.process_frame
		var actual: Array=[]
		for row in view.rows:actual.append(int(row.unit_id))
		var expected: Array=[]
		for id in sample.ids:expected.append(int(id))
		if actual!=expected:
			push_error("Native filter membership/order differs: "+str(sample.case));return false
		if view.selected!=int(sample.cursor) or view.first!=0 or view.scrollbar.first!=0:
			push_error("Native filter did not reset cursor/scroll: "+str(sample.case));return false
	# Closing retires both the original population and query; a new opening must
	# not inherit a previous panel's filter or expose its retained identities.
	view.apply_filter_key("miner".to_ascii_buffer())
	view.display_rows([])
	if not view.all_rows.is_empty() or not view.filter_key.is_empty() or not view.rows.is_empty():
		push_error("Closed selector retained filter state");return false
	return true

# Actual viewport text/backspace events; expected membership/display bytes are
# native captures, not generated by the presentation's normalization routine.
static func replay_filter_input(tree: SceneTree,view,rows: Array) -> bool:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_filter.json"))
	var previous_ticks: int=view.ticks_override
	view.display_rows([]);view.display_rows(rows)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=view.position+Vector2(44,678);click.global_position=click.position
	tree.root.push_input(click,true);click.pressed=false;tree.root.push_input(click,true)
	if not view.filter_focused:push_error("Filter click did not focus");return false
	for sample in reference.cases:
		for i in 35:
			var back:=InputEventKey.new();back.keycode=KEY_BACKSPACE;back.pressed=true
			tree.root.push_input(back,true);back.pressed=false;tree.root.push_input(back,true)
		for character in str(sample.input):
			var event:=InputEventKey.new();event.pressed=true;event.unicode=character.unicode_at(0)
			tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
		view.ticks_override=750
		for cell in sample.filter_cells:
			if int(cell.x)==51+str(sample.display_text).length() and int(cell.y)==60 and int(cell.ch)==95:view.ticks_override=0
		view.queue_redraw()
		# Leave a render frame between readbacks, as the row capture does.
		for frame in 2:await tree.process_frame;await RenderingServer.frame_post_draw
		var actual: Array=[]
		for row in view.rows:actual.append(int(row.unit_id))
		var expected: Array=[]
		for id in sample.ids:expected.append(int(id))
		if actual!=expected or view.filter_text!=str(sample.display_text).to_ascii_buffer() or view.filter_key!=str(sample.normalized_query).to_ascii_buffer():
			push_error("Native filter input differs: "+str(sample.case));return false
		var rendered:=tree.root.get_texture().get_image()
		var font:=Image.load_from_file(view.world.ui_font_path())
		for cell in sample.filter_cells:
			var ch:=int(cell.ch)
			if ch in [0,32]:continue
			var color: Color=view.colors[int(cell.fg)+(8 if cell.bold else 0)]
			for y in 12:
				for x in 8:
					var ink:=font.get_pixel((ch%16)*8+x,(ch/16)*12+y)
					if ink.a<0.99 or minf(ink.r,minf(ink.g,ink.b))<0.99:continue
					var actual_pixel:=rendered.get_pixel(int(cell.x)*8+x,int(cell.y)*12+4+y)
					if absf(actual_pixel.r-color.r)+absf(actual_pixel.g-color.g)+absf(actual_pixel.b-color.b)>0.035:
						push_error("Native filter glyph pixels differ: "+str(sample.case)+" cell="+str(cell));return false
	view.display_rows([])
	view.ticks_override=previous_ticks
	if view.filter_focused or not view.filter_text.is_empty():push_error("Filter editing survived close");return false
	return true

static func replay_filter_navigation(tree: SceneTree,view,rows: Array) -> bool:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_staff_candidate_filter.json"))
	view.display_rows([]);view.display_rows(rows)
	var click=func(point: Vector2):
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
		event.position=view.position+point;event.global_position=event.position
		tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
	var key=func(code: int,unicode: int=0):
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=true
		tree.root.push_input(event,true);event.pressed=false;tree.root.push_input(event,true)
	click.call(Vector2(44,678))
	for index in reference.navigation_cases.size():
		match index:
			0:
				for character in "miner":key.call(0,character.unicode_at(0))
			1:key.call(KEY_DOWN)
			2:key.call(KEY_PAGEDOWN)
			3:key.call(KEY_2,50)
			4:
				for i in 35:key.call(KEY_BACKSPACE)
			5:click.call(Vector2(516,678));key.call(KEY_X,120)
			6:click.call(Vector2(44,678));key.call(KEY_K,107)
		await tree.process_frame
		var sample: Dictionary=reference.navigation_cases[index]
		var actual: Array=[]
		for row in view.rows:actual.append(int(row.unit_id))
		var expected: Array=[]
		for id in sample.ids:expected.append(int(id))
		if actual!=expected or view.filter_key!=str(sample.normalized_query).to_ascii_buffer() or view.filter_focused!=bool(sample.focused) or view.selected!=int(sample.cursor) or view.first!=int(sample.first):
			push_error("Native focused navigation differs: "+str(sample.case));return false
	view.display_rows([])
	return true
