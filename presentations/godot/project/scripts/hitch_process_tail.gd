extends Node
# Last ordinary process callback. No RenderingServer query or GPU synchronization.
var recorder
func _ready() -> void:
	process_priority = 2147483647
func _process(_delta: float) -> void:
	if recorder.enabled: recorder.late_process(Time.get_ticks_usec())
