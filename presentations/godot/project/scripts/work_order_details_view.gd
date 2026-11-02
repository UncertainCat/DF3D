extends "res://scripts/location_staff_candidates_frame.gd"
# Native Details renderer2143b0; workshop reference232341. Other option
# families and global/responsive geometry remain staged.
signal cancelled
var state
var input_allowed: Callable
var colors: Array[Color]=[]
var search_focused:=false
var blink:=false
var quantity_focused:=false
func configure_details(source,model) -> void:
	super.configure(source);state=model;colors=art.installed_palette(source.assets_root())
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():if state!=null:state.hover_art(-1,0))
	scrollbar.row_changed.connect(func(value):state.seek(value))
	scrollbar.input_allowed=func():return state.phase==state.Phase.Ready and (not input_allowed.is_valid() or input_allowed.call())
	state.changed.connect(func():
		if state.phase==state.Phase.Closed:search_focused=false;hide()
		if state.snapshot.get("selected_option",-1)<0:search_focused=false
		if state.has_art() and state.art_page()<0:search_focused=false
		sync_scroll();queue_redraw())
func open(building: int,order: int) -> void:
	state.open(building,order);show();queue_redraw()
func layout(view: Vector2) -> void:
	var global: bool=state!=null and (state.building_id==-2 or state.has_art())
	var rows_count:=maxi(13,floori(view.y/12)-(5 if global else 10))
	var origin:=Vector2(16 if global else 72,(36 if global else 48)+fposmod(view.y,12)*0.5)
	var width:=976 if global else 832
	if position==origin and size==Vector2(width,rows_count*12):return
	state.hover_art(-1,0)
	position=origin;frame_rows=rows_count;size=Vector2(width,frame_rows*12);sync_scroll();queue_redraw()
func selected_kind() -> int:
	var selected: int=state.snapshot.get("selected_option",-1) if state!=null else -1
	return int(state.snapshot.options[selected].kind) if selected>=0 else -1
func list_top() -> int:
	if state!=null and state.has_art() and state.art_page()==17:return 96
	if state!=null and state.has_art():return 132 if state.art_page()>=0 else 96
	return 84 if selected_kind()==3 else 120
func sync_scroll() -> void:
	if state==null or scrollbar==null:return
	page_rows=maxi(1,int((size.y-list_top()-(96 if state.has_art() and state.art_page()>=6 else 60 if state.has_art() and state.art_page()==5 else 24))/36))
	state.draft_columns=maxi(1,int((size.x-32)/8))
	state.visible_rows=page_rows
	scrollbar.position=Vector2(size.x-32,list_top());scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	if state.has_art():
		if state.art_page()>=0 and state.art_page()!=6:scrollbar.set_rows(state.snapshot.art.total,state.first)
		else:scrollbar.hide()
	elif state.snapshot.get("selected_option",-1)>=0:scrollbar.set_rows(state.rows.size(),state.first)
	else:scrollbar.hide()
func back() -> void:
	if state.ticket!=0:return
	if state.has_art():
		search_focused=false;quantity_focused=false
		if state.art_page()>=0:state.art_back()
		else:cancelled.emit()
		return
	if state.snapshot.get("selected_option",-1)>=0:state.read_root()
	else:cancelled.emit()
func _process(_delta: float) -> void:
	var value:=Time.get_ticks_msec()%1000<500
	if (search_focused or quantity_focused) and value!=blink:blink=value;queue_redraw()
