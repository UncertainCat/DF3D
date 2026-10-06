extends Control
# Local presentation ownership only; not exposed by ui_availability.
# Native transitions: native_options_input.json and native_options_confirmations.json.
# Session effects, Settings and timeline selection still require integration/acceptance.
signal dismissed
signal route_requested(token: String)
signal confirmed(token: String)
signal save_requested(bytes: PackedByteArray)
signal timeline_requested(bytes: PackedByteArray)
signal destination_requested(id: String)
enum Page { CLOSED, MENU, NAME, CONFIRMATION, RETURN_CHOICES, TIMELINE_NAME }
var page: int = Page.CLOSED
var input_allowed: Callable
var session_busy := false
var menu = preload("res://scripts/native_options_view.gd").new()
var naming = preload("res://scripts/native_save_name_view.gd").new()
var confirmation = preload("res://scripts/native_options_confirmation.gd").new()
var return_choices = preload("res://scripts/native_save_return_view.gd").new()
var timeline_naming = preload("res://scripts/native_timeline_name_view.gd").new()

func configure(source) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in [menu, naming, confirmation, return_choices, timeline_naming]:
		add_child(child)
		child.configure(source)
		child.layout_reference()
	menu.input_allowed = func(): return accepts_input() and page == Page.MENU
	naming.input_allowed = func(): return accepts_input() and page == Page.NAME
	confirmation.input_allowed = func(): return accepts_input() and page == Page.CONFIRMATION
	return_choices.input_allowed = func(): return accepts_input() and page == Page.RETURN_CHOICES
	timeline_naming.input_allowed = func(): return accepts_input() and page == Page.TIMELINE_NAME
	menu.option_requested.connect(_select)
	menu.dismissed.connect(close)
	naming.cancelled.connect(func(): _show_page(Page.MENU))
	naming.submitted.connect(func(bytes): save_requested.emit(bytes))
	confirmation.cancelled.connect(_cancel_confirmation)
	confirmation.confirmed.connect(func(token): confirmed.emit(token))
	return_choices.option_requested.connect(_select_return)
	return_choices.destination_requested.connect(_select_destination)
	return_choices.dismissed.connect(close)
	timeline_naming.cancelled.connect(func(): _show_page(Page.RETURN_CHOICES))
	timeline_naming.submitted.connect(func(bytes): timeline_requested.emit(bytes))
	_show_page(Page.CLOSED)

func accepts_input() -> bool:
	return is_visible_in_tree() and not session_busy and (not input_allowed.is_valid() or input_allowed.call())

func open() -> void:
	# Reopening an active child must not discard its local draft.
	if page == Page.CLOSED: _show_page(Page.MENU)

func close() -> void:
	if page == Page.CLOSED: return
	_show_page(Page.CLOSED)
	dismissed.emit()

func _show_page(value: int) -> void:
	page = value
	visible = page != Page.CLOSED
	menu.visible = page == Page.MENU
	naming.visible = page == Page.NAME
	confirmation.visible = page == Page.CONFIRMATION
	return_choices.visible = page == Page.RETURN_CHOICES
	timeline_naming.visible = page == Page.TIMELINE_NAME

func _select(token: String) -> void:
	if not accepts_input() or page != Page.MENU: return
	match token:
		"RETURN": close()
		"SAVE_AND_CONTINUE":
			naming.begin_entry()
			_show_page(Page.NAME)
		"RETIRE_FORTRESS", "ABANDON_FORTRESS", "QUIT_WITHOUT_SAVING":
			confirmation.display(token)
			_show_page(Page.CONFIRMATION)
		"SAVE_AND_QUIT", "SETTINGS": route_requested.emit(token)

func show_overwrite() -> void:
	# Caller must establish the destination conflict; no filesystem inference here.
	if page != Page.NAME: return
	confirmation.display("SAVE_OVERWRITE")
	_show_page(Page.CONFIRMATION)

func show_save_return(destinations: Array) -> bool:
	# Caller owns catalog epoch/freshness. An unavailable catalog is not empty.
	# Do not replace an active child or partially apply a malformed catalog.
	if page != Page.MENU or not accepts_input(): return false
	if not return_choices.set_destinations(destinations): return false
	_show_page(Page.RETURN_CHOICES)
	return true

func _select_destination(id: String) -> void:
	if not accepts_input() or page != Page.RETURN_CHOICES: return
	destination_requested.emit(id)

func _select_return(token: String) -> void:
	if not accepts_input() or page != Page.RETURN_CHOICES: return
	match token:
		"RETURN": close()
		"SAVE_TO_NEW_FOLDER_NEW_TIMELINE":
			timeline_naming.begin_entry()
			_show_page(Page.TIMELINE_NAME)
		"SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE": route_requested.emit(token)

func _cancel_confirmation() -> void:
	_show_page(Page.NAME if confirmation.token == "SAVE_OVERWRITE" else Page.MENU)

func _unhandled_input(event: InputEvent) -> void:
	# Children run first. Remaining keyboard input belongs to this modal surface,
	# even while another session owner temporarily denies its actions.
	if is_visible_in_tree() and event is InputEventKey:
		get_viewport().set_input_as_handled()
