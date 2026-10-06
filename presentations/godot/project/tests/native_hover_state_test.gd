extends SceneTree
const Hover=preload("res://scripts/native_hover_state.gd")
var failures:=0
func check(ok: bool, reason: String) -> void:
	if not ok: failures+=1;push_error(reason)
func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_location_hover.json"))
	for trace in fixture.traces:
		var state=Hover.new();var previous: String=""
		for row in trace.samples:
			var now:=int(row.ms);var requested: String=row.requested
			if requested!=previous:
				if requested.is_empty(): state.leave(1,now)
				else: state.enter(1,requested,now)
				previous=requested
			check(state.advance(now)==row.displayed,"native hover trace differs: "+str(trace.capture)+" "+str(row))
	var state=Hover.new();state.enter(1,"first",0)
	check(state.advance(499)=="" and state.advance(500)=="first","cold hover threshold")
	state.enter(2,"second",510);state.leave(1,520)
	check(state.advance(520)=="second","late owner departure cannot clear replacement help")
	state.leave(2,530);check(state.advance(600)=="","leaving hides immediately")
	state.enter(3,"third",900);check(state.advance(900)=="third","short departure retains native warm state")
	state.leave(3,910);state.advance(1910);state.enter(4,"fourth",2000)
	check(state.advance(2499)=="" and state.advance(2500)=="fourth","long departure requires a fresh delay")
	state.reset();check(state.advance(10000)=="" and not state.warm,"world/owner reset removes help")
	print("NATIVE_HOVER_STATE_PASS" if failures==0 else "NATIVE_HOVER_STATE_FAIL")
	quit(failures)
