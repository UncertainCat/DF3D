extends Node

func _ready() -> void:
	if not OS.get_environment("DF3D_SETUP_CHANNEL").is_empty():
		var script_path := OS.get_environment("DF3D_SETUP_SCRIPT")
		if script_path.is_empty(): script_path = "res://scripts/setup_launcher.gd"
		var setup = load(script_path).new()
		add_child(setup)
	else:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