func feed_search(event: InputEventKey) -> void:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:search_focused=false;queue_redraw();return
	var value: String=state.query
	if event.keycode==KEY_BACKSPACE:value=value.left(maxi(0,value.length()-1))
	elif event.unicode>=32:
		# Native8b9c67/8b9d03: capacity20, flags0x17, raw text bytes.
		for byte in String.chr(event.unicode).to_utf8_buffer():
			if value.length()>=(60 if state.has_art() else 20):break
			value+=String.chr(byte if byte<128 else art.CP437_HIGH[byte-128])
	state.set_query(value)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (input_allowed.is_valid() and not input_allowed.call()):return
	# Artwork's native Back route is right-click; Escape does not leave it.
	if state.has_art() and event is InputEventKey and event.keycode==KEY_ESCAPE:get_viewport().set_input_as_handled();return
	if quantity_focused and event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:quantity_focused=false
		elif event.keycode==KEY_BACKSPACE:state.draft_quantity=int(str(state.draft_quantity).left(-1))
		elif event.unicode>=48 and event.unicode<=57:state.draft_quantity=mini(1000000000,int(str(state.draft_quantity)+String.chr(event.unicode)))
		queue_redraw();get_viewport().set_input_as_handled();return
	if search_focused and event is InputEventKey and event.keycode!=KEY_ESCAPE:
		feed_search(event);get_viewport().set_input_as_handled();return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		back();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if input_allowed.is_valid() and not input_allowed.call():return
	if event is InputEventMouseMotion and state.phase==state.Phase.Ready and state.has_art() and state.art_page()==5:
		var id: int=-1
		if Rect2(16,list_top(),size.x-48,page_rows*36).has_point(event.position):
			var index: int=int((event.position.y-list_top())/36)+state.first-state.row_base()
			if index>=0 and index<state.rows.size():id=state.rows[index].id
		state.hover_art(id,int((size.x-32)/8));return
	if state.phase!=state.Phase.Ready or not event is InputEventMouseButton or not event.pressed:return
	if state.has_art() and state.art_page()>=6:
		draft_input(event);return
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected>=0 and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var searching: bool=(state.has_art() and state.art_page()>=0) or (not state.has_art() and selected_kind() in [0,6])
	if searching and Rect2(16,96 if state.has_art() else 84,size.x-32,36).has_point(event.position):
		search_focused=not search_focused;queue_redraw();accept_event();return
	var top:=list_top() if selected>=0 else 48
	if not Rect2(16,top,size.x-48,size.y-top-24).has_point(event.position):return
	var index:=int((event.position.y-top)/36)
	if selected>=0:
		if state.has_art() and state.art_page()<0 and event.position.x>=360:return
		index+=state.first-state.row_base()
		if index<state.rows.size():state.choose(state.rows[index].id)
	elif index<state.snapshot.get("options",[]).size():state.select_option(index)
	accept_event()
func text(value: String,point: Vector2,color:=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point+Vector2(0,4),value,HORIZONTAL_ALIGNMENT_LEFT,size.x-point.x-16,12,colors[color] if colors.size()>color else Color.WHITE)
func _draw() -> void:
	if world==null or state==null:return
	patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	if state.snapshot.is_empty():return
	if state.has_art():draw_art();return
	text(state.snapshot.get("caption",""),Vector2(16,32))
	var selected: int=state.snapshot.get("selected_option",-1)
	if selected<0:
		for index in state.snapshot.options.size():text(state.snapshot.options[index].caption,Vector2(16,68+index*36))
		return
	var kind: int=state.snapshot.options[selected].kind
	# Captured native setting headings for the two wired semantic families.
	if kind in [0,6]:text("Setting material" if kind==0 else "Setting plant",Vector2(16,68))
	if kind==3:text("Setting type",Vector2(16,68)) # Native literal1615920.
	if kind in [0,6]:
		var filter: Texture2D=art.texture("BUTTON_FILTER")
		var columns:=int((size.x-32)/8)
		if filter!=null:
			for y in 3:
				for x in columns:
					var sx:=0 if x==0 else x-columns+6 if x>=columns-4 else 1
					draw_texture_rect_region(filter,Rect2(16+x*8,84+y*12,8,12),Rect2(sx*8,y*12,8,12))
		text(state.query+("_" if search_focused and blink else "") if search_focused or not state.query.is_empty() else "...",Vector2(32,104),15 if search_focused or not state.query.is_empty() else 8)
	for index in mini(page_rows,state.rows.size()-state.first):
		var row: Dictionary=state.rows[state.first+index]
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,int(list_top()/12)+index*3),int((size.x-32)/8)-(2 if scrollbar.visible else 0),3)
		text(row.caption,Vector2(16,list_top()+20+index*36))
		if row.has("count_caption"):text(row.count_caption,Vector2(size.x-(32 if scrollbar.visible else 16)-str(row.count_caption).length()*8,list_top()+20+index*36),13 if row.get("estimated",false) else 14)
