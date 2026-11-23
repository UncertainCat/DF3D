extends "res://scripts/residents_view.gd"
signal standing_orders_requested
signal stone_use_requested
signal kitchen_requested
# Native Work Details surface. Shared roster art/name/hover helpers come
# from Residents; this screen has its own layout, columns and input targets.
signal settings_requested
signal rename_requested
signal name_edited(value: String)
signal name_finished(action: Dictionary)
signal reset_requested
signal delete_requested
# Native mode renderer468800 uses category rectangles (parser119c728/119c496),
# not the textured worker-row rectangles or the dark generic selected button.
const DETAIL_SORTS=[C.WorkDetailWorkerSort.Name,C.WorkDetailWorkerSort.Category,C.WorkDetailWorkerSort.Profession,C.WorkDetailWorkerSort.Skills]
const DETAIL_SORT_X=[38,48,57,69]
const DETAIL_SORT_WIDTH=[10,9,10,20]
const DETAIL_SORT_LABELS=["Name","Cat","Prof",""]
# Native42b4e0 color dispatch (42bc4c/42bc18), categories-2 through-13.
const SETTINGS_COLORS=[14,15,2,5,6,1,8,10,9,12,3,7]
var name_entry
var name_target: int=-1
var detail_first:=0
var worker_selected: int=-1
var worker_sort: Array=[]
var settings_selected:=0
var showing_settings:=false
var right_keyboard_focus:=false
var detail_scrollbar
func roster_extent() -> float:return maxf(size.x,864)
func settings_top() -> int:return header_top()+36
func settings_capacity() -> int:return maxi(0,int((size.y-settings_top()-36)/36))
func settings_rect(index: int) -> Rect2:return Rect2(272,settings_top()+(index-state.settings_first)*36,size.x-312,36)
func done_rect() -> Rect2:return Rect2(264,header_top(),48,36)
func settings_action_rect() -> Rect2:return Rect2(size.x-(184 if state.settings.get("no_modify",false) else 104),header_top(),152 if state.settings.get("no_modify",false) else 72,36)
func configure_work_details(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root());picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var inset:=StyleBoxTexture.new();inset.texture=art.texture("BUTTON_FILTER")
	inset.set_texture_margin(SIDE_LEFT,8);inset.set_texture_margin(SIDE_RIGHT,32)
	for side in [SIDE_TOP,SIDE_BOTTOM]:inset.set_texture_margin(side,12)
	search=preload("res://scripts/area_owner_filter.gd").new();add_child(search)
	search.theme=theme;search.configure(inset,colors);search.edited.connect(state.set_query)
	name_entry=preload("res://scripts/area_name_entry.gd").new();add_child(name_entry)
	name_entry.theme=theme;name_entry.byte_limit=40;name_entry.size=Vector2(328,36)
	name_entry.add_theme_font_size_override("font_size",12);name_entry.add_theme_color_override("font_color",colors[15])
	name_entry.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;name_entry.mouse_filter=Control.MOUSE_FILTER_IGNORE
	name_entry.edited.connect(func(value):name_edited.emit(value);queue_redraw())
	name_entry.submitted.connect(func():name_finished.emit({}))
	name_entry.hide()

	scrollbar.row_changed.connect(func(value):
		if state.editing_settings:state.seek_settings(value,settings_capacity())
		else:state.seek(value,page_rows))
	scrollbar.input_allowed=allowed
	detail_scrollbar=preload("res://scripts/area_location_scrollbar.gd").new();add_child(detail_scrollbar);detail_scrollbar.configure(source)
	detail_scrollbar.input_allowed=allowed
	detail_scrollbar.row_changed.connect(func(value):detail_first=value;queue_redraw())
	state.changed.connect(refresh)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			if search.is_inside_tree():search.release_focus()
			_leave_hover())
	mouse_exited.connect(_leave_hover);refresh()
func name_rect() -> Rect2:return Rect2(272,header_top(),368,36)
func begin_name() -> void:
	name_target=int(state.selected.index);search.release_focus();name_entry.begin(state.selected.name);queue_redraw()
