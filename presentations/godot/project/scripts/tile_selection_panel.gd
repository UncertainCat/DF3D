extends Node
# Staged selection composition. Detail controllers keep their own action state;
# the navigation owner retains the tile receipt across confirmed handoffs.
const C=preload("res://scripts/management_contract.gd")
const Preferences=preload("res://scripts/presentation_settings.gd")
var navigation=preload("res://scripts/tile_selection_navigation.gd").new()
var ui_host
var world
var destination: Callable
var canvas: CanvasLayer
var panel: Panel
var body
var tabs
var play_enabled:=true
var modal_input:=false
var right_down:=false
var right_travel:=0.0

func configure(source,service,host,route: Callable) -> void:
	world=source;ui_host=host;destination=route
	navigation.configure(service,host,_route)
	canvas=CanvasLayer.new();canvas.layer=6;add_child(canvas)
	panel=Panel.new();canvas.add_child(panel);panel.mouse_filter=Control.MOUSE_FILTER_STOP
	var art=preload("res://scripts/original_ui.gd").new();art.configure(world)
	var border=art.make_style("HOVER_RECTANGLE",8)
	border.set_texture_margin(SIDE_TOP,12);border.set_texture_margin(SIDE_BOTTOM,12)
	panel.add_theme_stylebox_override("panel",border);panel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body=preload("res://scripts/tile_selection_group_view.gd").new();panel.add_child(body);body.configure(world,navigation.state)
	body.input_allowed=func():return ui_host.allows_panel_input(self)
	tabs=preload("res://scripts/tile_selection_tabs.gd").new();canvas.add_child(tabs);tabs.configure(world)
	tabs.input_allowed=_allows_tabs;tabs.alternative_requested.connect(navigation.state.choose_alternative)
	navigation.state.changed.connect(_refresh)
	ui_host.register(self);_refresh();_process(0)

func open_tile(tile: Vector3i) -> void:navigation.open(tile)

func _route(kind: int,id: int,tile: Vector3i):
	if kind in [C.SelectionKind.ItemList,C.SelectionKind.UnitList]:
		if not ui_host.activate(self):return null
		panel.show();return self
	return destination.call(kind,id,tile) if destination.is_valid() else null

func _allows_tabs() -> bool:
	return play_enabled and not ui_host.overlay_blocked and navigation.owner!=null and navigation.owner.get_ref()==ui_host.active

func _refresh() -> void:
	var state=navigation.state
	var images: Array=[]
	for target in state.snapshot.get("alternatives",[]):
		# Reuse semantic selection artwork; groups deliberately have no object
		# icon. Missing streamed appearance stays blank until qualified.
		images.append(_alternative_icon(target))
	tabs.set_selection(state.snapshot,images)
	tabs.enabled=state.phase==state.Phase.Ready and state.ticket==0
	if state.snapshot.is_empty():
		panel.hide()
		if ui_host.active==self:ui_host.release(self)

func _alternative_icon(target: Dictionary):
	if target.kind==C.SelectionKind.Building:
		var building: Dictionary=world.inspect_entity(3,target.id)
		# Native floodgate tabs use the fixed UI icon, not the material-colored
		# open/closed terrain sprite returned by selection_icon.
		if building.get("building_kind",0)==10:return world.ui_texture("BUILDING_ICON_FLOODGATE")
	return world.selection_icon(target.kind,target.id) if target.kind in [C.SelectionKind.Unit,C.SelectionKind.Item,C.SelectionKind.Building] else null

func close_panel() -> void:
	panel.hide();ui_host.release(self);cancel_gesture()
func handle_escape() -> void:close_panel()
func cancel_gesture() -> void:right_down=false;right_travel=0
func set_play_enabled(value: bool) -> void:
	play_enabled=value
	if not value:navigation.close()

func _process(_delta: float) -> void:
	if panel==null:return
	var viewport:=get_viewport().get_visible_rect().size
	var factor:=Preferences.effective_scale_vector(viewport);canvas.scale=factor
	var view:=viewport/factor
	panel.position=Vector2((floori(view.x/8)-98)*8,48+fposmod(view.y,12)*0.5)
	panel.size=Vector2(488,floori(view.y/12)*12-84)
	body.layout(panel.size.y);tabs.layout(panel.position)

func _input(event: InputEvent) -> void:
	if not ui_host.allows_panel_input(self):return
	if event is InputEventMouseMotion and right_down:right_travel+=event.relative.length()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed:right_down=true;right_travel=0
		else:
			var click:=right_down and right_travel<4;right_down=false
			if click:close_panel();get_viewport().set_input_as_handled()

func _exit_tree() -> void:navigation.dispose()
