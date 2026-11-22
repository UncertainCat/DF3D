extends "res://scripts/location_staff_candidates_frame.gd"
# Native Residents list, activity descriptions and semantic row actions.
signal information_requested(caption: String)
signal job_requested(unit_id: int)
signal cancelled
signal inspect_requested(unit_id: int)
signal focus_requested(tile: Vector3i)
const C=preload("res://scripts/management_contract.gd")
const NameColor=preload("res://scripts/native_name_color.gd")
const Indicators=preload("res://scripts/location_staff_indicators.gd")
const InfoTabs=preload("res://scripts/work_order_info_tabs.gd")
const RosterState=preload("res://scripts/residents_state.gd")
const SORTS=[C.ResidentsSort.Name,C.ResidentsSort.Category,C.ResidentsSort.Profession,C.ResidentsSort.Activity,C.ResidentsSort.Stress]
const SORT_X=[7,17,26,46,82]
const SORT_WIDTH=[10,9,10,35,4]
const SORT_LABELS=["Name","Cat","Prof","",""]
var state
var search
var colors: Array[Color]=[]
var wide_tabs:=false
var input_allowed: Callable
var ticks_override: int=-1
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO
var showing_activity:=false
# Native markup renderer d54640, jump table d54904 (link types0..11).
const LINK_RGB=[[0,128,255],[255,128,0],[255,255,0],[255,0,192],[0,255,0],[96,96,200],[0,255,255],[192,192,192],[0,64,255],[255,224,224],[255,0,64],[255,64,0]]

func configure_residents(source,model) -> void:
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root());picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search)
	search.theme=theme;search.configure(inset,colors);search.edited.connect(state.set_query)
	scrollbar.row_changed.connect(func(value):
		if state.activity_open():state.scroll_activity(value,activity_rows())
		else:state.seek(value,page_rows))
	scrollbar.input_allowed=allowed
	state.changed.connect(refresh)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			if search.is_inside_tree():search.release_focus()
			_leave_hover())
	mouse_exited.connect(_leave_hover)
	refresh()
func allowed() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func list_top() -> int:return 96 if wide_tabs else 120
func activity_rows() -> int:return maxi(0,int((size.y-list_top()-60)/12))
func activity_width() -> int:return clampi(int(size.x/8)-8,1,1024)
func activity_close_rect() -> Rect2:return Rect2(size.x-208,size.y-72,160,36)
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	page_rows=maxi(0,int((size.y-list_top()-120)/36))
	if search!=null:search.position=Vector2(32,size.y-60);search.size=Vector2(312,36)
	if scrollbar!=null:
		scrollbar.dragging=false
		scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,maxi(36,size.y-list_top()-84));scrollbar.page=page_rows
	if state!=null and (state.capacity!=page_rows):state.seek(state.first,page_rows)
	if state!=null:
		state.activity_capacity=activity_rows();state.resize_activity(activity_width())
	refresh()
func refresh() -> void:
	if state==null:return
	var retained: Dictionary={}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or not row.has("sheet_icon"):continue
		var previous: Dictionary=portraits.get(RosterState.row_key(row),{})
		if previous.get("recipe",{})==row.sheet_icon:retained[RosterState.row_key(row)]=previous
		else:retained[RosterState.row_key(row)]={"recipe":row.sheet_icon.duplicate(true),"texture":world.candidate_icon(row.sheet_icon)}
	portraits=retained
	if scrollbar!=null:
		if showing_activity!=state.activity_open():scrollbar.dragging=false
		if state.activity_open():
			scrollbar.position=Vector2(size.x-32,list_top()-24);scrollbar.size=Vector2(16,maxi(36,activity_rows()*12));scrollbar.page=activity_rows()
			scrollbar.set_rows(int(state.activity_page.get("max_y",-1))+1,state.activity_first)
		else:
			scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,maxi(36,size.y-list_top()-84));scrollbar.page=page_rows
			scrollbar.set_rows(state.ids.size(),state.first)
	if search!=null:
		if state.activity_open():search.release_focus()
		search.visible=not state.activity_open();search.set_bytes(state.query)
	showing_activity=state.activity_open()
	queue_redraw()