func finish_name() -> void:
	if name_entry!=null:name_entry.finish();queue_redraw()
func clear_name() -> void:
	finish_name();name_target=-1;queue_redraw()
func right_panel_rect() -> Rect2:return Rect2(264,header_top(),size.x-296,size.y-header_top()-24)
func _input(event: InputEvent) -> void:
	if allowed() and name_entry!=null and name_entry.editing:
		if event is InputEventKey and event.pressed and event.keycode!=KEY_ESCAPE:
			name_entry.feed_key(event);get_viewport().set_input_as_handled();return
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
			if not name_rect().has_point(point):
				var action:=click_action(point)
				if action.get("kind","")=="sort":
					action.retain_priorities=event.shift_pressed;action.remove_priority=event.ctrl_pressed
				name_finished.emit(action)
			get_viewport().set_input_as_handled();return
	if allowed() and state!=null:
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
			right_keyboard_focus=right_panel_rect().has_point(point)
		elif event is InputEventKey and event.pressed:
			# Native42e2e0 propagates this gate independently of textbox focus.
			if not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.shift_pressed and event.keycode in [KEY_LEFT,KEY_RIGHT]:
				right_keyboard_focus=event.keycode==KEY_RIGHT;get_viewport().set_input_as_handled();return
			if event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.shift_pressed and not event.echo and event.keycode==KEY_F and right_keyboard_focus and not state.editing_settings and state.phase==state.Phase.Ready and search!=null:
				search.grab_focus();get_viewport().set_input_as_handled();return
			if search!=null and search.has_focus() and not right_keyboard_focus and event.keycode!=KEY_ESCAPE:
				get_viewport().set_input_as_handled();return
	super._input(event)
func click_action(point: Vector2) -> Dictionary:
	if standing_orders_rect().has_point(point):return {"kind":"standing_orders"}
	if stone_use_rect().has_point(point):return {"kind":"stone_use"}
	if kitchen_rect().has_point(point):return {"kind":"kitchen"}
	if add_rect().has_point(point):return {"kind":"create"}
	for index in range(detail_first,mini(state.details.size(),detail_first+detail_capacity())):
		if detail_rect(index).has_point(point):return {"kind":"detail","index":index}
	for index in 3:
		if mode_rect(index).has_point(point):return {"kind":"mode","value":[1,3,2][index]}
	if Rect2(640,header_top(),32,36).has_point(point):return {"kind":"settings"}
	if search.get_rect().has_point(point):return {"kind":"search"}
	for index in 4:
		if Rect2(DETAIL_SORT_X[index]*8,list_top()-24,DETAIL_SORT_WIDTH[index]*8,12).has_point(point):return {"kind":"sort","value":DETAIL_SORTS[index]}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty():continue
		if member_rect(index).has_point(point):return {"kind":"member","id":int(row.id),"value":not row.member}
		if Rect2(720,list_top()+index*36,32,36).has_point(point):return {"kind":"specialize","id":int(row.id)}
	return {}
func dispatch_action(action: Dictionary) -> void:
	match action.get("kind",""):
		"standing_orders":standing_orders_requested.emit()
		"stone_use":stone_use_requested.emit()
		"kitchen":kitchen_requested.emit()
		"create":state.create_detail()
		"detail":state.select_detail(int(action.index))
		"mode":state.set_mode(int(action.value))
		"settings":state.open_settings()
		"search":search.grab_focus()
		"sort":state.select_sort(int(action.value),bool(action.get("retain_priorities",false)),bool(action.get("remove_priority",false)))
		"member":state.set_member(int(action.id),bool(action.value))
		"specialize":state.specialize(int(action.id))
func list_top() -> int:return 204 if wide_tabs else 228
func header_top() -> int:return list_top()-132
func standing_orders_rect() -> Rect2:return Rect2(136,header_top()-36,152,24)
func stone_use_rect() -> Rect2:return Rect2(376,header_top()-36,104,24)
func kitchen_rect() -> Rect2:return Rect2(288,header_top()-36,88,24)
func detail_top() -> int:return header_top()+36
func detail_capacity() -> int:return maxi(0,int((size.y-detail_top()-36)/36))
func detail_rect(index: int) -> Rect2:return Rect2(24,detail_top()+(index-detail_first)*36,224,36)
func add_rect() -> Rect2:return Rect2(24,header_top(),240,36)
func mode_rect(index: int) -> Rect2:
	return Rect2(size.x-528+[0,168,352][index],header_top()+60,[168,184,144][index],36)
