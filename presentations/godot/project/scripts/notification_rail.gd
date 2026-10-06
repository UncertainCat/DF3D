extends ScrollContainer
signal group_requested(group: Dictionary)
signal group_dismissed(group: Dictionary)
# Semantic category names map to the installed native alert variants here only.
const CATEGORIES = ["General", "EraChange", "Underground", "Migrant", "Monster", "Ambush", "Trade", "Noble", "Animal", "Birth", "Mood", "LaborChange", "Military", "Marriage", "Berserk", "MartialTrance", "LoseEmotion", "Stress", "ArtDefacement", "Masterpiece", "JobFailed", "Death", "Ghost", "UndeadAttack", "Weather", "Vermin", "CuriousGuzzler", "ResearchBreakthrough", "GuestArrival", "Holdings", "Rumor", "Agreement", "Crime", "DeityCurse", "Combat", "Sparring", "Hunting"]
var world
var column: VBoxContainer
var buttons: Array[Button] = []
var _key: Array = []

func _ready():
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func update_groups(state: Dictionary, enabled: bool):
	var groups: Array = state.get("active_notifications", []) if state.get("fortress_valid", false) else []
	var epoch := int(state.get("fortress_epoch", 0))
	var key := [epoch, hash(groups)]
	if key != _key:
		_key = key
		buttons.clear()
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
		for group in groups:
			var category := CATEGORIES.find(str(group.get("category_name", "")))
			if category < 0: continue
			var button := Button.new()
			if world != null and world.has_method("ui_texture"): button.icon = world.ui_texture("ANNOUNCEMENT_ALERT", category)
			button.custom_minimum_size = Vector2(32,36)
			button.focus_mode = Control.FOCUS_NONE
			# Native category icons have no hover text (e7 findings item 4).
			# The distinct red ALERT button's instructions do not belong here.
			for style in ["normal", "hover", "pressed", "disabled", "focus"]: button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
			var selected: Dictionary = group.duplicate(true)
			selected["fortress_epoch"] = epoch
			button.pressed.connect(func(): group_requested.emit(selected))
			button.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not button.disabled:
					group_dismissed.emit(selected)
					button.accept_event())
			column.add_child(button)
			buttons.append(button)
	for button in buttons: button.disabled = not enabled
	visible = not buttons.is_empty()