func _exit_tree() -> void:
	_leave_hover()
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
func _process(_delta: float) -> void:
	update_hover()
	if ticks_override<0 and is_visible_in_tree() and state!=null and state.phase==state.Phase.Ready:
		for row: Dictionary in state.rows.values():
			if int(row.name_color.effect)!=0:queue_redraw();break
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_known=true;pointer_position=get_global_transform_with_canvas().affine_inverse()*event.position
	if not allowed() or state==null:return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancelled.emit();get_viewport().set_input_as_handled()
		elif search.has_focus():search.feed_key(event);get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and not event.echo and pointer_known and state.phase==state.Phase.Ready:
			var target:=hover_target(pointer_position)
			if target.get("kind")=="recenter" and event.keycode==KEY_C:focus_requested.emit(target.row.position);get_viewport().set_input_as_handled()
			elif target.get("kind")=="details" and event.keycode==KEY_V:inspect_requested.emit(RosterState.row_key(target.row));get_viewport().set_input_as_handled()
			elif str(target.get("kind","")).begins_with("specialization_") and event.keycode==KEY_Z:state.specialize(RosterState.row_key(target.row));get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func hover_target(point: Vector2) -> Dictionary:
	if state==null or state.phase!=state.Phase.Ready:return {}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty():continue
		var y:=list_top()+index*36
		for entry in [["recenter",304,24],["details",336,24],["happiness",656,16],["specialization",696,32]]:
			if not Rect2(entry[1],y,entry[2],24 if entry[0]=="happiness" else 36).has_point(point):continue
			var kind: String=entry[0]
			if kind=="recenter" and not row.has("position"):return {}
			if kind=="details" and not row.get("can_inspect",true):return {}
			if kind=="happiness":
				if not row.has("happiness"):return {}
				kind+="_"+str(int(row.happiness))
			if kind=="specialization":
				if not row.has("specialization"):return {}
				kind+="_"+str(int(row.specialization.only_assigned))
			return {"kind":kind,"row":row}
		var x:=736
		for entry: Dictionary in row.get("assignments",[]):
			var slot:=Indicators.art_for(entry)
			if slot.is_empty() or slot.token.is_empty():continue
			var texture: Texture2D=art.texture(slot.token)
			if texture==null and not slot.fallback.is_empty():texture=art.texture(slot.fallback)
			if texture==null:continue
			if Rect2(x,y,32,36).has_point(point):return {"staff":slot.help,"row":row}
			x+=32
	return {}
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	var target: Dictionary=hover_target(pointer_position) if pointer_known and allowed() else {}
	if target.has("kind"):hover_help.enter_residents(get_instance_id(),target.kind)
	elif target.has("staff"):hover_help.enter_staff_indicator(get_instance_id(),target.staff)
	else:hover_help.leave(get_instance_id())
func _leave_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var step: int=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
		if state.activity_open():state.scroll_activity(state.activity_first+step,activity_rows())
		else:state.seek(state.first+step,page_rows)
		accept_event()
	elif event.button_index==MOUSE_BUTTON_LEFT:
		search.release_focus()
		var caption:=InfoTabs.caption_at(event.position,wide_tabs)
		if not caption.is_empty():
			if caption!="Creatures":information_requested.emit(caption)
			accept_event();return
		if state.activity_open():
			if activity_close_rect().has_point(event.position):state.close_activity()
			accept_event();return
		for index in page_rows:
			var row: Dictionary=state.row_at(state.first+index)
			if not row.is_empty() and state.phase==state.Phase.Ready and row.has("position") and Rect2(304,list_top()+index*36,24,36).has_point(event.position):
				focus_requested.emit(row.position);accept_event();return
			if not row.is_empty() and state.phase==state.Phase.Ready and row.get("can_inspect",true) and Rect2(336,list_top()+index*36,24,36).has_point(event.position):
				inspect_requested.emit(RosterState.row_key(row));accept_event();return
			if not row.is_empty() and state.phase==state.Phase.Ready and row.has("job_target") and Rect2(528,list_top()+index*36,24,36).has_point(event.position):
				job_requested.emit(RosterState.row_key(row));accept_event();return
			if not row.is_empty() and row.has("activity_target") and Rect2(624,list_top()+index*36,24,36).has_point(event.position):
				state.activity_capacity=activity_rows();state.show_activity(RosterState.row_key(row),activity_width());accept_event();return
			if not row.is_empty() and row.has("specialization") and Rect2(696,list_top()+index*36,32,36).has_point(event.position):
				state.specialize(RosterState.row_key(row));accept_event();return
		for index in SORTS.size():
			if Rect2(SORT_X[index]*8,list_top()-24,SORT_WIDTH[index]*8,12).has_point(event.position):state.select_sort(SORTS[index]);break
		accept_event()
func text(value: String,point: Vector2,color: int=15,width: float=-1) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,width,12,colors[color] if colors.size()>color else Color.WHITE)
func draw_activity() -> void:
	# DF supplies wrapping and blank lines. Only viewport scrolling is local.
	var links: Array=state.activity_page.get("links",[])
	for word: Dictionary in state.activity_page.get("words",[]):
		var row: int=int(word.y)-state.activity_first
		if int(word.x)<0 or row<0 or row>=activity_rows():continue
		var rgb: Array=word.rgb
		var link:=int(word.link)
		if link>=0 and link<links.size():
			var kind:=int(links[link].type)
			if kind>=0 and kind<LINK_RGB.size():rgb=LINK_RGB[kind]
		if theme.default_font!=null:
			theme.default_font.draw_string(get_canvas_item(),Vector2(16+int(word.x)*8,list_top()-12+row*12),word.text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(rgb[0],rgb[1],rgb[2]))
	var close_rect:=activity_close_rect()
	patch("HORIZONTAL_OPTION_CONFIRM",Vector2i(int(close_rect.position.x/8),int(close_rect.position.y/12)),20,3)
	text("Close",close_rect.position+Vector2(56,24))
