extends "res://scripts/standing_orders_view.gd"
# Staged Justice case/Convict view. Native190710 and230636 establish the
#1200x800 layout; full sorted artwork and other categories remain pending.
signal focus_requested(tile: Vector3i)
const C=preload("res://scripts/management_contract.gd")
const CASE_TABS=["Open cases","Closed cases","Cold cases","Fortress guard","Convicts","Intelligence"]
const NameColor=preload("res://scripts/native_name_color.gd")
const SORT_COLUMNS=[C.JusticeCandidateColumn.Name,C.JusticeCandidateColumn.Category,C.JusticeCandidateColumn.Profession,C.JusticeCandidateColumn.Crime]
var witness_scroll
var candidate_scroll
var search
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
var portraits: Dictionary={}
var ticks_override: int=-1
func intelligence_capacity() -> int:return maxi(0,int((size.y-list_top()-48)/(36 if state.intelligence.selected<0 else 12)))
func intelligence_rect(index: int) -> Rect2:return Rect2(16,list_top()+24+index*36,size.x-32,36)
func guard_open() -> bool:return state.tab==3
func roster_open() -> bool:return state.tab in [3,4]
func roster():return state.guard if guard_open() else state.convicts
func guard_capacity() -> int:return maxi(0,int((size.y-list_top()-(144 if guard_open() else 120))/36))
func guard_rect(index: int) -> Rect2:return Rect2(16,list_top()+(48 if guard_open() else 24)+index*36,size.x-56 if guard_open() else detail_x()-40,36)
func guard_sort_rect(index: int) -> Rect2:return Rect2([56,136,208,368][index],list_top()+(24 if guard_open() else 0),[10,9,10,4][index]*8,12)
func guard_allowed() -> bool:return allowed() and roster().phase in [roster().Phase.Ready,roster().Phase.DetailReading]
func picker_open() -> bool:return state.candidates.phase not in [state.candidates.Phase.Closed,state.candidates.Phase.Unavailable]
func picker_capacity() -> int:return maxi(0,int((size.y-list_top()-120)/36))
func picker_rect(index: int) -> Rect2:return Rect2(detail_x(),list_top()+24+index*36,size.x-detail_x()-40,36)
func interrogate_rect() -> Rect2:return Rect2(detail_x(),list_top()+24,104,36)
func convict_rect() -> Rect2:return Rect2(detail_x()+104,list_top()+24,72,36)
func sort_rect(index: int) -> Rect2:return Rect2(detail_x()+[5,15,24,35][index]*8,list_top(),[10,9,10,4][index]*8,12)
func picker_allowed() -> bool:return allowed() and state.candidates.phase==state.candidates.Phase.Ready
func configure_justice(source,model) -> void:
	configure_standing_orders(source,model)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):
		if state.tab==5:state.intelligence.seek(value,intelligence_capacity())
		else:state.seek(value,capacity()))
	witness_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(witness_scroll);witness_scroll.configure(source)
	witness_scroll.use_classic_art=true
	witness_scroll.input_allowed=allowed;witness_scroll.wheel_enabled=false
	witness_scroll.row_changed.connect(func(value):state.seek_witness(value,witness_capacity()))
	candidate_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(candidate_scroll);candidate_scroll.configure(source)
	candidate_scroll.use_classic_art=true
	candidate_scroll.input_allowed=func():return guard_allowed() if roster_open() else picker_allowed();candidate_scroll.wheel_enabled=false
	candidate_scroll.row_changed.connect(func(value):
		if roster_open():roster().seek(value,guard_capacity())
		else:state.candidates.seek(value,picker_capacity()))
	picture.configure(source)
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search);search.theme=theme;search.configure(inset,colors)
	search.edited.connect(func(value):
		if roster_open():roster().search(value.get_string_from_utf8())
		else:state.candidates.search(value.get_string_from_utf8()))
	visibility_changed.connect(func():
		if not is_visible_in_tree() and search.is_inside_tree():search.release_focus())
	state.changed.connect(refresh);refresh()
func information_rows() -> Array:
	var groups:=InfoTabs.rows(wide_tabs)
	if not wide_tabs:groups.reverse()
	return groups
