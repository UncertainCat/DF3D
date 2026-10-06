extends Control
# Native201709 permission bar. Full Details route/layout remains a separate owner.
const ICONS = ["VISITORS","RESIDENTS","CITIZENS","MEMBERS"]
const LABELS = ["All visitors welcome","Citizens and long-term residents only","Citizens only","Only members can visit"]
const GREEN := Color8(19,253,101)
const WHITE := Color8(255,255,255)
const YELLOW := Color8(255,225,17)
var art = preload("res://scripts/original_ui.gd").new()
var state
var hover_help
var buttons: Array[Button] = []
var current: Dictionary = {}

func configure(source, model, help=null) -> void:
	state=model;hover_help=help;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(576,36)
	for mode in 4:
		var button:=Button.new();button.position=Vector2(mode*32,0);button.size=Vector2(32,36)
		button.focus_mode=Control.FOCUS_NONE
		for key in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(key,StyleBoxEmpty.new())
		var icon:=TextureRect.new();icon.name="Icon";icon.size=Vector2(32,36)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(icon);button.pressed.connect(_choose.bind(mode));add_child(button);buttons.append(button)
		if hover_help!=null:
			button.mouse_entered.connect(func(): hover_help.enter_access(button.get_instance_id(),mode))
			# A neighboring button enters during the same input dispatch. Defer the
			# old owner's leave so that transition preserves the native cold timer.
			button.mouse_exited.connect(func(): hover_help.leave.call_deferred(button.get_instance_id()))
	state.changed.connect(refresh);refresh()

func _choose(mode: int) -> void:
	if not buttons[mode].disabled and buttons[mode].visible: state.set_access(mode)

static func content(details: Dictionary) -> Dictionary:
	if typeof(details.get("kind"))!=TYPE_INT or int(details.kind) not in [1,2,3,4,5]: return {}
	for key in ["visitors","residents","members"]:
		if typeof(details.get(key))!=TYPE_BOOL: return {}
	var selected:=3 if details.members else 0 if details.visitors else 1 if details.residents else 2
	var count:=4 if int(details.kind) in [2,4] else 3
	var label: String=LABELS[selected]
	if selected==3 and int(details.kind)==4: label+=" (if guild established)"
	var icons: Array=[]
	for mode in count: icons.append("LOCATION_PERMISSION_"+("ON_" if mode==selected else "OFF_")+ICONS[mode])
	return {"icons":icons,"selected":selected,"label":label,"label_x":count*32+16,
		"color":YELLOW if selected==2 else WHITE if selected==1 else GREEN}

func refresh() -> void:
	current=content(state.snapshot)
	visible=not current.is_empty()
	for mode in buttons.size():
		var button:=buttons[mode]
		button.visible=not current.is_empty() and mode<current.icons.size()
		if not button.visible and is_instance_valid(hover_help): hover_help.leave(button.get_instance_id())
		button.disabled=state.phase!=state.Phase.Ready or state.ticket!=0
		if button.visible: button.get_node("Icon").texture=art.texture(current.icons[mode])
	queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(hover_help):
		for button in buttons: hover_help.leave(button.get_instance_id())

func _draw() -> void:
	if current.is_empty() or theme==null or theme.default_font==null: return
	theme.default_font.draw_string(get_canvas_item(),Vector2(current.label_x,24),current.label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,current.color)