func member_rect(index: int) -> Rect2:return Rect2(800,list_top()+index*36,32,36)
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	page_rows=maxi(0,int((size.y-list_top()-96)/36))
	if search!=null:search.position=Vector2(280,size.y-60);search.size=Vector2(312,36)
	if name_entry!=null:name_entry.position=Vector2(288,header_top())
	if scrollbar!=null:
		scrollbar.dragging=false
	detail_first=clampi(detail_first,0,maxi(0,(state.details.size() if state!=null else 0)-detail_capacity()))
	if detail_scrollbar!=null:detail_scrollbar.dragging=false
	if state!=null and state.capacity!=page_rows:state.seek(state.first,page_rows)
	refresh()
func refresh() -> void:
	if state==null:return
	var current_sort: Array=[state.priorities,state.directions]
	if current_sort!=worker_sort:
		# Native sort headers reset the cursor to the first newly ordered row.
		worker_selected=-1
		worker_sort=current_sort.duplicate(true)

	var retained: Dictionary={}
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or not row.has("sheet_icon"):continue
		var previous: Dictionary=portraits.get(int(row.id),{})
		retained[int(row.id)]=previous if previous.get("recipe",{})==row.sheet_icon else {"recipe":row.sheet_icon.duplicate(true),"texture":world.candidate_icon(row.sheet_icon)}
	portraits=retained
	if state.phase==state.Phase.Closed:worker_selected=-1;right_keyboard_focus=false
	elif state.roster_ready and not state.ids.has(worker_selected):
		worker_selected=int(state.ids[0]) if not state.ids.is_empty() else -1
	if showing_settings!=state.editing_settings:
		showing_settings=state.editing_settings;settings_selected=0;_leave_hover()
		if search!=null and search.is_inside_tree():search.release_focus()
		if scrollbar!=null:scrollbar.dragging=false
	if scrollbar!=null:
		scrollbar.position=Vector2(size.x-32 if showing_settings else roster_extent()-32,settings_top() if showing_settings else list_top())
		scrollbar.size=Vector2(16,maxi(36,size.y-scrollbar.position.y-(24 if showing_settings else 84)))
		scrollbar.page=settings_capacity() if showing_settings else page_rows
		if showing_settings and not state.settings.is_empty():
			var first:=clampi(state.settings_first,0,maxi(0,state.settings.get("catalog",[]).size()-settings_capacity()))
			if first!=state.settings_first:state.seek_settings(first,settings_capacity());return
		scrollbar.set_rows(state.settings.get("catalog",[]).size() if showing_settings else state.ids.size(),state.settings_first if showing_settings else state.first)
	if detail_scrollbar!=null:
		detail_scrollbar.position=Vector2(256,detail_top());detail_scrollbar.size=Vector2(16,maxi(36,size.y-detail_top()-24));detail_scrollbar.page=detail_capacity()
		detail_scrollbar.set_rows(state.details.size(),detail_first)
	if search!=null:search.visible=not showing_settings
	if search!=null:search.set_bytes(state.query);search.editable=allowed() and state.phase!=state.Phase.Applying
	queue_redraw()
func setting_icons(id: int,y: float) -> Array[Dictionary]:
	var entries: Array[Dictionary]=[]
	if id<0:return entries
	var x:=size.x-104
	for definition: Dictionary in state.details:
		if definition.get("labors",PackedInt32Array()).has(id) and int(definition.icon)>=0 and int(definition.icon)<Indicators.WORK_DETAILS.size():
			entries.append({"icon":int(definition.icon),"rect":Rect2(x,y,32,36)});x-=32
	return entries
