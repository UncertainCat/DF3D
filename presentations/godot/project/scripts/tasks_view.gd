extends "res://scripts/standing_orders_view.gd"
# Native Tasks397c90 layout. Navigation is emitted to the panel owner; the
# view never drives DF menus or derives capabilities from job types.
signal navigation_requested(row: Dictionary,worker: bool,inspect: bool)
const NameColor=preload("res://scripts/native_name_color.gd")
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
var ticks_override: int=-1
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
func configure_tasks(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	state.changed.connect(refresh)
	mouse_exited.connect(_leave_hover)
	visibility_changed.connect(func():
		if not is_visible_in_tree():_leave_hover())
	refresh()
func list_top() -> int:return 48 if wide_tabs else 72
func capacity() -> int:return maxi(0,int((size.y-list_top()-24)/36))
func visible_first() -> int:return mini(state.first,maxi(0,state.rows.size()-capacity()))
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func refresh() -> void:
	var retained: Dictionary={}
	for index in range(visible_first(),mini(state.rows.size(),visible_first()+capacity())):
		var row: Dictionary=state.rows[index]
		for field in ["worker_appearance","building_appearance"]:
			if not row.has(field):continue
			var key: String=str(row.job_id)+field
			var prior: Dictionary=portraits.get(key,{})
			retained[key]=prior if prior.get("recipe")==row[field] else {"recipe":row[field].duplicate(true),"texture":world.candidate_icon(row[field])}
	portraits=retained
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first());queue_redraw()
func _exit_tree() -> void:
	_leave_hover()
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
func _process(_delta: float) -> void:
	update_hover()
	if is_visible_in_tree() and state!=null and state.rows.any(func(row):return row.get("worker_color",{}).get("effect",0)!=0):queue_redraw()
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_known=true;pointer_position=get_global_transform_with_canvas().affine_inverse()*event.position
	# Native396fd8 gates contextual scrolling by pointer cells, including the
	# scrollbar and the blank row above the list. Standard scroll keys are inert.
	if allowed() and state!=null and state.phase==state.Phase.Ready and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		if Rect2(0,list_top()-12,size.x+8,size.y-list_top()+12).has_point(point):
			var step: int=(capacity() if event.shift_pressed else 1)*(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
			state.seek(visible_first()+step,capacity());get_viewport().set_input_as_handled();return
	super._input(event)
func hover_target(point: Vector2) -> String:
	if state==null or state.phase!=state.Phase.Ready:return ""
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		if row.has("building_position") and Rect2(208,y,24,36).has_point(point):return "job-recenter"
		for entry in [[0,"can_view_job","view-task"],[2,"can_remove_worker","remove-worker"],[3,"can_suspend","suspend"],[4,"can_cancel","remove"]]:
			if row[entry[1]] and button_rect(index,entry[0]).has_point(point):return entry[2]
		if row.worker_id>=0:
			if Rect2(664,y,24,36).has_point(point):return "worker-recenter"
			if Rect2(688,y,24,36).has_point(point):return "worker-view"
	return ""
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	var target:=hover_target(pointer_position) if pointer_known and allowed() else ""
	if target.is_empty():hover_help.leave(get_instance_id())
	else:hover_help.enter_tasks(get_instance_id(),target)
func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func button_rect(index: int,slot: int) -> Rect2:return Rect2(232+slot*24,list_top()+index*36,24,36)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var caption:=InfoTabs.caption_at(event.position,wide_tabs)
	if not caption.is_empty():
		if caption!="Tasks":information_requested.emit(caption)
		accept_event();return
	if state.phase!=state.Phase.Ready:return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		if row.has("building_position") and Rect2(208,y,24,36).has_point(event.position):navigation_requested.emit(row.duplicate(true),false,false);return
		for slot in 5:
			if not button_rect(index,slot).has_point(event.position):continue
			if slot==0:
				if row.can_view_job:navigation_requested.emit(row.duplicate(true),false,true)
			else:state.apply(row.job_id,[0,2,1,3][slot-1])
			return
		if row.worker_id>=0:
			for slot in 2:
				if Rect2(664+slot*24,y,24,36).has_point(event.position):navigation_requested.emit(row.duplicate(true),true,slot==1);return
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Tasks")
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),int(size.x/8)-6,3)
		text(row.caption if row.caption.length()<24 else row.caption.left(20)+"...",Vector2(16,y+24),11)
		if row.has("building_position"):
			var recenter: Texture2D=art.texture("STOCKS_RECENTER")
			if recenter!=null:draw_texture_rect(recenter,Rect2(208,y,24,36),false)
		var tokens: Array=["STOCKS_VIEW_ITEM","BUILDING_JOBS_REPEAT"+("_ACTIVE" if row.repeating else ""),"BUILDING_JOBS_REMOVE_WORKER","BUILDING_JOBS_SUSPENDED"+("_ACTIVE" if row.suspended else ""),"BUILDING_JOBS_REMOVE"]
		var enabled: Array=[row.can_view_job,row.can_repeat,row.can_remove_worker,row.can_suspend,row.can_cancel]
		for slot in 5:
			if enabled[slot]:
				var icon: Texture2D=art.texture(tokens[slot])
				if icon!=null:draw_texture_rect(icon,button_rect(index,slot),false)
		for field in ["worker_appearance","building_appearance"]:
			if not row.has(field):continue
			var x:=368 if field=="worker_appearance" else 728
			patch("",Vector2i(x/8,int(y/12)),5,3,picture.texture(false))
			var portrait: Texture2D=portraits.get(str(row.job_id)+field,{}).get("texture")
			if portrait!=null:draw_texture_rect(portrait,Rect2(x+2,y+2,32,32),false)
		if row.worker_id>=0:
			var ink:=NameColor.choose(row.worker_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
			if not ink.is_empty():text(row.worker_name if row.worker_name.length()<31 else row.worker_name.left(27)+"...",Vector2(424,y+24),int(ink[0])+8*int(ink[2]))
			for slot in 2:
				var icon: Texture2D=art.texture(["STOCKS_RECENTER","STOCKS_VIEW_ITEM"][slot])
				if icon!=null:draw_texture_rect(icon,Rect2(664+slot*24,y,24,36),false)
		if row.building_id>=0:
			var cells:=int(size.x/8)-102-(2 if state.rows.size()>capacity() else 0)
			var caption: String=row.building_caption
			# Native399512 leaves negative-width names untruncated; zero-to-three
			# cells truncate without an ellipsis. Preserve the narrow-window spill.
			if cells>=0 and caption.length()>cells:
				caption=caption.left(cells-3)+"..." if cells>3 else caption.left(cells)
			text(caption,Vector2(784,y+24))
