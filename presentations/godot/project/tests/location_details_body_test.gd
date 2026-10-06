extends SceneTree
const Body=preload("res://scripts/location_details_body.gd")
var failures:=0
func check(ok: bool, reason: String) -> void:
	if not ok: failures+=1;push_error(reason)
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_body.json"))
	for sample in data.cases:
		# Recorded JSON numbers are doubles; typed model facts are int32/int64.
		var d: Dictionary=sample.details.duplicate(true)
		for key in ["kind","written_objects","desired_copies","dance_floor_x","dance_floor_y"]: d[key]=int(d[key])
		for key in d.facilities: d.facilities[key]=int(d.facilities[key])
		for supply in d.supplies:
			for key in supply: supply[key]=int(supply[key])
		var actual:=Body.content(d)
		check(actual.size()==sample.expected.size(),"native body row count differs")
		for i in mini(actual.size(),sample.expected.size()):
			var row: Dictionary=actual[i];var expected: Dictionary=sample.expected[i]
			check(row.x==int(expected.x) and row.y==int(expected.y) and row.caption+row.value==expected.text,"native body text/position differs: "+str(row)+" expected "+str(expected))
	check(Body.content({"kind":1}).is_empty(),"unknown facts cannot turn into zero-valued body rows")
	var none:=Body.content({"kind":1,"dance_floor_x":0,"dance_floor_y":0})
	check(none.size()==1 and none[0].value=="None","native absent dance floor text required")
	var colors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_dance_color.json"))
	var palette={4:Color8(255,113,17),6:Color8(255,225,17),7:Color.WHITE}
	for sample in colors.cases:
		var actual:=Body.content({"kind":int(sample.kind),"dance_floor_x":int(sample.x),"dance_floor_y":int(sample.y)})
		if (int(sample.x)==0)!=(int(sample.y)==0):
			check(actual.is_empty(),"invalid semantic dimension pair must remain absent");continue
		check(actual.size()==1 and actual[0].value==sample.text and actual[0].color==palette[int(sample.fg)] and sample.bold,"native dance wording/color differs")
	print("LOCATION_DETAILS_BODY_PASS" if failures==0 else "LOCATION_DETAILS_BODY_FAIL")
	quit(failures)