func hover_target(point: Vector2) -> Dictionary:
	if state==null or state.phase!=state.Phase.Ready:return {}
	if state.editing_settings:
		var catalog: Array=state.settings.get("catalog",[])
		for index in range(state.settings_first,mini(catalog.size(),state.settings_first+settings_capacity())):
			for entry: Dictionary in setting_icons(int(catalog[index].id),settings_rect(index).position.y):
				if entry.rect.has_point(point):return {"staff":"work_detail"}
		return {}
	if search!=null and search.get_rect().has_point(point):return {"widget":"filter"}
	for index in 4:
		if Rect2(DETAIL_SORT_X[index]*8,list_top()-24,DETAIL_SORT_WIDTH[index]*8,12).has_point(point):
			return {"widget":["name","category","profession","skills"][index]}
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
func update_hover() -> void:
	if not is_instance_valid(hover_help):return
	var target: Dictionary=hover_target(pointer_position) if pointer_known and allowed() else {}
	if target.has("widget"):
		if target.widget=="filter":hover_help.enter_owner_filter(get_instance_id())
		else:hover_help.enter_work_detail_widget(get_instance_id(),target.widget)
		return
	# Widget overlays have independent ownership/timing; retire them before
	# entering a main-interface instruction, without resetting its warm timer.
	if hover_help.widget_owner==get_instance_id():hover_help.leave(get_instance_id())
	super.update_hover()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var step: int=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
		if event.position.x<264:detail_first=clampi(detail_first+step,0,maxi(0,state.details.size()-detail_capacity()));refresh()
		elif state.editing_settings:state.seek_settings(state.settings_first+step,settings_capacity())
		else:state.seek(state.first+step,page_rows)
		accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	search.release_focus();accept_event()
	var caption:=InfoTabs.caption_at(event.position,wide_tabs)
	if not caption.is_empty():
		if caption!="Labor":information_requested.emit(caption)
		return
	if standing_orders_rect().has_point(event.position):standing_orders_requested.emit();return
	if stone_use_rect().has_point(event.position):stone_use_requested.emit();return
	if kitchen_rect().has_point(event.position):kitchen_requested.emit();return
	if add_rect().has_point(event.position):state.create_detail();return
	for index in range(detail_first,mini(state.details.size(),detail_first+detail_capacity())):
		if detail_rect(index).has_point(event.position):state.select_detail(index);return
	if state.editing_settings:
		if done_rect().has_point(event.position):state.close_settings();return
		if settings_action_rect().has_point(event.position):
			if state.settings.get("no_modify",false):reset_requested.emit()
			else:delete_requested.emit()
			return
		for index in range(state.settings_first,mini(state.settings.get("catalog",[]).size(),state.settings_first+settings_capacity())):
			if settings_rect(index).has_point(event.position):settings_selected=index;state.toggle_setting(int(state.settings.catalog[index].id));queue_redraw();return
		return
	for index in 3:
		if mode_rect(index).has_point(event.position):state.set_mode([1,3,2][index]);return
	if Rect2(272,header_top(),368,36).has_point(event.position):rename_requested.emit();return
	if Rect2(640,header_top(),32,36).has_point(event.position):settings_requested.emit();return
	for index in 4:
		if Rect2(DETAIL_SORT_X[index]*8,list_top()-24,DETAIL_SORT_WIDTH[index]*8,12).has_point(event.position):state.select_sort(DETAIL_SORTS[index],event.shift_pressed,event.ctrl_pressed);return
	for index in page_rows:
		var row: Dictionary=state.row_at(state.first+index)
		if row.is_empty() or state.phase!=state.Phase.Ready:continue
		if Rect2(264,list_top()+index*36,roster_extent()-304,36).has_point(event.position):
			worker_selected=int(row.id);queue_redraw()
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
	if state.selected.is_empty():_draw_detail_names();return
	if state.editing_settings:_draw_settings();_draw_detail_names();return
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	if filter!=null:
		for y in 3:
			for cell in 42:draw_texture_rect_region(filter,Rect2(272+cell*8,header_top()+y*12,8,12),Rect2(0 if cell==0 else 8,y*12,8,12))
	var endcap: Texture2D=art.texture("BUTTON_FILTER_NAME")
	if endcap!=null:draw_texture_rect(endcap,Rect2(608,header_top(),32,36),false)
	if name_entry==null or not name_entry.editing:text(name_entry.value if name_target==int(state.selected.index) else state.selected.name,Vector2(288,header_top()+24),15,320)
	var settings: Texture2D=art.texture("LABOR_EDIT_WORK_DETAIL")
	if settings!=null:draw_texture_rect(settings,Rect2(640,header_top(),32,36),false)
	for index in 3:
		var rect:=mode_rect(index);var selected_mode: bool=int(state.selected.mode)==[1,3,2][index]
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if selected_mode else "BUTTON_CATEGORY_RECTANGLE",Vector2i(int(rect.position.x/8),int(rect.position.y/12)),int(rect.size.x/8),3)
		text(["Everybody does this","Only selected do this","Nobody does this"][index],rect.position+Vector2(8,24),8 if index==0 and state.selected.cannot_be_everybody else 15)
	for index in 4:
		var suffix: String="ACTIVE" if state.sort_active(DETAIL_SORTS[index]) else "INACTIVE"
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
		patch("BUTTON_RECTANGLE_SELECTED" if int(row.id)==worker_selected else "BUTTON_RECTANGLE_DARK",Vector2i(33,int(y/12)),int(roster_extent()/8)-38,3)
		patch("",Vector2i(33,int(y/12)),5,3,picture.texture(int(row.id)==worker_selected))
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

	_draw_detail_names()

