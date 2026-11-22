extends "res://scripts/residents_view.gd"
# Native trainer/knowledge pane geometry: protected094804 and093702.
# These components remain staged until their complete roster route is qualified.
signal tab_requested(index: int)
const GENERIC_LABELS={C.PetTrainerMode.Any:"Any trainer",C.PetTrainerMode.Unassigned:"Any unassigned trainer",C.PetTrainerMode.None:"None"}
var displayed: Array=[]

func configure_pets(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root());picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP;state.changed.connect(refresh)
	scrollbar.input_allowed=allowed
	scrollbar.row_changed.connect(func(value):state.seek(value,visible_count(value)))
	refresh()
func is_trainers() -> bool:return state!=null and state.pane==state.Pane.Trainers
func content_top() -> int:return list_top()-12 if is_trainers() else list_top()
func content_bottom() -> int:return int(size.y)-24 if is_trainers() else int(size.y)-84
func step_at(index: int) -> int:return 36 if is_trainers() and index<3 else 48
func visible_count(first: int) -> int:
	var y:=content_top();var count:=0
	while count<64 and y+step_at(first+count)<=content_bottom():
		y+=step_at(first+count);count+=1
	return maxi(1,count)
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	if scrollbar!=null:scrollbar.dragging=false
	if state!=null:state.seek(state.first,visible_count(state.first))
	refresh()
func refresh() -> void:
	if state==null:return
	displayed=[];var retained: Dictionary={};var y:=content_top()
	for index in range(state.first,mini(maxi(0,state.total),state.first+visible_count(state.first))):
		var row: Dictionary=state.row_at(index);displayed.append({"index":index,"y":y,"row":row})
		if row.has("portrait"):
			var key: String=("unit:"+str(row.id)) if is_trainers() else ("race:"+str(row.race))
			var previous: Dictionary=portraits.get(key,{})
			retained[key]=previous if previous.get("recipe",{})==row.portrait else {"recipe":row.portrait.duplicate(true),"texture":world.candidate_icon(row.portrait)}
		y+=step_at(index)
	portraits=retained
	if scrollbar!=null:
		scrollbar.position=Vector2(size.x-(32 if is_trainers() else 40),content_top())
		scrollbar.size=Vector2(16,maxi(36,content_bottom()-content_top()));scrollbar.page=visible_count(state.first)
		scrollbar.set_rows(maxi(0,state.total),state.first)
	queue_redraw()
func _process(_delta: float) -> void:
	if not is_visible_in_tree() or state==null:return
	for row: Dictionary in state.rows.values():
		if row.get("name_color",{}).get("effect",0)!=0:queue_redraw();break
func _input(event: InputEvent) -> void:
	if not allowed():return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or state==null or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var first: int=state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)
		state.seek(first,visible_count(maxi(0,first)));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var caption:=InfoTabs.caption_at(event.position,wide_tabs)
	if not caption.is_empty():
		if caption!="Creatures":information_requested.emit(caption)
		accept_event();return
	var creature_tab:=creature_tab_at(event.position)
	if creature_tab>=0:tab_requested.emit(creature_tab);accept_event();return
	if is_trainers() and state.phase==state.Phase.Ready:
		for entry: Dictionary in displayed:
			if not Rect2(16,entry.y,size.x-56,step_at(entry.index)).has_point(event.position):continue
			var row: Dictionary=entry.row
			if row.has("mode"):state.select_trainer(int(row.mode))
			elif row.has("id"):state.select_trainer(C.PetTrainerMode.Individual,int(row.id))
			break
	accept_event()
func row_background(origin: Vector2i,columns: int) -> void:
	# Native094804/093702 use texture columns0/2/1 for left/fill/right,
	# unlike the generic frame helper's0/1/2 ordering.
	var texture: Texture2D=art.texture("BUTTON_RECTANGLE")
	if texture==null:return
	for y in 3:
		for x in columns:
			draw_texture_rect_region(texture,Rect2((origin.x+x)*8,(origin.y+y)*12,8,12),Rect2((0 if x==0 else 8 if x==columns-1 else 16),y*12,8,12))
func _draw() -> void:
	if world==null or state==null:return
	draw_chrome(1)
	if is_trainers():text(str(state.snapshot.get("header","")),Vector2(16,list_top()-12))
	for entry: Dictionary in displayed:
		var row: Dictionary=entry.row;var y:=int(entry.y)
		if row.is_empty():continue
		if row.has("mode"):
			text(GENERIC_LABELS[row.mode],Vector2(48,y+24));continue
		var x:=16 if is_trainers() else 32
		row_background(Vector2i(x/8,y/12),int(size.x/8)-7 if is_trainers() else 50)
		patch("",Vector2i(x/8,y/12),5,3,picture.texture(false))
		var key: String=("unit:"+str(row.id)) if is_trainers() else ("race:"+str(row.race))
		var portrait: Texture2D=portraits.get(key,{}).get("texture")
		if portrait!=null:draw_texture_rect(portrait,Rect2(x+2,y+2,32,32),false)
		if is_trainers():
			var ink:=NameColor.choose(row.name_color,ticks_override if ticks_override>=0 else Time.get_ticks_msec(),0 if ticks_override>=0 else randi_range(0,1))
			var warning: Dictionary=row.get("name_warning",{})
			# Native1423d0f/1423d39 shifts split names for the grazer line;
			# the fitting combined-name branch1423d52 retains its baseline.
			var shift:=12 if not warning.is_empty() and not str(row.second_line).is_empty() else 0
			if not ink.is_empty():
				text(row.first_line,Vector2(56,y+12-shift),int(ink[0])+8*int(ink[2]),240)
				text(row.second_line,Vector2(56,y+24-shift),int(ink[0])+8*int(ink[2]),240)
			if not warning.is_empty():text(warning.text,Vector2(64,y+24),int(warning.foreground)+8*int(warning.bright))
			for index in row.skills.size():text(row.skills[index],Vector2(296,y+24+index*12))
		else:
			text(row.name,Vector2(80,y+24))
			text(row.knowledge.text,Vector2(280,y+24),int(row.knowledge.foreground)+8*int(row.knowledge.bright))
