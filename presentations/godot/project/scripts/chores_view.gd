extends "res://scripts/standing_orders_view.gd"
# Staged Chores surface. Native renderer43700d/43762a supplies name colors and
# the fixed labor palette; captions and participation remain native receipts.
signal category_requested(category: int)
const NameColor=preload("res://scripts/native_name_color.gd")
const LABOR_COLORS={23:5,37:6,1:3,2:3,6:3,3:3,4:3,5:3,7:3,8:3,74:3,77:3,9:7,75:7}
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
var row_facts: Dictionary={}
var ticks_override: int=-1
var labor_scrollbar
func configure_chores(source,model) -> void:
	configure_standing_orders(source,model);picture.configure(source)
	labor_scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(labor_scrollbar);labor_scrollbar.configure(source)
	scrollbar.input_allowed=allowed;labor_scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(first):state.seek_children(first,capacity());queue_redraw())
	labor_scrollbar.row_changed.connect(func(first):state.labor_first=first;queue_redraw())
	state.changed.connect(refresh_scrollbars)
	refresh_scrollbars()
func layout(view: Vector2) -> void:
	super.layout(view)
	if labor_scrollbar!=null:
		scrollbar.dragging=false;labor_scrollbar.dragging=false;refresh_scrollbars()
func refresh_scrollbars() -> void:
	if labor_scrollbar==null:return
	for bar in [scrollbar,labor_scrollbar]:bar.page=capacity();bar.size=Vector2(16,capacity()*36)
	scrollbar.position=Vector2(column_middle()-32,rows_top())
	labor_scrollbar.position=Vector2(size.x-32,rows_top())
	scrollbar.set_rows(state.children.size(),state.child_first);labor_scrollbar.set_rows(state.labors.size(),state.labor_first)
	state.child_first=scrollbar.first;state.labor_first=labor_scrollbar.first
	queue_redraw()
func display_rows(rows: Array) -> void:
	var retained: Dictionary={};row_facts={}
	for row: Dictionary in rows:
		var id:=int(row.id)
		row_facts[id]=row
		var previous: Dictionary=portraits.get(id,{})
		retained[id]=previous if previous.get("recipe",{})==row.sheet_icon else {"recipe":row.sheet_icon.duplicate(true),"texture":world.candidate_icon(row.sheet_icon)}
	portraits=retained;queue_redraw()
func rows_top() -> int:return list_top()+48
func capacity() -> int:return maxi(0,floori((size.y-rows_top()-24)/36))
func column_middle() -> int:return floori(size.x/16)*8
func participation_rect(enabled: bool) -> Rect2:
	return Rect2(size.x-496+(0 if enabled else 240),list_top(),240,36)
func child_rect(index: int) -> Rect2:return Rect2(16,rows_top()+index*36,column_middle()-32-(16 if state.children.size()>capacity() else 0),36)
func labor_rect(index: int) -> Rect2:return Rect2(column_middle()+8,rows_top()+index*36,size.x-column_middle()-24-(16 if state.labors.size()>capacity() else 0),36)
func checkmark(rect: Rect2,token: String,inset: int=40) -> void:
	# Native tile replacement clears caption glyphs under the full checkbox cells,
	# including transparent pixels; keep the surrounding native row pattern.
	var background: Texture2D=art.texture("BUTTON_RECTANGLE")
	if background!=null:
		for y in 3:
			for x in 4:draw_texture_rect_region(background,Rect2(rect.end.x-inset+x*8,rect.position.y+y*12,8,12),Rect2(16 if inset==32 and x==3 else 8,y*12,8,12))
	var texture: Texture2D=art.texture(token)
	if texture!=null:draw_texture_rect(texture,Rect2(rect.end.x-inset,rect.position.y,32,36),false)
func _draw() -> void:
	if world==null:return
	draw_chrome(5)
	if state.snapshot.is_empty():return
	for enabled in [true,false]:
		var rect:=participation_rect(enabled)
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if state.snapshot.enabled==enabled else "BUTTON_CATEGORY_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),30,3)
		text("Children do chores" if enabled else "Children don't do chores",rect.position+Vector2(16,24))
	for index in mini(capacity(),state.children.size()-state.child_first):
		var child: Dictionary=state.children[state.child_first+index]
		var rect:=child_rect(index)
		patch("BUTTON_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		patch("",Vector2i(rect.position/Vector2(8,12)),5,3,picture.texture(false))
		var portrait: Texture2D=portraits.get(int(child.id),{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
		var facts: Dictionary=row_facts.get(int(child.id),{})
		var ink:=NameColor.choose(facts.get("name_color",{}),ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
		if not ink.is_empty():text(child.caption,rect.position+Vector2(56,24),int(ink[0])+8*int(ink[2]))
		checkmark(rect,"LABOR_WORKER_UNASSIGNED" if int(child.id) in state.snapshot.exempted else "LABOR_WORKER_ASSIGNED" if state.snapshot.enabled else "LABOR_WORKER_ASSIGNED_NOBODY")
	for index in mini(capacity(),state.labors.size()-state.labor_first):
		var labor: Dictionary=state.labors[state.labor_first+index]
		var rect:=labor_rect(index)
		patch("BUTTON_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		text(labor.caption,rect.position+Vector2(24,24),LABOR_COLORS[int(labor.id)])
		checkmark(rect,"LABOR_WORKER_ASSIGNED" if state.snapshot.labors[state.labor_first+index].enabled else "LABOR_WORKER_UNASSIGNED",32)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var bar=scrollbar if event.position.x<column_middle() else labor_scrollbar
		bar.move_to(bar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if stone_use_rect().has_point(event.position):stone_use_requested.emit();accept_event();return
	if work_details_rect().has_point(event.position):work_details_requested.emit();return
	if kitchen_rect().has_point(event.position):kitchen_requested.emit();return
	for category in [0,1,2,3,4,6]:
		if category_rect(category).has_point(event.position):category_requested.emit(category);return
	if state.phase!=state.Phase.Ready:return
	for enabled in [true,false]:
		if participation_rect(enabled).has_point(event.position):state.set_enabled(enabled);return
	for index in mini(capacity(),state.children.size()-state.child_first):
		if child_rect(index).has_point(event.position):
			var id:=int(state.children[state.child_first+index].id)
			state.set_exempt(id,id not in state.snapshot.exempted);return
	for index in mini(capacity(),state.labors.size()-state.labor_first):
		if labor_rect(index).has_point(event.position):
			var row: Dictionary=state.snapshot.labors[state.labor_first+index]
			state.set_labor(int(row.id),not row.enabled);return
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh_scrollbars):state.changed.disconnect(refresh_scrollbars)
	super._exit_tree()
