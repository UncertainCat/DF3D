extends VBoxContainer
const Preferences = preload("res://scripts/presentation_settings.gd")
const MODES = ["windowed","fullscreen"]
const SIZES = [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]
var mode_picker: OptionButton
var size_picker: OptionButton
var result: Label
var sizes: Array = []
var options: VBoxContainer
var confirmation: VBoxContainer
var countdown: Label
var pending := false
var applying := false
var remaining := 0.0
var previous: Dictionary = {}
var proposed_mode := "windowed"
var proposed_size := Vector2i(1600,900)
var windowed_selection := 0
func _ready() -> void:
	options=VBoxContainer.new()
	add_child(options)
	mode_picker=OptionButton.new()
	for title in ["Windowed","Borderless fullscreen"]: mode_picker.add_item(title)
	mode_picker.select(MODES.find(Preferences.window_mode))
	row("Display mode",mode_picker)
	size_picker=OptionButton.new()
	sizes.assign(SIZES)
	if not sizes.has(Preferences.window_size): sizes.append(Preferences.window_size)
	windowed_selection=sizes.find(Preferences.window_size)
	row("Resolution",size_picker)
	size_picker.item_selected.connect(func(index): windowed_selection=index)
	mode_picker.item_selected.connect(func(_index): refresh_resolutions())
	refresh_resolutions()
	var apply:=Button.new()
	apply.text="Apply"
	apply.pressed.connect(apply_settings)
	options.add_child(apply)
	confirmation=VBoxContainer.new()
	add_child(confirmation)
	var title:=Label.new()
	title.text="Keep these display settings?"
	confirmation.add_child(title)
	countdown=Label.new()
	confirmation.add_child(countdown)
	var buttons:=HBoxContainer.new()
	confirmation.add_child(buttons)
	for caption in ["Keep changes","Revert"]:
		var button:=Button.new()
		button.text=caption
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(keep_changes if caption=="Keep changes" else revert_changes)
		buttons.add_child(button)
	confirmation.hide()
	result=Label.new()
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(result)
func row(title: String, control: Control) -> void:
	var box:=HBoxContainer.new()
	options.add_child(box)
	var label:=Label.new()
	label.text=title
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_child(label)
	box.add_child(control)
func refresh_resolutions() -> void:
	size_picker.clear()
	if mode_picker.selected==0:
		for dimensions in sizes: size_picker.add_item("%d x %d" % [dimensions.x,dimensions.y])
		size_picker.select(windowed_selection)
		size_picker.disabled=false
	else:
		var desktop:=DisplayServer.screen_get_size(get_window().current_screen) if DisplayServer.get_name()!="headless" else Vector2i(1920,1080)
		size_picker.add_item("Desktop (%d x %d)" % [desktop.x,desktop.y])
		size_picker.disabled=true
func apply_settings() -> void:
	if pending or applying: return
	var window:=get_window()
	previous={"mode":window.mode,"size":window.size,"position":window.position}
	proposed_mode=MODES[mode_picker.selected]
	proposed_size=sizes[windowed_selection]
	pending=true
	applying=true
	options.hide()
	confirmation.show()
	remaining=15.0
	result.text=""
	await Preferences.apply_window_values(window,proposed_mode,proposed_size)
	applying=false
func _process(delta: float) -> void:
	if not pending or applying: return
	remaining-=delta
	countdown.text="Reverting in %d seconds" % ceili(maxf(remaining,0))
	if remaining<=0 or not is_visible_in_tree(): revert_changes()
func keep_changes() -> void:
	if not pending or applying: return
	Preferences.window_mode=proposed_mode
	Preferences.window_size=proposed_size
	Preferences.display_configured=true
	result.text="" if Preferences.save_preferences()==OK else "Could not save display settings"
	finish_confirmation()
func revert_changes() -> void:
	if not pending or applying: return
	var window:=get_window()
	applying=true
	var drawing:=RenderingServer.render_loop_enabled
	RenderingServer.render_loop_enabled=false
	RenderingServer.force_sync()
	window.mode=previous.mode
	await get_tree().process_frame
	if previous.mode==Window.MODE_WINDOWED:
		window.size=previous.size
		window.position=previous.position
	RenderingServer.force_sync()
	RenderingServer.render_loop_enabled=drawing
	applying=false
	mode_picker.select(MODES.find(Preferences.window_mode))
	windowed_selection=sizes.find(Preferences.window_size)
	refresh_resolutions()
	finish_confirmation()
func finish_confirmation() -> void:
	pending=false
	confirmation.hide()
	options.show()
