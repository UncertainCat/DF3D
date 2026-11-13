extends Control
# Staged Tasks body, native_workshop.json. The sheet owns header/tabs/contents.
# Native category choices share the task rows; Cancel leaves the picker.
signal details_requested(job_id: int)
signal priority_requested(job_id: int)
signal picker_changed
var art=preload("res://scripts/original_ui.gd").new()
var state
var colors: Array[Color]=[]
var input_allowed: Callable
var picking:=false
var first:=0
var target: int=-1
var scrollbar
var query_bytes:=PackedByteArray()
var search_focused:=false
var blink:=-1
var search_label: Label

func configure(world,model) -> void:
	state=model;art.configure(world);theme=art.theme
	colors=art.installed_palette(world.assets_root())
	size=Vector2(464,360);mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	scrollbar=preload("res://scripts/reports_scrollbar.gd").new()
	scrollbar.use_standalone_sheet=false;add_child(scrollbar);scrollbar.configure(world)
	scrollbar.input_allowed=available
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	search_label=Label.new();search_label.position=Vector2(16,42);search_label.size=Vector2(368,12)
	search_label.add_theme_font_size_override("font_size",12);search_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(search_label)
	state.changed.connect(refresh);resized.connect(refresh);refresh()

func available() -> bool:
	return state!=null and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())

func refresh() -> void:
	if state==null:return
	if target!=state.building_id:
		target=state.building_id;picking=false;first=0;scrollbar.dragging=false;query_bytes.clear();search_focused=false
	search_label.visible=picking
	var rows: Array=state.choices() if picking else state.jobs()
	# Native1844f1..1847bc reserves six cells at the sheet bottom, then
	# divides the remaining span by three cells per choice. The scrollbar's
	# outer arrows begin half a cell above the first button (1857c9..1858b1).
	scrollbar.page=maxi(1,floori((size.y-126)/36))
	scrollbar.position=Vector2(size.x-24,66)
	scrollbar.size=Vector2(16,scrollbar.page*36)
	first=clampi(first,0,maxi(0,rows.size()-scrollbar.page))
	scrollbar.set_rows(rows.size() if picking else 0,first)
	if not available():scrollbar.dragging=false
	queue_redraw()

func choose_mode(value: bool) -> void:
	picking=value;first=0;query_bytes.clear();search_focused=false
	state.reset_picker();refresh();picker_changed.emit()

func leave_picker() -> void:
	if state.parent==null:choose_mode(false)
	elif available():
		first=0;query_bytes.clear();search_focused=false;state.go_back()

func query_text() -> String:
	var text:=""
	for byte in query_bytes:text+=String.chr(byte if byte<128 else art.CP437_HIGH[byte-128])
	return text

func search_allowed() -> bool:
	return picking and state.phase in [state.Phase.Ready,state.Phase.Reading] and (not input_allowed.is_valid() or input_allowed.call())

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not search_allowed() or not search_focused or not event is InputEventKey or not event.pressed:return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.keycode==KEY_ESCAPE:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if not event.echo and not event.shift_pressed:search_focused=false;queue_redraw()
		get_viewport().set_input_as_handled();return
	var before:=query_bytes.duplicate()
	if event.keycode==KEY_BACKSPACE:
		if not query_bytes.is_empty():query_bytes.resize(query_bytes.size()-1)
	elif event.unicode>=32:
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if query_bytes.size()>=46:break
			query_bytes.append(byte)
	if before!=query_bytes:first=0;state.set_query(query_text());queue_redraw()
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not picking or not is_visible_in_tree():return
	var next:=int(Time.get_ticks_msec()%1000<500)
	if next!=blink:blink=next;queue_redraw()

func add_rect() -> Rect2:
	return Rect2(264,state.jobs().size()*36+36,112,24)

func cancel_rect() -> Rect2:return Rect2(size.x-88,0,80,24)

func _gui_input(event: InputEvent) -> void:
	if search_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if cancel_rect().has_point(event.position):leave_picker();accept_event();return
		if Rect2(0,30,size.x-8,36).has_point(event.position):search_focused=not search_focused;queue_redraw();accept_event();return
	if not available() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and picking:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if picking:
		if cancel_rect().has_point(event.position):leave_picker();accept_event();return
		var index:=floori((event.position.y-66)/36)+first
		var rows: Array=state.choices()
		if event.position.x<0 or event.position.x>=size.x-(24 if scrollbar.visible else 8) or event.position.y<66 or index<first or index>=mini(rows.size(),first+scrollbar.page):return
		var row: Dictionary=rows[index]
		if row.get("category_choice",false):
			first=0;query_bytes.clear();search_focused=false;state.open_category(row.key);accept_event();return
		# Unknown availability is not evidence that this task can be selected.
		if row.has("availability") and row.availability.available:
			state.queue_task(row.key);choose_mode(false)
		accept_event();return
	if add_rect().has_point(event.position):choose_mode(true);accept_event();return
	var index:=floori((event.position.y-36)/36)
	var jobs: Array=state.jobs()
	if index<0 or index>=jobs.size() or not jobs[index].editable:return
	var job: Dictionary=jobs[index]
	if event.position.y-36-index*36>=24:return
	match floori((event.position.x-304)/24):
		0:state.set_repeat(job.id,not job.repeat)
		1:priority_requested.emit(job.id)
		2:state.move_up(job.id)
		3:details_requested.emit(job.id)
		4:state.set_suspended(job.id,not job.suspended)
		5:state.cancel_task(job.id)
	accept_event()

