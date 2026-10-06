extends CanvasLayer
# Session controls remain responsive while Saving disables map interactions.
var world
var audio: Node
var panel: PanelContainer
var status: Label
var feedback: Label
var save: Button
var save_return: Button
var checkpoint_name: LineEdit
var pending_seq := 0
var latest: Dictionary = {}
var local_error := ""
const MONTHS = ["Granite", "Slate", "Felsite", "Hematite", "Malachite", "Galena", "Limestone", "Sandstone", "Timber", "Moonstone", "Opal", "Obsidian"]

static func fresh_checkpoint_name() -> String:
	return "DF3D " + Time.get_datetime_string_from_system().replace("T", " ").replace(":", "-") + "-" + str(Time.get_ticks_msec() % 1000)

static func calendar(year: int, year_tick: int) -> String:
	var days: int = clampi(year_tick, 0, 403199) / 1200
	return "%d %s, %d" % [days % 28 + 1, MONTHS[days / 28], year]

func _ready() -> void:
	layer = 4
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	panel = PanelContainer.new()
	anchor.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 12
	panel.offset_top = -116
	panel.offset_right = 590
	panel.offset_bottom = -12
	var box := VBoxContainer.new()
	panel.add_child(box)
	status = Label.new()
	box.add_child(status)
	var row := HBoxContainer.new()
	box.add_child(row)
	checkpoint_name = LineEdit.new()
	checkpoint_name.custom_minimum_size.x = 235
	checkpoint_name.max_length = 40
	checkpoint_name.placeholder_text = "New checkpoint name"
	checkpoint_name.text = fresh_checkpoint_name()
	checkpoint_name.tooltip_text = "New manual checkpoint; existing names are never overwritten"
	checkpoint_name.text_changed.connect(func(_text): local_error = "")
	row.add_child(checkpoint_name)
	save = Button.new()
	save.text = "Save checkpoint"
	save.tooltip_text = "Save through Dwarf Fortress's native save dialog"
	save.focus_mode = Control.FOCUS_NONE
	row.add_child(save)
	save.pressed.connect(func(): request_save(false))
	save_return = Button.new()
	save_return.text = "Save and return to menu"
	save_return.tooltip_text = "Save the current timeline, or create a new timeline folder when continuing from a manual checkpoint"
	save_return.focus_mode = Control.FOCUS_NONE
	row.add_child(save_return)
	save_return.pressed.connect(func(): request_save(true))
	feedback = Label.new()
	feedback.custom_minimum_size.x = 570
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	visible = false

func update_session(state: Dictionary, entered: bool) -> void:
	latest = state
	visible = entered
	var valid: bool = state.get("fortress_valid", false)
	var busy: bool = state.get("phase", 4) in [6,7] or state.get("request_status", 0) == 1
	status.text = "%s · %s · %s" % [state.get("fort_name", "Fortress"), calendar(state.get("year", 0), state.get("year_tick", 0)), "Paused" if state.get("paused", false) else "Running"] if valid else "Fortress status unavailable"
	if busy: status.text += " · Saving" if state.get("phase", 4) == 6 else " · Working"
	if pending_seq != 0 and state.get("request_seq", 0) == pending_seq and state.get("request_status", 0) in [2, 3, 4]:
		pending_seq = 0
		if state.request_status == 2 and state.get("request_action", 0) == 1:
			checkpoint_name.text = fresh_checkpoint_name()
		if audio != null and state.request_status != 4: audio.cue("accepted" if state.request_status == 2 else "rejected")
	if state.get("phase", 4) == 4:
		pending_seq = 0
		feedback.text = "Connection lost. Save completion is unverified."
	elif local_error != "":
		feedback.text = local_error
	elif state.get("request_action", 0) in [1,2]:
		feedback.text = state.get("message", "")
	save.disabled = not entered or not valid or busy or pending_seq != 0 or not state.get("can_save", false)
	save_return.disabled = not entered or not valid or busy or pending_seq != 0 or not state.get("can_save_return", false)
	checkpoint_name.editable = not busy and pending_seq == 0
	if not busy and not state.get("can_save", false):
		save.tooltip_text = "Close panels in Dwarf Fortress and wait for any current save"
	else: save.tooltip_text = "Save through Dwarf Fortress's native save dialog"

func request_save(return_to_menu: bool) -> void:
	if (save_return.disabled if return_to_menu else save.disabled): return
	pending_seq = world.save_fortress(return_to_menu, "" if return_to_menu else checkpoint_name.text)
	feedback.text = "Waiting for Dwarf Fortress to save..." if pending_seq > 0 else "Save was not sent. Refresh fortress status and try again."
	if pending_seq == 0 and world.has_method("last_error"): feedback.text = world.last_error()
	local_error = feedback.text if pending_seq == 0 else ""
	if pending_seq > 0:
		save.disabled = true
		save_return.disabled = true
		if audio != null: audio.cue("click")

func blocks_commands() -> bool:
	return pending_seq != 0 or latest.get("phase", 4) in [6,7]
