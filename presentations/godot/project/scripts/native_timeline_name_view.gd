extends "res://scripts/native_save_name_view.gd"
# Native102803/102935: timeline metadata is not a filesystem name. Keep native
# punctuation even though the manual-save filename field filters these bytes.
# Unexposed until explicit timeline/destination session commands are accepted.
func _init() -> void:
	prompt_lines = [
		"What would you like to name this timeline?",
		"Saves starting here will be grouped on the",
		"title screen, with their own active save.",
	]
	excluded_bytes = PackedByteArray()