func list_top() -> int:return 72 if wide_tabs else 96
func detail_x() -> int:return int(size.x/16)*8+8
func capacity() -> int:return maxi(0,int((size.y-list_top()-24)/36))
func witness_capacity() -> int:return maxi(0,int((size.y-list_top()-96)/60))
func visible_first() -> int:return mini(state.first,maxi(0,state.rows.size()-capacity()))
func witness_first() -> int:return mini(state.witness_first,maxi(0,state.detail.get("witnesses",[]).size()-witness_capacity()))
func tab_rect(index: int) -> Rect2:
	var x:=8
	for previous in index:x+=(CASE_TABS[previous].length()+4)*8
	return Rect2(x,36 if wide_tabs else 60,(CASE_TABS[index].length()+4)*8,24)
func case_rect(index: int) -> Rect2:
	return Rect2(16,list_top()+index*36,detail_x()-40-(16 if state.rows.size()>capacity() else 0),36)
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:
		state.intelligence.resize_columns(int((size.x-48)/8));refresh()
func refresh() -> void:
	scrollbar.position=Vector2(detail_x()-40,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first())
	witness_scroll.position=Vector2(size.x-32,list_top()+72);witness_scroll.size=Vector2(16,maxi(0,int((size.y-list_top()-96)/12))*12)
	witness_scroll.page=witness_capacity();witness_scroll.set_rows(state.detail.get("witnesses",[]).size(),witness_first())
	if picker_open():witness_scroll.hide()
	candidate_scroll.position=Vector2(size.x-32,list_top()+24);candidate_scroll.size=Vector2(16,maxi(36,size.y-list_top()-108))
	candidate_scroll.page=picker_capacity();candidate_scroll.set_rows(state.candidates.rows.size(),state.candidates.first)
	if not picker_open():candidate_scroll.hide()
	search.position=Vector2(detail_x()+16,size.y-60);search.size=Vector2(312,36);search.visible=picker_open()
	search.editable=allowed() and state.candidates.phase in [state.candidates.Phase.Ready,state.candidates.Phase.Reading,state.candidates.Phase.Rejected]
	search.set_bytes(state.candidates.query.to_utf8_buffer())
	if roster_open():
		scrollbar.hide();witness_scroll.hide()
		candidate_scroll.position=Vector2(size.x-32 if guard_open() else detail_x()-40,list_top()+(48 if guard_open() else 24));candidate_scroll.size=Vector2(16,maxi(36,size.y-list_top()-(132 if guard_open() else 108)))
		candidate_scroll.page=guard_capacity();candidate_scroll.set_rows(roster().rows.size(),roster().first)
		search.position.x=32;search.visible=true
		search.editable=allowed() and roster().phase in [roster().Phase.Ready,roster().Phase.Reading,roster().Phase.Rejected,roster().Phase.DetailReading]
		search.set_bytes(roster().query.to_utf8_buffer())
	if state.tab==5:
		scrollbar.position=Vector2(size.x-32,list_top()+24);scrollbar.size=Vector2(16,intelligence_capacity()*(36 if state.intelligence.selected<0 else 12));scrollbar.page=intelligence_capacity();scrollbar.set_rows(state.intelligence.rows.size() if state.intelligence.selected<0 else state.intelligence.lines.size(),state.intelligence.first)
	if not search.visible:search.release_focus()
	var retained: Dictionary={}
	var roster_state=roster() if roster_open() else state.candidates
	var count:=guard_capacity() if roster_open() else picker_capacity()
	for index in range(roster_state.first,mini(roster_state.rows.size(),roster_state.first+count)):
		var row: Dictionary=roster_state.rows[index]
		if not row.has("sheet_icon"):continue
		var id: int=row.unit_id;var recipe: Dictionary=row.sheet_icon;var previous: Dictionary=portraits.get(id,{})
		retained[id]=previous if previous.get("recipe",{})==recipe else {"recipe":recipe.duplicate(true),"texture":world.candidate_icon(recipe)}
	portraits=retained;queue_redraw()