func tab(value: String,point: Vector2,selected:=false,secondary:=false) -> float:
	var width:=value.length()+4
	var texture: Texture2D=art.texture(("SHORT_SUBTAB" if secondary else "SHORT_TAB")+("_SELECTED" if selected else ""))
	if texture!=null:
		for y in 2:
			for x in width:
				var sx:=x if x<2 else x-width+5 if x>=width-2 else 2
				draw_texture_rect_region(texture,Rect2(point+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
	text(value,point+Vector2(16,18),0 if selected else 15);return width*8
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28))
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),caption=="Creatures")
	var x:=8.0
	for caption in ["Residents","Pets/Livestock","Other","Dead/Missing"]:x+=tab(caption,Vector2(x,list_top()-60),caption=="Residents",true)
	if state==null:return
	if state.activity_open():
		draw_activity();return
	for index in SORTS.size():
		var suffix: String="ACTIVE" if state.sort==SORTS[index] else "INACTIVE"
		var direction: String="DESCENDING" if state.directions[SORTS[index]] else "ASCENDING"
		for cell in 4:
			var arrow:=strip("SORT_"+direction+"_"+suffix,cell)
			if arrow!=null:draw_texture_rect(arrow,Rect2((SORT_X[index]+cell)*8,list_top()-24,8,12),false)
		if not SORT_LABELS[index].is_empty():
			var width: int=SORT_WIDTH[index]-4
			for cell in width:
				var background:=strip("SORT_TEXT_"+suffix,0 if cell==0 else 2 if cell==width-1 else 1)
				if background!=null:draw_texture_rect(background,Rect2((SORT_X[index]+4+cell)*8,list_top()-24,8,12),false)
			text(SORT_LABELS[index],Vector2((SORT_X[index]+5)*8,list_top()-12),0 if suffix=="ACTIVE" else 7)
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty():continue
		var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(y/12)),int(size.x/8)-7,3)
		patch("",Vector2i(2,int(y/12)),5,3,picture.texture(false))
		var portrait: Texture2D=portraits.get(RosterState.row_key(row),{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(18,y+2,32,32),false)
		# Native142ed10 constructs the 3x3 unit-sheet button with this row's ID.
		var details: Texture2D=art.texture("STOCKS_VIEW_ITEM")
		if details!=null and row.get("can_inspect",true):draw_texture_rect(details,Rect2(336,y,24,36),false)
		if details!=null and row.has("job_target"):draw_texture_rect(details,Rect2(528,y,24,36),false)
		if details!=null and row.has("activity_target"):draw_texture_rect(details,Rect2(624,y,24,36),false)
		if row.has("position"):
			var recenter: Texture2D=art.texture("STOCKS_RECENTER")
			if recenter!=null:draw_texture_rect(recenter,Rect2(304,y,24,36),false)
		var ink:=NameColor.choose(row.name_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
		if not ink.is_empty():
			text(row.first_line,Vector2(56,y+24),int(ink[0])+8*int(ink[2]),240)
			text(row.second_line,Vector2(56,y+36),int(ink[0])+8*int(ink[2]),240)
		text(row.activity.caption,Vector2(368,y+24),int(row.activity.fg)+8*int(row.activity.bright),280)
		var indicator_x:=736
		for entry: Dictionary in row.get("assignments",[]):
			var slot:=Indicators.art_for(entry)
			if slot.is_empty() or slot.token.is_empty():continue
			var texture: Texture2D=art.texture(slot.token)
			if texture==null and not slot.fallback.is_empty():texture=art.texture(slot.fallback)
			if texture==null:continue
			var rectangle:=Rect2(indicator_x,y,32,36)
			if slot.building:rectangle=Rect2(indicator_x,y+2,32,32)
			draw_texture_rect(texture,rectangle,false);indicator_x+=32
		if row.has("specialization"):
			var specialization: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if row.specialization.only_assigned else "WORKER_DO_ANY_AVAILABLE_JOB")
			if specialization!=null:draw_texture_rect(specialization,Rect2(696,y,32,36),false)
		if row.has("happiness"):
			# Native1428db0 returns indicator6..12; graphics parser1100d63
			# maps these to BUTTON_STRESS_0..6. Captured row bounds are2x2 cells.
			var happiness: Texture2D=art.texture("BUTTON_STRESS_%d" % int(row.happiness))
			if happiness!=null:draw_texture_rect(happiness,Rect2(656,y,16,24),false)
