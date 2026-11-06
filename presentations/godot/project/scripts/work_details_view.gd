extends "res://scripts/residents_view.gd"
# Staged native Work Details surface. Shared roster art/name/hover helpers come
# from Residents; this screen has its own layout, columns and input targets.
signal settings_requested
signal rename_requested
# Native mode renderer468800 uses category rectangles (parser119c728/119c496),
# not the textured worker-row rectangles or the dark generic selected button.
const DETAIL_SORTS=[C.WorkDetailWorkerSort.Name,C.WorkDetailWorkerSort.Category,C.WorkDetailWorkerSort.Profession,C.WorkDetailWorkerSort.Skills]
const DETAIL_SORT_X=[38,48,57,69]
const DETAIL_SORT_WIDTH=[10,9,10,20]
const DETAIL_SORT_LABELS=["Name","Cat","Prof",""]
var detail_first:=0
func configure_work_details(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root());picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search)
	search.theme=theme;search.configure(inset,colors);search.edited.connect(state.set_query)
	scrollbar.row_changed.connect(func(value):state.seek(value,page_rows));scrollbar.input_allowed=allowed
	state.changed.connect(refresh)
	visibility_changed.connect(func():
		if not is_visible_in_tree():search.release_focus();_leave_hover())
	mouse_exited.connect(_leave_hover);refresh()
func list_top() -> int:return 204 if wide_tabs else 228
func header_top() -> int:return list_top()-132
func detail_top() -> int:return header_top()+36
func detail_capacity() -> int:return maxi(0,int((size.y-detail_top()-24)/36))
func detail_rect(index: int) -> Rect2:return Rect2(24,detail_top()+(index-detail_first)*36,224,36)
func add_rect() -> Rect2:return Rect2(24,header_top(),240,36)
func mode_rect(index: int) -> Rect2:
	return Rect2(size.x-528+[0,168,352][index],header_top()+60,[168,184,144][index],36)
func member_rect(index: int) -> Rect2:return Rect2(800,list_top()+index*36,32,36)
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	page_rows=maxi(0,int((size.y-list_top()-120)/36))
	if search!=null:search.position=Vector2(280,size.y-60);search.size=Vector2(312,36)
	if scrollbar!=null:
		scrollbar.dragging=false;scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,maxi(36,size.y-list_top()-84));scrollbar.page=page_rows
	detail_first=clampi(detail_first,0,maxi(0,(state.details.size() if state!=null else 0)-detail_capacity()))
	if state!=null and state.capacity!=page_rows:state.seek(state.first,page_rows)
	refresh()
func refresh() -> void:
	if state==null:return
	var retained: Dictionary={}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or not row.has("sheet_icon"):continue
		var previous: Dictionary=portraits.get(int(row.id),{})
		retained[int(row.id)]=previous if previous.get("recipe",{})==row.sheet_icon else {"recipe":row.sheet_icon.duplicate(true),"texture":world.candidate_icon(row.sheet_icon)}
	portraits=retained
	if scrollbar!=null:scrollbar.set_rows(state.ids.size(),state.first)
	if search!=null:search.set_bytes(state.query);search.editable=allowed() and state.phase!=state.Phase.Applying
	queue_redraw()