func _process(_delta: float) -> void:
	if ticks_override<0 and is_visible_in_tree() and state!=null and picker_open():
		for index in range(state.candidates.first,mini(state.candidates.rows.size(),state.candidates.first+picker_capacity())):
			if state.candidates.rows[index].display.name_color.effect!=0:queue_redraw();break
	if ticks_override<0 and is_visible_in_tree() and state!=null and roster_open():
		for index in range(roster().first,mini(roster().rows.size(),roster().first+guard_capacity())):
			if roster().rows[index].name_color.effect!=0:queue_redraw();break
func _input(event: InputEvent) -> void:
	if allowed() and state!=null and (picker_open() or roster_open()) and event is InputEventKey and event.pressed and event.keycode!=KEY_ESCAPE and search.has_focus():
		search.feed_key(event);get_viewport().set_input_as_handled();return
	if allowed() and state!=null and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		if Rect2(Vector2(0,list_top()),size-Vector2(0,list_top())).has_point(point):
			var step: int=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
			if state.tab==5:state.intelligence.seek(state.intelligence.first+step,intelligence_capacity())
			elif roster_open():roster().seek(roster().first+step,guard_capacity())
			elif point.x<detail_x():state.seek(visible_first()+step,capacity())
			elif picker_open():state.candidates.seek(state.candidates.first+step,picker_capacity())
			else:state.seek_witness(witness_first()+step,witness_capacity())
			get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	search.release_focus()
	var groups:=information_rows()
	for row in groups.size():
		var x:=8
		for caption in groups[row]:
			var width: int=(caption.length()+4)*8
			if Rect2(x,12+row*24,width,24).has_point(event.position):
				if caption!="Justice":information_requested.emit(caption)
				return
			x+=width
	for index in 6:
		if tab_rect(index).has_point(event.position):state.select_tab(index);return
	if state.phase not in [state.Phase.Ready,state.Phase.DetailReading]:return
	if state.tab==5:
		if state.intelligence.selected<0:
			for index in mini(intelligence_capacity(),state.intelligence.rows.size()-state.intelligence.first):
				if intelligence_rect(index).has_point(event.position):state.intelligence.select_report(state.intelligence.rows[state.intelligence.first+index].index);return
		return
	if roster_open():
		for index in (4 if guard_open() else 3):
			if guard_sort_rect(index).has_point(event.position):roster().select_sort(SORT_COLUMNS[index],event.shift_pressed,event.ctrl_pressed);return
		if not guard_allowed():return
		for index in mini(guard_capacity(),roster().rows.size()-roster().first):
			var row: Dictionary=roster().rows[roster().first+index];var rect:=guard_rect(index)
			if Rect2(rect.position+Vector2(288,0),Vector2(24,36)).has_point(event.position) and row.has("position"):focus_requested.emit(row.position);return
			if Rect2(rect.position+Vector2(320,0),Vector2(24,36)).has_point(event.position):roster().inspect(row.unit_id);return
			if not guard_open() and rect.has_point(event.position):state.convicts.select_unit(row.unit_id);return
		return
	if picker_open():
		for index in 4:
			if sort_rect(index).has_point(event.position):state.candidates.select_sort(SORT_COLUMNS[index],event.shift_pressed,event.ctrl_pressed);return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		if case_rect(index).has_point(event.position):state.select_case(state.rows[visible_first()+index].crime_id);return
	if picker_open():
		for index in mini(picker_capacity(),state.candidates.rows.size()-state.candidates.first):
			if picker_rect(index).has_point(event.position):
				var id: int=state.candidates.rows[state.candidates.first+index].unit_id
				if state.candidates.interrogate:state.candidates.toggle_interrogation(id)
				else:state.candidates.convict(id)
				return
	elif state.tab!=1 and not state.detail.is_empty():
		if convict_rect().has_point(event.position):state.open_candidates()
		elif interrogate_rect().has_point(event.position):state.open_candidates(true)