func draw_art() -> void:
	var caption: String=state.snapshot.art.caption
	text(caption,Vector2(maxf(16,(size.x-caption.length()*8)*0.5),20))
	if state.art_page()>=6:draw_draft();return
	if state.art_page()<0:
		for index in state.rows.size():
			patch("BUTTON_CATEGORY_RECTANGLE_ON",Vector2i(2,8+index*3),43,3)
			text(state.rows[index].caption,Vector2(24,116+index*36))
		return
	var filter: Texture2D=art.texture("BUTTON_FILTER")
	var columns:=int((size.x-32)/8)
	if filter!=null:
		for y in 3:
			for x in columns:
				var sx:=0 if x==0 else x-columns+6 if x>=columns-4 else 1
				draw_texture_rect_region(filter,Rect2(16+x*8,96+y*12,8,12),Rect2(sx*8,y*12,8,12))
	text(state.query+("_" if search_focused and blink else "") if search_focused or not state.query.is_empty() else "...",Vector2(32,116),15 if search_focused or not state.query.is_empty() else 8)
	var offset: int=state.first-state.row_base()
	for index in mini(page_rows,state.rows.size()-offset):
		var row: Dictionary=state.rows[offset+index]
		var width:=columns-(2 if scrollbar.visible else 0)
		patch("BUTTON_RECTANGLE_DARK",Vector2i(2,11+index*3),width,3)
		var label: String=row.caption
		if label.length()>width-2:label=label.left(maxi(0,width-5))+"..."
		text(label,Vector2(16,152+index*36),11)
		if row.has("badge"):text(row.badge,Vector2(size.x-24-21*8-(16 if scrollbar.visible else 0),152+index*36),14)
	for index in mini(3,state.preview_lines.size()):text(state.preview_lines[index],Vector2(16,size.y-52+index*12),14)

# Native artwork editor200070; layout and captions captured in011836.
const DRAFT_CATEGORIES=[
	[7,"Creature",Vector2i(2,8)],[8,"Historical figure",Vector2i(2,11)],
	[9,"Plant",Vector2i(2,14)],[10,"Tree",Vector2i(10,14)],
	[11,"Shape",Vector2i(2,17)],[12,"Object",Vector2i(10,17)],
	[13,"Artifact",Vector2i(2,20)],[14,"Action or relationship",Vector2i(2,23)],
	[17,"Delete element",Vector2i(2,26)]]
func draft_button(label: String,cell: Vector2i,enabled:=true,red:=false,selected:=false) -> Rect2:
	var token:="BUTTON_CATEGORY_RECTANGLE" if not enabled else "BUTTON_CATEGORY_RECTANGLE_OFF" if red else "BUTTON_CATEGORY_RECTANGLE_ON"
	if selected and enabled:token+="_SELECTED"
	patch(token,cell,label.length()+2,3)
	text(label,Vector2(cell.x*8+8,cell.y*12+20))
	return Rect2(cell.x*8,cell.y*12,(label.length()+2)*8,36)
func draft_enabled(id: int) -> bool:
	return id not in [14,17] or not state.draft_value.elements.is_empty()