func _draw_detail_names() -> void:
	# Native captions update immediately and may overdraw the roster. Keep
	# their unbounded width and late drawing order; no clipping exception exists.
	for index in range(detail_first,mini(state.details.size(),detail_first+detail_capacity())):
		var row: Dictionary=state.details[index]
		text(name_entry.value if name_target==int(row.index) else row.name,detail_rect(index).position+Vector2(48,24),15)

func _draw_settings() -> void:
	patch("HORIZONTAL_OPTION_ACTIVE",Vector2i(33,int(header_top()/12)),6,3);text("Done",Vector2(272,header_top()+24),10)
	if state.settings.is_empty():return
	var action:=settings_action_rect()
	patch("HORIZONTAL_OPTION_REMOVE",Vector2i(int(action.position.x/8),int(header_top()/12)),int(action.size.x/8),3)
	text("Reset to default" if state.settings.no_modify else "Delete",action.position+Vector2(8,24),15)
	var catalog: Array=state.settings.catalog;var labors: PackedInt32Array=state.settings.labors
	var category: int=-2
	for index in catalog.size():
		var entry: Dictionary=catalog[index];var id:=int(entry.id)
		if id<0:category=id
		if index<state.settings_first or index>=state.settings_first+settings_capacity():continue
		var rect:=settings_rect(index)
		patch("BUTTON_RECTANGLE_SELECTED" if index==settings_selected else "BUTTON_RECTANGLE",Vector2i(34,int(rect.position.y/12)),int(rect.size.x/8),3)
		text(entry.caption,rect.position+Vector2(16 if id<0 else 24,24),SETTINGS_COLORS[-category-2],rect.size.x-88)
		var checked:=labors.has(id)
		if id<0:
			checked=true
			for next in range(index+1,catalog.size()):
				if int(catalog[next].id)<0:break
				if not labors.has(int(catalog[next].id)):checked=false;break
		else:
			for badge: Dictionary in setting_icons(id,rect.position.y):
				var icon: Texture2D=art.texture("WORK_DETAIL_"+Indicators.WORK_DETAILS[badge.icon])
				if icon!=null:draw_texture_rect(icon,badge.rect,false)
		var checkbox: Texture2D=art.texture("LABOR_WORKER_ASSIGNED" if checked else "LABOR_WORKER_UNASSIGNED")
		# Native replaces this checkbox cell's backing, including its transparent
		# bottom edge; the other cells retain the surrounding row border.
		draw_rect(Rect2(size.x-56,rect.position.y+24,8,12),Color8(28,28,28))
		if checkbox!=null:draw_texture_rect(checkbox,Rect2(size.x-72,rect.position.y,32,36),false)
