extends "res://scripts/location_staff_candidates_frame.gd"
# Staged Residents surface. Indicators, actions, hover and remaining portrait
# states need acceptance before this may replace the public readout.
signal cancelled
const C=preload("res://scripts/management_contract.gd")
const NameColor=preload("res://scripts/native_name_color.gd")
const Indicators=preload("res://scripts/location_staff_indicators.gd")
const InfoTabs=preload("res://scripts/work_order_info_tabs.gd")
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

func configure_residents(source,model) -> void:
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root());picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search)
	search.theme=theme;search.configure(inset,colors);search.edited.connect(state.set_query)
	scrollbar.row_changed.connect(func(value):state.seek(value,page_rows))
	scrollbar.input_allowed=allowed
	state.changed.connect(refresh)
	visibility_changed.connect(func():
		if not is_visible_in_tree():search.release_focus())
	refresh()
func allowed() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func list_top() -> int:return 96 if wide_tabs else 120
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	page_rows=maxi(0,int((size.y-list_top()-120)/36))
	if search!=null:search.position=Vector2(32,size.y-60);search.size=Vector2(312,36)
	if scrollbar!=null:
		scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,maxi(36,size.y-list_top()-84));scrollbar.page=page_rows
	if state!=null and (state.capacity!=page_rows):state.seek(state.first,page_rows)
	refresh()
func refresh() -> void:
	if state==null:return
	var retained: Dictionary={}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or not row.has("sheet_icon"):continue
		var previous: Dictionary=portraits.get(int(row.id),{})
		if previous.get("recipe",{})==row.sheet_icon:retained[int(row.id)]=previous
		else:retained[int(row.id)]={"recipe":row.sheet_icon.duplicate(true),"texture":world.candidate_icon(row.sheet_icon)}
	portraits=retained
	if scrollbar!=null:scrollbar.set_rows(state.ids.size(),state.first)
	if search!=null:search.set_bytes(state.query)
	queue_redraw()
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
func _process(_delta: float) -> void:
	if ticks_override<0 and is_visible_in_tree() and state!=null and state.phase==state.Phase.Ready:
		for row: Dictionary in state.rows.values():
			if int(row.name_color.effect)!=0:queue_redraw();break
func _input(event: InputEvent) -> void:
	if not allowed() or state==null:return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancelled.emit();get_viewport().set_input_as_handled()
		elif search.has_focus():search.feed_key(event);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		state.seek(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),page_rows);accept_event()
	elif event.button_index==MOUSE_BUTTON_LEFT:
		search.release_focus()
		for index in page_rows:
			var row: Dictionary=state.row_at(state.first+index)
			if not row.is_empty() and row.has("specialization") and Rect2(696,list_top()+index*36,32,36).has_point(event.position):
				state.specialize(int(row.id));accept_event();return
		for index in SORTS.size():
			if Rect2(SORT_X[index]*8,list_top()-24,SORT_WIDTH[index]*8,12).has_point(event.position):state.select_sort(SORTS[index]);break
		accept_event()
func text(value: String,point: Vector2,color: int=15,width: float=-1) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,width,12,colors[color] if colors.size()>color else Color.WHITE)
func tab(value: String,point: Vector2,selected:=false,secondary:=false) -> float:
	var width:=value.length()+4
	var texture: Texture2D=art.texture(("SHORT_SUBTAB" if secondary else "SHORT_TAB")+("_SELECTED" if selected else ""))
	if texture!=null:
		for y in 2:
			for x in width:
				var sx:=x if x<2 else x-width+5 if x>=width-2 else 2
				draw_texture_rect_region(texture,Rect2(point+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
	text(value,point+Vector2(16,16),0 if selected else 15);return width*8
func _draw() -> void:
	if world==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),caption=="Creatures")
	var x:=8.0
	for caption in ["Residents","Pets/Livestock","Other","Dead/Missing"]:x+=tab(caption,Vector2(x,list_top()-60),caption=="Residents",true)
	if state==null:return
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
		var portrait: Texture2D=portraits.get(int(row.id),{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(18,y+2,32,32),false)
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
