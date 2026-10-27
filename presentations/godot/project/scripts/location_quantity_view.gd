extends Control
# Native quantity rows; local keyboard draft, semantic writes through the workflow.
const Body=preload("res://scripts/location_details_body.gd")
const Format=preload("res://scripts/location_details_format.gd")
const C=preload("res://scripts/management_contract.gd")
const ICONS=["ARENA_ENTER_AMOUNT","WORK_ORDERS_INCREASE_AMOUNT","WORK_ORDERS_DECREASE_AMOUNT"]
const FIELDS={1:{17:0,20:1},2:{23:1},3:{20:10,26:2},5:{20:4,23:5,26:3,29:6,32:7,35:8,38:9}}
var art=preload("res://scripts/original_ui.gd").new()
var workflow=preload("res://scripts/location_quantity_workflow.gd").new()
var rows: Array=[]
var details
var actions_enabled:=true
var input_allowed: Callable

func configure(source,model) -> void:
	art.configure(source);theme=art.theme;details=model
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	workflow.configure(model);workflow.changed.connect(refresh)
	details.changed.connect(refresh);refresh()

func layout(view: Vector2) -> void:
	position=Vector2(384,60+fposmod(view.y,12)*0.5)
	size=Vector2(floori(view.x/8)*8-624,floori(view.y/12)*12-156)
	queue_redraw()

func refresh() -> void:
	rows=[]
	if details==null:return
	var fields: Dictionary=FIELDS.get(int(details.snapshot.get("kind",0)),{})
	for row in Body.content(details.snapshot):
		if fields.has(int(row.y)):
			row.quantity=fields[int(row.y)];rows.append(row)
	queue_redraw()

func button_rect(row: Dictionary, action: int) -> Rect2:
	var left:=352 if int(details.snapshot.get("kind",0)) in [1,2] else 320
	return Rect2(left+action*32,(int(row.y)-6)*12,32,36)

func _has_point(point: Vector2) -> bool:
	for row in rows:
		for action in 3:
			if button_rect(row,action).has_point(point):return true
	return false

func _gui_input(event: InputEvent) -> void:
	if not actions_enabled or (input_allowed.is_valid() and not input_allowed.call()) or not workflow.available() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for row in rows:
		for action in 3:
			if button_rect(row,action).has_point(event.position):
				if action==0:workflow.begin(int(row.quantity))
				else:workflow.step(int(row.quantity),action)
				accept_event();return

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not actions_enabled or (input_allowed.is_valid() and not input_allowed.call()) or workflow.editing<0 or not workflow.available() or not event is InputEventKey or not event.pressed:return
	# Physical Escape belongs to the surrounding Options/Details route.
	if event.keycode==KEY_ESCAPE:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:workflow.finish()
	elif event.keycode==KEY_BACKSPACE:workflow.type_text(workflow.text.left(-1))
	elif event.unicode>=48 and event.unicode<=57:workflow.type_text(workflow.text+String.chr(event.unicode))
	get_viewport().set_input_as_handled()

func displayed_value(row: Dictionary) -> String:
	if workflow.editing!=int(row.quantity):return str(row.value)
	var draft: String=workflow.text+"_"
	if int(row.quantity)==10:return draft
	for supply in details.snapshot.get("supplies",[]):
		if int(supply.kind)==int(row.quantity):return str(Format.supply_quantity(supply.stored,int(row.quantity),false))+" ("+draft+")"
	return str(row.value)

func _draw() -> void:
	if theme==null:return
	var font: Font=theme.default_font
	var background: Texture2D=art.texture("BUTTON_RECTANGLE")
	var columns:=int(size.x/8)
	for row in rows:
		var top:=Vector2(0,(int(row.y)-6)*12)
		if background!=null:
			for y in 3:
				for x in columns:
					draw_texture_rect_region(background,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2((0 if x==0 else 16 if x==columns-1 else 8),y*12,8,12))
		for action in 3:
			var texture: Texture2D=art.texture(ICONS[action])
			if texture!=null:draw_texture_rect(texture,button_rect(row,action),false)
		if font==null:continue
		var point:=Vector2((int(row.x)-48)*8,(int(row.y)-5)*12+12)
		font.draw_string(get_canvas_item(),point,str(row.caption),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Body.GRAY)
		point.x+=str(row.caption).length()*8
		font.draw_string(get_canvas_item(),point,displayed_value(row),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func _exit_tree() -> void:
	if details!=null and details.changed.is_connected(refresh):details.changed.disconnect(refresh)
	if workflow.changed.is_connected(refresh):workflow.changed.disconnect(refresh)
	workflow.dispose()
