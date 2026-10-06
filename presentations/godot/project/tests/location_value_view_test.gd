extends SceneTree
const View=preload("res://scripts/location_value_view.gd")
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_value_visual.json"))
	for sample in data.cases:
		var details: Dictionary=sample.details.duplicate(true)
		for key in details:details[key]=int(details[key])
		if View.content(details)!=sample.text:push_error("Native value line differs "+str(details));quit(1);return
	for unknown in [{},{"kind":2,"tier":1},{"kind":2,"tier":1,"value":0,"appraisal":-2},{"kind":1,"tier":1,"value":0,"appraisal":15}]:
		if not View.content(unknown).is_empty():push_error("Unknown value invented visible copy");quit(1);return
	print("LOCATION_VALUE_VIEW_PASS");quit(0)
