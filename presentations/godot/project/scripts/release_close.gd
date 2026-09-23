extends Node
# Release-only close flow. A viewer exit never terminates the DF process.
signal close_requested
var world
var latest: Dictionary = {}
var dialog: ConfirmationDialog
var leave: Button
var pending := 0
var requested_at := 0
func _ready():
	get_tree().auto_accept_quit = false
	dialog = ConfirmationDialog.new()
	dialog.title = "Close DF3D"
	dialog.ok_button_text = "Save and close"
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(520, 180)
	dialog.dialog_hide_on_ok = false
	add_child(dialog)
	leave = dialog.add_button("Leave DF running", false, "leave")
	dialog.confirmed.connect(save_and_close)
	dialog.custom_action.connect(func(action):
		if action == "leave" and not leave.disabled: close_requested.emit())
	dialog.canceled.connect(func():
		if pending != 0: dialog.popup_centered())
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if pending != 0: return
		if latest.get("phase", 4) == 1:
			close_requested.emit()
			return
		dialog.dialog_text = "Save before closing? Dwarf Fortress will remain open.\n\nLeaving DF running does not save or discard your fortress."
		dialog.get_ok_button().disabled = not latest.get("can_save_return", false) or latest.get("phase", 4) == 6
		dialog.popup_centered()
func save_and_close():
	if pending != 0 or not latest.get("can_save_return", false): return
	pending = world.save_fortress(true, "")
	if pending == 0:
		dialog.dialog_text = "Save was not sent. Dwarf Fortress remains open.\n" + world.last_error()
		return
	requested_at = Time.get_ticks_msec()
	dialog.dialog_text = "Waiting for Dwarf Fortress to finish saving..."
	dialog.get_ok_button().disabled = true
	leave.disabled = true
func update_session(state: Dictionary):
	latest = state
	if pending == 0: return
	if int(state.get("phase",4)) == 4:
		pending = 0
		dialog.dialog_text = "Connection lost. Save completion is unknown. You can close DF3D."
		leave.disabled = false
		dialog.get_ok_button().disabled = true
		return
	if int(state.get("request_seq", 0)) == pending:
		if int(state.get("request_status", 0)) == 2 and int(state.get("phase", 4)) == 1:
			pending = 0
			close_requested.emit()
			return
		if int(state.get("request_status", 0)) == 3:
			pending = 0
			dialog.dialog_text = "Save failed. DF3D will stay open.\n" + str(state.get("message", ""))
			leave.disabled = false
			dialog.get_ok_button().disabled = not state.get("can_save_return", false)
	if pending != 0 and Time.get_ticks_msec() - requested_at > 120000:
		# Never treat a timeout as save completion or close the simulation.
		dialog.dialog_text = "Still waiting for save confirmation. Dwarf Fortress remains open; check its window."
		leave.disabled = false
