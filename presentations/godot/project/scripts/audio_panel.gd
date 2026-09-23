extends CanvasLayer
var audio: Node
var panel: PanelContainer
var playing: Label
var pause: Button
var mute: CheckButton
var launcher: Button
var volume_controls: VBoxContainer
var sliders: Dictionary = {}

func _ready() -> void:
	layer = 5
	add_to_group("audio_panel")
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button := Button.new()
	launcher = button
	button.text = "Audio"
	button.focus_mode = Control.FOCUS_NONE
	anchor.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -92
	button.offset_right = -12
	button.offset_top = 12
	button.offset_bottom = 44
	panel = PanelContainer.new()
	anchor.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -332
	panel.offset_right = -12
	panel.offset_top = 52
	panel.custom_minimum_size = Vector2(320, 0)
	panel.visible = OS.get_environment("DF3D_AUDIO_PANEL") == "1"
	button.pressed.connect(func(): panel.visible = not panel.visible; audio.cue("click"))
	var box := VBoxContainer.new()
	panel.add_child(box)
	volume_controls = VBoxContainer.new()
	box.add_child(volume_controls)
	mute = CheckButton.new()
	mute.text = "Mute all audio"
	mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(audio.set_muted)
	volume_controls.add_child(mute)
	for bus in ["Master", "Music", "UI", "SFX"]:
		var row := HBoxContainer.new()
		volume_controls.add_child(row)
		var label := Label.new()
		label.text = bus
		label.custom_minimum_size.x = 60
		row.add_child(label)
		var slider := HSlider.new()
		slider.focus_mode = Control.FOCUS_NONE
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = audio.volumes[bus]
		slider.custom_minimum_size.x = 160
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sliders[bus] = slider
		slider.value_changed.connect(func(value): audio.set_volume(bus, value))
		row.add_child(slider)
	playing = Label.new()
	playing.custom_minimum_size.x = 300
	playing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(playing)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	pause = Button.new()
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(func(): audio.pause_music(not audio.music_paused); audio.cue("click"))
	controls.add_child(pause)
	var skip := Button.new()
	skip.text = "Next track"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func(): audio.next_track(); audio.cue("click"))
	controls.add_child(skip)
	audio.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	playing.text = audio.now_playing
	pause.text = "Resume music" if audio.music_paused else "Pause music"
	mute.set_pressed_no_signal(audio.muted)
	for bus in sliders: sliders[bus].set_value_no_signal(audio.volumes[bus])

func _input(event: InputEvent) -> void:
	if panel.visible and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			panel.hide()
			audio.cue("cancel")
		get_viewport().set_input_as_handled()

func blocks_camera() -> bool:
	return panel.visible

# Move the single authoritative set of volume controls into the settings menu.
# The standalone panel retains optional track playback controls for diagnostics.
func embed_settings(parent: Node) -> void:
	volume_controls.reparent(parent)
	panel.hide()
	launcher.hide()