func draw_intelligence() -> void:
	var model=state.intelligence;var x:=8.0
	for caption in ["Interrogations","Actors","Organizations","Plots"]:x+=tab(caption,Vector2(x,list_top()-12),"SHORT_SUBSUBTAB",caption=="Interrogations")
	if model.phase!=model.Phase.Ready:return
	if model.selected<0:
		for index in mini(intelligence_capacity(),model.rows.size()-model.first):
			var row: Dictionary=model.rows[model.first+index];var rect:=intelligence_rect(index)
			patch("BUTTON_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
			var width:=int((rect.size.x-24)/8)
			var title: String=row.title
			if title.length()>=width:title=title.left(width-3)+"..."
			var officer: String=row.officer
			if officer.length()>=width-1:officer=officer.left(width-4)+"..."
			text(title,rect.position+Vector2(16,24));text(officer,rect.position+Vector2(24,36),9)
	else:
		for index in mini(intelligence_capacity(),model.lines.size()-model.first):text(model.lines[model.first+index],Vector2(16,list_top()+36+index*12))
func draw_guard() -> void:
	if guard_open():text(roster().caption,Vector2(16,list_top()+12),roster().color)
	for index in (4 if guard_open() else 3):
		var rect:=guard_sort_rect(index);var x:=rect.position.x;var y:=rect.position.y;var width:=int(rect.size.x/8)
		var suffix: String="ACTIVE" if roster().priorities.has(SORT_COLUMNS[index]) else "INACTIVE"
		var direction: String="ASCENDING" if roster().directions[SORT_COLUMNS[index]] else "DESCENDING"
		for cell in 4:
			var arrow:=strip("SORT_"+direction+"_"+suffix,cell)
			if arrow!=null:draw_texture_rect(arrow,Rect2(x+cell*8,y,8,12),false)
		if index==3:continue
		for cell in width-4:
			var background:=strip("SORT_TEXT_"+suffix,0 if cell==0 else 2 if cell==width-5 else 1)
			if background!=null:draw_texture_rect(background,Rect2(x+32+cell*8,y,8,12),false)
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(x+40,y+12),["Name","Cat","Prof"][index],HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[0] if suffix=="ACTIVE" else Color8(160,160,160))
	for index in mini(guard_capacity(),roster().rows.size()-roster().first):
		var row: Dictionary=roster().rows[roster().first+index];var rect:=guard_rect(index)
		var selected: bool=row.unit_id==roster().cursor_id
		patch("BUTTON_RECTANGLE_SELECTED" if selected else "BUTTON_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		patch("",Vector2i(rect.position/Vector2(8,12)),5,3,picture.texture(selected))
		var portrait: Texture2D=portraits.get(row.unit_id,{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
		var ink:=NameColor.choose(row.name_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
		if not ink.is_empty():
			text(row.first_line,rect.position+Vector2(40,24),int(ink[0])+8*int(ink[2]))
			text(row.second_line,rect.position+Vector2(40,36),int(ink[0])+8*int(ink[2]))
		for control in [["STOCKS_RECENTER",288],["STOCKS_VIEW_ITEM",320]]:
			if control[1]==288 and not row.has("position"):continue
			var icon: Texture2D=art.texture(control[0])
			if icon!=null:draw_texture_rect(icon,Rect2(rect.position+Vector2(control[1],0),Vector2(24,36)),false)
func draw_convict_detail() -> void:
	var detail: Dictionary=state.convicts.detail
	if detail.is_empty():return
	var x:=detail_x()+8;var y:=list_top()+12
	for line in detail.sentence:text(line,Vector2(x,y));y+=12
	y+=12
	if detail.has("officer"):text(detail.officer,Vector2(x,y),9);y+=24
	for crime in detail.crimes:
		for field in ["caption","injured_party"]:
			if not crime.has(field) or crime[field].is_empty():continue
			var indent:=16 if field=="injured_party" else 0
			var lines:=preload("res://scripts/reports_view.gd").wrap_report(crime[field],maxi(1,int((size.x-32-x-indent)/8)))
			for line in lines:
				if y<=size.y-24:text(line,Vector2(x+indent,y),7 if indent else 15)
				y+=12
func draw_picker() -> void:
	for index in 4:
		var x: int=detail_x()+[5,15,24,35][index]*8;var width: int=[10,9,10,4][index]
		var suffix: String="ACTIVE" if state.candidates.priorities.has(SORT_COLUMNS[index]) else "INACTIVE"
		var direction: String="ASCENDING" if state.candidates.directions[SORT_COLUMNS[index]] else "DESCENDING"
		for cell in 4:
			var arrow:=strip("SORT_"+direction+"_"+suffix,cell)
			if arrow!=null:draw_texture_rect(arrow,Rect2(x+cell*8,list_top(),8,12),false)
		if index==3:continue
		for cell in width-4:
			var background:=strip("SORT_TEXT_"+suffix,0 if cell==0 else 2 if cell==width-5 else 1)
			if background!=null:draw_texture_rect(background,Rect2(x+32+cell*8,list_top(),8,12),false)
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),Vector2(x+40,list_top()+12),["Name","Cat","Prof"][index],HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[0] if suffix=="ACTIVE" else Color8(160,160,160))
	for index in mini(picker_capacity(),state.candidates.rows.size()-state.candidates.first):
		var row: Dictionary=state.candidates.rows[state.candidates.first+index];var rect:=picker_rect(index)
		var selected: bool=row.unit_id==state.candidates.cursor_id
		patch("BUTTON_RECTANGLE_SELECTED" if selected else "BUTTON_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		patch("",Vector2i(rect.position/Vector2(8,12)),5,3,picture.texture(selected))
		var portrait: Texture2D=portraits.get(row.unit_id,{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(rect.position+Vector2(2,2),Vector2(32,32)),false)
		var d: Dictionary=row.display
		var ink:=NameColor.choose(d.name_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
		if not ink.is_empty():text(d.name,rect.position+Vector2(40,24),int(ink[0])+8*int(ink[2]))
		var witness_x:=320 if state.candidates.interrogate else 280
		text(d.witness_label,rect.position+Vector2(witness_x,12),d.witness_color)
		text(d.deceased,rect.position+Vector2(witness_x,24),13)
		if state.candidates.interrogate:
			var checkbox: Texture2D=art.texture("LABOR_WORKER_ASSIGNED" if row.interrogation_pending else "LABOR_WORKER_UNASSIGNED")
			if checkbox!=null:draw_texture_rect(checkbox,Rect2(rect.position+Vector2(280,0),Vector2(32,36)),false)
			if row.interrogation_pending:text("Interview Scheduled",rect.position+Vector2(40,36),14)
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=information_rows()
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Justice")
	for index in 6:tab(CASE_TABS[index],tab_rect(index).position,"SHORT_SUBTAB",index==state.tab)
	if state.tab==5:draw_intelligence();return
	if roster_open():
		draw_guard()
		if not guard_open():draw_convict_detail()
		return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var rect:=case_rect(index)
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if row.crime_id==state.selected_id else "BUTTON_CATEGORY_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		text(row.caption,rect.position+Vector2(16,24))
	if picker_open():draw_picker();return
	if state.detail.is_empty():return
	var d: Dictionary=state.detail;var x:=detail_x();var top:=list_top()
	if d.has("injured_party"):text(d.injured_party,Vector2(x,top+12),7)
	text(d.status,Vector2(x,top+24),11 if d.resolution==C.JusticeCaseResolution.Unsolved else 13)
	if state.tab!=1:
		patch("HORIZONTAL_OPTION_ACTIVE",Vector2i(x/8,(top+24)/12),13,3)
		patch("HORIZONTAL_OPTION_ACTIVE",Vector2i((x+104)/8,(top+24)/12),9,3)
		text("Interrogate",Vector2(x+8,top+48));text("Convict",Vector2(x+112,top+48))
	var witnesses: Array=d.witnesses
	for index in mini(witness_capacity(),witnesses.size()-witness_first()):
		var row: Dictionary=witnesses[witness_first()+index];var y:=top+72+index*60
		text(row.witness,Vector2(x,y+12));text(row.description,Vector2(x,y+24),14)
		text(row.date,Vector2(x,y+36),7);text(row.reported,Vector2(x,y+48),7)
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
	super._exit_tree()