func patch(token: String, rect: Rect2) -> void:
	var texture: Texture2D=art.texture(token)
	if texture==null:return
	var columns:=int(rect.size.x/8);var rows:=int(rect.size.y/12)
	for y in rows:
		for x in columns:
			draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(0 if x==0 else 16 if x==columns-1 else 8,0 if y==0 else texture.get_height()-12 if y==rows-1 else 12,8,12))

func caption(text: String, point: Vector2, color: int) -> void:
	if theme.default_font!=null and colors.size()==16:
		theme.default_font.draw_string(get_canvas_item(),point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])

func _draw() -> void:
	if state==null:return
	if picking:
		patch("HORIZONTAL_OPTION_ACTIVE",Rect2(cancel_rect().position-Vector2(0,6),cancel_rect().size+Vector2(0,12)));caption("Back" if state.parent!=null else "Cancel",cancel_rect().position+Vector2(24 if state.parent!=null else 16,18),12)
		var texture: Texture2D=art.texture("BUTTON_FILTER")
		var columns:=int((size.x-8)/8)
		if texture!=null:
			for y in 3:
				for x in columns:
					var sx:=0 if x==0 else x-(columns-6) if x>=columns-4 else 1
					draw_texture_rect_region(texture,Rect2(x*8,30+y*12,8,12),Rect2(sx*8,y*12,8,12))
		var text:=query_text()
		if search_focused and blink==1:text+="_"
		elif text.is_empty() and not search_focused:text="..."
		search_label.text=text
		if colors.size()==16:search_label.add_theme_color_override("font_color",colors[15 if search_focused or not query_bytes.is_empty() else 8])
		var rows: Array=state.choices()
		for index in mini(scrollbar.page,rows.size()-first):
			var row: Dictionary=rows[first+index];var y:=72+index*36
			patch("BUTTON_RECTANGLE",Rect2(0,y-6,size.x-(24 if scrollbar.visible else 8),36))
			var known: bool=row.has("availability")
			var enabled: bool=row.get("category_choice",false) or (known and row.availability.available)
			caption(row.name,Vector2(8,y+18),15 if enabled else 12)
			# Native1854c9: objections take precedence over memorial info.
			var objection: String=row.get("availability",{}).get("objection","")
			if not objection.is_empty():caption(objection,Vector2(16,y+30),4)
			elif row.has("memorial"):
				var priority: int=row.memorial.priority
				# Native1b9ee0: only priority1000 is yellow; other non-ghost groups are cyan.
				caption(row.memorial.text,Vector2(16,y+30),13 if priority==1 else (14 if priority==1000 else 11))
		return
	if state.snapshot.is_empty():return
	var jobs: Array=state.jobs()
	for index in jobs.size():
		var job: Dictionary=jobs[index];var y:=36+index*36
		caption(job.name,Vector2(0,y+18),11)
		if job.get("active",false):
			var marker: Texture2D=art.texture("BUILDING_JOBS_ACTIVE")
			if marker!=null:draw_texture_rect(marker,Rect2(280,y-6,24,36),false)
		for entry in [[0,"BUILDING_JOBS_REPEAT"+("_ACTIVE" if job.repeat else "")],[1,"BUILDING_JOBS_DO_NOW"+("_ACTIVE" if job.get("priority",false) else "")],[2,"BUILDING_JOBS_PRIORITY_UP"],[3,"STOCKS_VIEW_ITEM"],[4,"BUILDING_JOBS_SUSPENDED"+("_ACTIVE" if job.suspended else "")],[5,"BUILDING_JOBS_REMOVE"]]:
			if entry[0]==1 and not job.has("priority"):continue
			if entry[0]==2 and (index==0 or not job.get("can_move_up",false)):continue
			var texture: Texture2D=art.texture(entry[1])
			if texture!=null:draw_texture_rect(texture,Rect2(304+entry[0]*24,y-6,24,36),false)
	patch("HORIZONTAL_OPTION_ACTIVE",Rect2(add_rect().position-Vector2(0,6),add_rect().size+Vector2(0,12)));caption("Add new task",add_rect().position+Vector2(8,18),10)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