func hover_target(point: Vector2) -> Dictionary:
	if state==null or state.phase!=state.Phase.Ready:return {}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty():continue
		var y:=list_top()+index*36
		if row.has("specialization") and Rect2(720,y,32,36).has_point(point):return {"kind":"specialization_"+str(int(row.specialization.only_assigned)),"row":row}
		var x:=760
		for entry: Dictionary in row.get("assignments",[]):
			var slot:=Indicators.art_for(entry)
			if slot.is_empty() or slot.token.is_empty():continue
			if Rect2(x,y,32,36).has_point(point):return {"staff":slot.help,"row":row}
			x+=32
	return {}
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var step: int=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
		if event.position.x<264:detail_first=clampi(detail_first+step,0,maxi(0,state.details.size()-detail_capacity()));queue_redraw()
		else:state.seek(state.first+step,page_rows)
		accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	search.release_focus();accept_event()
	if add_rect().has_point(event.position):state.create_detail();return
	for index in range(detail_first,mini(state.details.size(),detail_first+detail_capacity())):
		if detail_rect(index).has_point(event.position):state.select_detail(index);return
	for index in 3:
		if mode_rect(index).has_point(event.position):state.set_mode([1,3,2][index]);return
	if Rect2(272,header_top(),368,36).has_point(event.position):rename_requested.emit();return
	if Rect2(640,header_top(),32,36).has_point(event.position):settings_requested.emit();return
	for index in 4:
		if Rect2(DETAIL_SORT_X[index]*8,list_top()-24,DETAIL_SORT_WIDTH[index]*8,12).has_point(event.position):state.select_sort(DETAIL_SORTS[index]);return
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or state.phase!=state.Phase.Ready:continue
		if member_rect(index).has_point(event.position):state.set_member(int(row.id),not row.member);return
		if Rect2(720,list_top()+index*36,32,36).has_point(event.position):state.specialize(int(row.id));return
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),caption=="Labor")
	var x:=8.0
	for caption in ["Work Details","Standing orders","Kitchen","Stone use"]:x+=tab(caption,Vector2(x,header_top()-36),caption=="Work Details",true)
	if state==null:return
	patch("HORIZONTAL_OPTION_ACTIVE",Vector2i(3,int(header_top()/12)),30,3);text("Add new work detail",Vector2(64,header_top()+24),10)
	for index in range(detail_first,mini(state.details.size(),detail_first+detail_capacity())):
		var row: Dictionary=state.details[index];var rect:=detail_rect(index)
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if int(state.selected.get("index",-1))==int(row.index) else "BUTTON_CATEGORY_RECTANGLE",Vector2i(3,int(rect.position.y/12)),28,3)
		if int(row.icon)>=0 and int(row.icon)<Indicators.WORK_DETAILS.size():
			var icon: Texture2D=art.texture("WORK_DETAIL_"+Indicators.WORK_DETAILS[int(row.icon)])
			if icon!=null:draw_texture_rect(icon,Rect2(rect.position,Vector2(32,36)),false)
		text(row.name,rect.position+Vector2(48,24),15,176)
	if state.selected.is_empty():return
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for cell in 42:draw_texture_rect_region(filter,Rect2(272+cell*8,header_top()+y*12,8,12),Rect2(0 if cell==0 else 8,y*12,8,12))
	var endcap: Texture2D=art.texture("BUTTON_FILTER_NAME")
	if endcap!=null:draw_texture_rect(endcap,Rect2(608,header_top(),32,36),false)
	text(state.selected.name,Vector2(288,header_top()+24),15,320)
	var settings: Texture2D=art.texture("LABOR_EDIT_WORK_DETAIL")
	if settings!=null:draw_texture_rect(settings,Rect2(640,header_top(),32,36),false)
	for index in 3:
		var rect:=mode_rect(index);var selected_mode: bool=int(state.selected.mode)==[1,3,2][index]
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if selected_mode else "BUTTON_CATEGORY_RECTANGLE",Vector2i(int(rect.position.x/8),int(rect.position.y/12)),int(rect.size.x/8),3)
		text(["Everybody does this","Only selected do this","Nobody does this"][index],rect.position+Vector2(8,24),8 if index==0 and state.selected.cannot_be_everybody else 15)
	for index in 4:
		var suffix: String="ACTIVE" if state.sort==DETAIL_SORTS[index] else "INACTIVE"
		var direction: String="ASCENDING" if state.directions[DETAIL_SORTS[index]] else "DESCENDING"
		for cell in 4:
			var arrow:=strip("SORT_"+direction+"_"+suffix,cell)
			if arrow!=null:draw_texture_rect(arrow,Rect2((DETAIL_SORT_X[index]+cell)*8,list_top()-24,8,12),false)
		if DETAIL_SORT_LABELS[index].is_empty():continue
		for cell in DETAIL_SORT_WIDTH[index]-4:
			var background:=strip("SORT_TEXT_"+suffix,0 if cell==0 else 2 if cell==DETAIL_SORT_WIDTH[index]-5 else 1)
			if background!=null:draw_texture_rect(background,Rect2((DETAIL_SORT_X[index]+4+cell)*8,list_top()-24,8,12),false)
		text(DETAIL_SORT_LABELS[index],Vector2((DETAIL_SORT_X[index]+5)*8,list_top()-12),0 if suffix=="ACTIVE" else 7)
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty():continue
		var y:=list_top()+index*36
		patch("BUTTON_RECTANGLE_DARK",Vector2i(33,int(y/12)),int(size.x/8)-38,3)
		patch("",Vector2i(33,int(y/12)),5,3,picture.texture(false))
		var portrait: Texture2D=portraits.get(int(row.id),{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(266,y+2,32,32),false)
		var ink:=NameColor.choose(row.name_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
		if not ink.is_empty():
			text(row.first_line,Vector2(304,y+24),int(ink[0])+8*int(ink[2]),240);text(row.second_line,Vector2(304,y+36),int(ink[0])+8*int(ink[2]),240)
		# Preserve native sequential row overdraw; no overflow correction approved.
		for skill in row.skills.size():text(row.skills[skill].caption,Vector2(552,y+24+skill*12),15,160)
		var indicator_x:=760
		for entry: Dictionary in row.get("assignments",[]):
			var slot:=Indicators.art_for(entry)
			if slot.is_empty() or slot.token.is_empty():continue
			var texture: Texture2D=art.texture(slot.token)
			if texture==null and not slot.fallback.is_empty():texture=art.texture(slot.fallback)
			if texture!=null:draw_texture_rect(texture,Rect2(indicator_x,y+(2 if slot.building else 0),32,32 if slot.building else 36),false);indicator_x+=32
		if row.has("specialization"):
			var texture: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if row.specialization.only_assigned else "WORKER_DO_ANY_AVAILABLE_JOB")
			if texture!=null:draw_texture_rect(texture,Rect2(720,y,32,36),false)
		var checkbox: Texture2D=art.texture("LABOR_WORKER_ASSIGNED" if row.member else "LABOR_WORKER_UNASSIGNED")
		if checkbox!=null:draw_texture_rect(checkbox,member_rect(index),false)
