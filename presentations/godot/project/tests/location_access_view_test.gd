extends SceneTree
const View=preload("res://scripts/location_access_view.gd")
var failures:=0
class Help extends Node:
	var owners: Array=[]
	func leave(owner: int) -> void:owners.append(owner)
func check(ok: bool, reason: String) -> void:
	if not ok: failures+=1;push_error(reason)
func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_access_visual.json"))
	for sample in fixture.cases:
		var details: Dictionary=sample.details.duplicate();details.kind=int(details.kind)
		var actual:=View.content(details)
		check(actual.label==sample.label and actual.icons==sample.icons,"native permission text/selected art differs")
		check(actual.label_x==int(sample.label_cell.x)*8-384,"native permission label position differs")
		check(actual.color==Color8(int(sample.rgb[0]),int(sample.rgb[1]),int(sample.rgb[2])),"native permission color differs")
	check(View.content({}).is_empty() and View.content({"kind":5}).is_empty(),"unknown flags cannot become Citizens only")
	var view=View.new();var help=Help.new();view.hover_help=help
	view._leave_help(7);check(help.owners==[7],"valid hover owner must leave")
	view._leave_help.call_deferred(8);help.free()
	await process_frame
	view.free()
	print("LOCATION_ACCESS_VIEW_PASS" if failures==0 else "LOCATION_ACCESS_VIEW_FAIL")
	quit(failures)
