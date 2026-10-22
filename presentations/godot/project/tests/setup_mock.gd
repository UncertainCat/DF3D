extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(preload("res://scripts/setup_view.gd").new())
