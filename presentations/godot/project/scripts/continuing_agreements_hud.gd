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

func configure(world, service) -> void:
	layer=1
	list_view=preload("res://scripts/continuing_agreements_view.gd").new()
	popup_view=preload("res://scripts/continuing_agreement_popup_view.gd").new()
	add_child(list_view);add_child(popup_view)
	list_view.configure(world);popup_view.configure(world)
	bind(service)

func bind(service) -> void:
	reader.configure(service);popup_reader.configure(reader)
	reader.changed.connect(_list_changed)
	popup_reader.changed.connect(_popup_changed)

func activate() -> void:
	reader.set_active(true)

func retire() -> void:
	reader.clear()

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
