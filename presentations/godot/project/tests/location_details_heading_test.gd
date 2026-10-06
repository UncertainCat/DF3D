extends SceneTree
const Heading=preload("res://scripts/location_details_heading.gd")
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_heading.json"))
	for sample in data.cases:
		var details: Dictionary=sample.details.duplicate(true)
		for key in ["kind","tier","profession"]:details[key]=int(details[key])
		var actual:=Heading.content(details)
		if actual.size()!=sample.expected_heading.size():push_error("Native heading row count differs");quit(1);return
		for i in actual.size():
			var expected: Dictionary=sample.expected_heading[i]
			if actual[i].text!=expected.text or actual[i].x!=int(expected.x) or actual[i].y!=int(expected.y):push_error("Native heading differs");quit(1);return
	var visual: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_affiliation_visual.json"))
	var palette={7:Color8(192,192,192),15:Color.WHITE,14:Color8(255,225,17),11:Color8(18,254,207),13:Color8(232,17,255)}
	for sample in visual.cases:
		var details: Dictionary=sample.details.duplicate(true)
		for key in ["kind","tier","profession"]:details[key]=int(details[key])
		if details.has("affiliation"):
			for key in ["kind","id","count","workers"]:details.affiliation[key]=int(details.affiliation[key])
		var actual:=Heading.content(details)
		if actual.size()!=sample.expected.size():push_error("Native affiliation row count differs "+str(sample.case));quit(1);return
		for i in actual.size():
			var expected: Dictionary=sample.expected[i]
			if str(actual[i].text).left(int(expected.width))!=expected.text or actual[i].x!=int(expected.x) or actual[i].y!=int(expected.y) or actual[i].get("color",Color.WHITE)!=palette[int(expected.fg)+(8 if expected.bold else 0)]:
				push_error("Native affiliation differs "+str(sample.case)+" "+str(actual[i])+" expected "+str(expected.text));quit(1);return
	if not Heading.affiliation_rows({"kind":2}).is_empty():push_error("Unknown affiliation invented text");quit(1);return
	if not Heading.content({}).is_empty():push_error("Unknown heading invented text");quit(1);return
	print("LOCATION_DETAILS_HEADING_PASS");quit(0)
