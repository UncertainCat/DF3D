extends Control
# Staged Tasks body, native_workshop.json. The sheet owns header/tabs/contents.
# Category/search, priority and task-detail integration remain unfinished.
signal details_requested(job_id: int)
signal priority_requested(job_id: int)
var art=preload("res://scripts/original_ui.gd").new()
var state
var colors: Array[Color]=[]
var input_allowed: Callable
var picking:=false
var first:=0
var target: int=-1
var scrollbar

func configure(world,model) -> void:
	state=model;art.configure(world);theme=art.theme
	colors=art.installed_palette(world.assets_root())
	size=Vector2(464,360);mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	scrollbar=preload("res://scripts/reports_scrollbar.gd").new()
	scrollbar.use_standalone_sheet=false;add_child(scrollbar);scrollbar.configure(world)
	scrollbar.input_allowed=available
	scrollbar.row_changed.connect(func(value):first=value;queue_redraw())
	state.changed.connect(refresh);resized.connect(refresh);refresh()

func available() -> bool:
	return state!=null and state.phase==state.Phase.Ready and state.ticket==0 and (not input_allowed.is_valid() or input_allowed.call())

func refresh() -> void:
	if state==null:return
	if target!=state.building_id:
		target=state.building_id;picking=false;first=0;scrollbar.dragging=false
	var rows: Array=state.recipes() if picking else state.jobs()
	scrollbar.position=Vector2(size.x-24,72)
	scrollbar.size=Vector2(16,maxi(36,floori((size.y-72)/36)*36))
	scrollbar.page=maxi(1,int(scrollbar.size.y/36))
	first=clampi(first,0,maxi(0,rows.size()-scrollbar.page))
	scrollbar.set_rows(rows.size() if picking else 0,first)
	if not available():scrollbar.dragging=false
	queue_redraw()

func choose_mode(value: bool) -> void:
	picking=value;first=0;refresh()

func add_rect() -> Rect2:
	return Rect2(264,state.jobs().size()*36+36,112,24)

func cancel_rect() -> Rect2:return Rect2(size.x-88,0,80,24)

func _gui_input(event: InputEvent) -> void:
	if not available() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and picking:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if picking:
		if cancel_rect().has_point(event.position):choose_mode(false);accept_event();return
		var index:=floori((event.position.y-72)/36)+first
		var rows: Array=state.recipes()
		if event.position.x<8 or event.position.x>=size.x-24 or event.position.y<72 or index<first or index>=rows.size():return
		var row: Dictionary=rows[index]
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
	if state==null or state.snapshot.is_empty():return
	if picking:
		patch("HORIZONTAL_OPTION_ACTIVE",Rect2(cancel_rect().position-Vector2(0,6),cancel_rect().size+Vector2(0,12)));caption("Cancel",cancel_rect().position+Vector2(16,18),12)
		var rows: Array=state.recipes()
		for index in mini(scrollbar.page,rows.size()-first):
			var row: Dictionary=rows[first+index];var y:=72+index*36
			patch("BUTTON_RECTANGLE_DARK",Rect2(8,y,size.x-16,36))
			var known: bool=row.has("availability")
			var enabled: bool=known and row.availability.available
			caption(row.name,Vector2(8,y+18),15 if enabled else 12)
			if known and not enabled:caption(row.availability.objection,Vector2(16,y+30),4)
		return
	var jobs: Array=state.jobs()
	for index in jobs.size():
		var job: Dictionary=jobs[index];var y:=36+index*36
		caption(job.name,Vector2(0,y+18),11)
		for entry in [[0,"BUILDING_JOBS_REPEAT"+("_ACTIVE" if job.repeat else "")],[1,"BUILDING_JOBS_DO_NOW"],[3,"STOCKS_VIEW_ITEM"],[4,"BUILDING_JOBS_SUSPENDED"+("_ACTIVE" if job.suspended else "")],[5,"BUILDING_JOBS_REMOVE"]]:
			var texture: Texture2D=art.texture(entry[1])
			if texture!=null:draw_texture_rect(texture,Rect2(304+entry[0]*24,y-6,24,36),false)
	patch("HORIZONTAL_OPTION_ACTIVE",Rect2(add_rect().position-Vector2(0,6),add_rect().size+Vector2(0,12)));caption("Add new task",add_rect().position+Vector2(8,18),10)

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