func draw_draft() -> void:
	var page: int=state.art_page()
	var description: Array=state.snapshot.art.get("draft_description",[])
	for i in mini(2,description.size()):text(description[i],Vector2(16,80+i*12),14)
	for category in DRAFT_CATEGORIES:draft_button(category[1],category[2],draft_enabled(category[0]),category[0]==17,page==category[0])
	if page==6:
		# The component name editor remains staged; Done uses the native draft name.
		draft_button("Name",Vector2i(2,30),false)
		draft_button("Done",Vector2i(9,30),not state.draft_value.elements.is_empty() and state.draft_value.has("name"))
		draft_button("Back",Vector2i(16,30),true,true)
	else:draft_button("Stop deleting" if page==17 else "Cancel",Vector2i(2,30),true,true)
	if page>=7 and page<=14:
		patch("BUTTON_RECTANGLE",Vector2i(29,8),int((size.x-248)/8),3)
		text(state.query+("_" if search_focused and blink else "") if search_focused or not state.query.is_empty() else "...",Vector2(248,116),15 if search_focused else 8)
	elif page in [15,16]:text(("Choose X: " if page==15 else "Choose Y: ")+state.draft_relation_caption,Vector2(232,116))
	if page!=6:
		var offset: int=state.first-state.row_base()
		var width:=int((size.x-248)/8)-(2 if scrollbar.visible else 0)
		for i in mini(page_rows,state.rows.size()-offset):
			var row: Dictionary=state.rows[offset+i]
			patch("BUTTON_RECTANGLE_DARK",Vector2i(29,int(list_top()/12)+i*3),width,3)
			var label: String=row.caption
			if label.length()>width-2:label=label.left(maxi(0,width-5))+"..."
			text(label,Vector2(232,list_top()+20+i*36),11)
			if page==17:
				var remove: Texture2D=art.texture("BUILDING_JOBS_REMOVE")
				if remove!=null:draw_texture_rect(remove,Rect2(size.x-48,list_top()+i*36,32,36),false)
	if page>=7 and page<=13:
		text("Number:",Vector2(232,size.y-28))
		patch("BUTTON_RECTANGLE",Vector2i(37,int(size.y/12)-4),int((size.x-392)/8),3)
		text(str(state.draft_quantity)+("_" if quantity_focused and blink else ""),Vector2(312,size.y-28))
		text("(0 for unnumbered plural)",Vector2(size.x-328,size.y-28))
		for entry in [["BUTTON_ADD",size.x-80],["BUTTON_SUBTRACT",size.x-48]]:
			var texture: Texture2D=art.texture(entry[0])
			if texture!=null:draw_texture_rect(texture,Rect2(entry[1],size.y-48,32,36),false)
	if state.draft_discard:
		patch("HOVER_RECTANGLE",Vector2i(20,18),80,15)
		text("Any image data you've changed will be lost.",Vector2(176,244))
		draft_button("Keep working",Vector2i(22,22))
		draft_button("Leave editor and discard data",Vector2i(22,26),true,true)
func draft_input(event: InputEventMouseButton) -> void:
	if state.draft_discard:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if Rect2(176,264,112,36).has_point(event.position):state.draft_discard=false;queue_redraw()
			elif Rect2(176,312,248,36).has_point(event.position):state.discard_draft()
		accept_event();return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if state.art_page()!=6:scrollbar.move_to(state.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	for category in DRAFT_CATEGORIES:
		var cell: Vector2i=category[2]
		if Rect2(cell.x*8,cell.y*12,(category[1].length()+2)*8,36).has_point(event.position):
			if draft_enabled(category[0]):search_focused=false;quantity_focused=false;state.draft_navigate(category[0])
			accept_event();return
	var page: int=state.art_page()
	if page==6 and Rect2(72,360,48,36).has_point(event.position):state.commit_draft();accept_event();return
	if (Rect2(128,360,48,36) if page==6 else Rect2(16,360,120,36)).has_point(event.position):back();accept_event();return
	if page>=7 and page<=14 and Rect2(232,96,size.x-248,36).has_point(event.position):
		quantity_focused=false;search_focused=not search_focused;queue_redraw();accept_event();return
	if page>=7 and page<=13 and event.position.y>=size.y-48 and event.position.y<size.y-12:
		search_focused=false
		if event.position.x>=size.x-48:state.draft_quantity=maxi(0,state.draft_quantity-1)
		elif event.position.x>=size.x-80:state.draft_quantity=mini(1000000000,state.draft_quantity+1)
		elif event.position.x>=296:quantity_focused=not quantity_focused
		queue_redraw();accept_event();return
	if page!=6 and Rect2(232,list_top(),size.x-248,page_rows*36).has_point(event.position):
		if page==17 and event.position.x<size.x-48:return
		var index: int=int((event.position.y-list_top())/36)+state.first-state.row_base()
		if index>=0 and index<state.rows.size():
			search_focused=false;quantity_focused=false;state.choose_draft(state.rows[index])
		accept_event()
