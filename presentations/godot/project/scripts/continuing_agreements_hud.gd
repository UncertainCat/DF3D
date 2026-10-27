extends CanvasLayer
# Viewer-owned composition. Activation is explicit after session retirement;
# pointer movement and redraw must never reactivate a retired reader.
signal hover_claim_changed(claimed: bool)
var reader=preload("res://scripts/continuing_agreements_reader.gd").new()
var popup_reader=preload("res://scripts/continuing_agreement_popup_reader.gd").new()
var list_view
var popup_view
var hover_claimed:=false
var list_allowed:=true
var hud
var world_source
var session_entered:=false
var session_identity: Array=[]
var pointer_position:=Vector2(-1,-1)

func _ready() -> void:
	get_viewport().mouse_exited.connect(_pointer_left)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:pointer_position=event.position

func _pointer_left() -> void:
	pointer_position=Vector2(-1,-1)
	popup_reader.clear();_claim(false)

func configure(world, service) -> void:
	layer=1
	world_source=world
	list_view=preload("res://scripts/continuing_agreements_view.gd").new()
	popup_view=preload("res://scripts/continuing_agreement_popup_view.gd").new()
	add_child(list_view);add_child(popup_view)
	list_view.configure(world);popup_view.configure(world)
	bind(service)

func bind(service) -> void:
	reader.configure(service);popup_reader.configure(reader)
	reader.changed.connect(_list_changed)
	popup_reader.changed.connect(_popup_changed)
	service.session_changed.connect(_pointer_left)

func activate() -> void:
	reader.set_active(true)

func retire() -> void:
	reader.clear()

func sync_session(entered: bool, identity: Array) -> void:
	# Called from this owner's process, after the semantic service has reconciled
	# its session. A repeated context cannot undo service-triggered retirement.
	var fresh:=entered and (not session_entered or identity!=session_identity)
	if not entered and session_entered:retire()
	session_entered=entered;session_identity=identity.duplicate()
	if fresh:activate()

func _process(delta: float) -> void:
	if hud==null:return
	sync_session(hud.entered and world_source.is_live(),[world_source.session_generation(),int(hud.session.get("fortress_epoch",0))])
	var popup_allowed: bool=hud.enabled and not hud.menu_open()
	var active=hud.ui_host.active
	# Current Info, areas, construction and inspection owners suppress native
	# popup targeting. Reports/alerts instead cover it with their higher layer.
	if is_instance_valid(active) and active.get_script() not in [preload("res://scripts/reports_panel.gd"),preload("res://scripts/alert_popup_panel.gd")]:
		popup_allowed=false
	if get_viewport().gui_get_hovered_control()!=null:popup_allowed=false
	update_hover(delta,get_viewport().get_visible_rect().size,hud.ui_scale_vector(),
		pointer_position,hud.visible,popup_allowed)

func _claim(value: bool) -> void:
	if hover_claimed==value:return
	hover_claimed=value;hover_claim_changed.emit(value)

func _list_changed() -> void:
	list_view.display(reader.snapshot() if reader.active and reader.ready else [])
	list_view.visible=list_view.visible and list_allowed
	if not reader.active or not reader.ready:_claim(false)

func _popup_changed() -> void:
	popup_view.display(popup_reader.snapshot() if popup_reader.ready else {})
	if popup_reader.target.is_empty():_claim(false)

func update_hover(delta: float, viewport_size: Vector2, factor: Vector2,
		pointer: Vector2, show_list: bool, allow_popup: bool) -> void:
	scale=factor
	list_view.layout(viewport_size/factor);popup_view.layout(viewport_size/factor)
	list_view.visible=show_list and reader.active and reader.ready and not reader.snapshot().is_empty()
	list_allowed=show_list
	var row: Dictionary={}
	if list_view.visible and allow_popup and Rect2(Vector2.ZERO,viewport_size).has_point(pointer):
		row=list_view.row_at(pointer/factor-list_view.position)
	popup_reader.display(row)
	# Claim immediately, including while semantic details are pending. Controls
	# remain mouse-ignore: this arbitrates prose, never map click ownership.
	_claim(not popup_reader.target.is_empty())
	reader.poll(delta);popup_reader.poll(delta)
	popup_view.visible=hover_claimed and popup_reader.ready

func _exit_tree() -> void:
	popup_reader.dispose();reader.dispose()
