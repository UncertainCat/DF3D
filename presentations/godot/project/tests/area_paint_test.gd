extends SceneTree
const State = preload("res://scripts/area_paint_state.gd")
const Counts = preload("res://scripts/area_paint_counts.gd")
class CountService:
	extends RefCounted
	var requests: Array = []
	var observers: Array = []
	var detached: Array = []
	func submit(_domain, request, observer):
		requests.append(request.duplicate(true)); observers.append(observer); return requests.size()
	func detach(ticket): detached.append(ticket)
	func reply(ticket, painted, preview, generation := -1):
		var request: Dictionary = requests[ticket-1]
		observers[ticket-1].call(ticket,{"status":2,"action":9,"area":{"operation":19,
			"count_generation":request.count_generation if generation == -1 else generation,
			"painted_count":painted,"preview_count":preview}},request)
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void:
	test_counts()
	var state := State.new()
	state.open({},Vector2i(512,512),4)
	check(state.stroke(Vector3i(0,0,4),Vector3i(12,12,4)) and state.cells.size() == 13,"fast diagonal brush fills between samples")
	for i in 13: check(state.cells.has(Vector2i(i,i)),"diagonal stroke contains every intervening cell")
	check(state.stroke(Vector3i(12,12,4),Vector3i(0,0,4),true) and state.cells.is_empty(),"reverse erase follows same continuous path")
	check(not state.stroke(Vector3i(0,0,4),Vector3i(512,0,4)) and state.cells.is_empty(),"out-of-map stroke cannot partly edit draft")
	state.open({},Vector2i(512,512),4)
	check(state.rectangle(Vector3i(19,19,4),Vector3i(0,0,4)),"reversed rectangle includes all 400 tiles")
	check(state.cells.size() == 400 and state.prepare(),"400 tiles produce paint plan")
	check(State.spans_for(state.cells).size() == 20,"400 tile rectangle coalesces into one payload")
	var request: Dictionary = state.next_request()
	check(request.action == 10 and request.operation == 5 and request.paint_z == 4,"one request creates complete paint")
	check(state.next_request().is_empty(),"pending batch cannot be sent twice")
	var observed := {"id":37,"kind":0,"revision":9007199254740993,"origin":Vector3i(0,0,4),"width":20,"height":20,"extents":PackedByteArray()}
	observed.extents.resize(400); observed.extents.fill(1)
	state.stop("Outcome unknown; inspect before continuing")
	check(state.next_request().is_empty(),"unknown result cannot replay paint")
	state.rebase(observed)
	check(not state.prepare(),"reinspection proving all desired cells applied never replays unknown batch")
	state.open(observed,Vector2i(512,512),4)
	check(not state.rectangle(Vector3i(1,1,5),Vector3i(2,2,5)),"cross-z stroke refused")
	check(not state.rectangle(Vector3i(-1,0,4),Vector3i(1,1,4)),"out of map stroke refused")
	check(state.rectangle(Vector3i(0,0,4),Vector3i(19,19,4),true) and not state.prepare(),"whole-area erase cannot be submitted")
	state.open(observed,Vector2i(512,512),4)
	state.rectangle(Vector3i(0,0,4),Vector3i(19,0,4),true)
	check(state.prepare() and state.next_request().paint_mode == 3,"erase sends desired footprint in one replacement")
	var sparse: Dictionary = {}
	for y in 129: sparse[Vector2i(0,y)] = true
	var spans := State.spans_for(sparse)
	check(spans.size() == 129,"fragmented paint stays one request")
	state.open({},Vector2i(512,512),4)
	check(state.rectangle(Vector3i(0,0,4),Vector3i(255,127,4)),"32768 tiles and 256-side boundary supported")
	check(not state.rectangle(Vector3i(0,128,4),Vector3i(0,128,4)) and state.cells.size() == 32768,"oversize stroke leaves draft unchanged")
	state.open(observed,Vector2i(512,512),4)
	state.rectangle(Vector3i(0,0,4),Vector3i(19,0,4),true)
	state.rectangle(Vector3i(0,20,4),Vector3i(19,20,4))
	check(state.prepare(),"mixed add/erase draft prepares once")
	request = state.next_request()
	check(request.paint_mode == 3 and request.spans.size() == 20 and request.expected_revision == 9007199254740993,"mixed edit carries one full footprint and exact revision")
	check(state.accept(observed) and state.next_request().is_empty(),"authoritative success cannot dispatch a second mutation")
	state.clear(); check(state.cells.is_empty() and state.next_request().is_empty(),"close clears draft and chain")
	print("AREA_PAINT PASS" if failures == 0 else "AREA_PAINT FAIL"); quit(failures)

func test_counts() -> void:
	var service := CountService.new()
	var counts := Counts.new(); counts.service = service
	var request := {"action":9,"operation":19,"kind":1,"zone_type":92,"paint_z":4,"spans":[]}
	counts.demand([1,4,92],request); counts.poll(0)
	check(service.requests.size() == 1 and counts.values.is_empty(),"first count read is pending, not fabricated zero")
	counts.demand([2,4,92],request); counts.demand([3,4,92],request); counts.poll(1)
	check(service.requests.size() == 1,"pointer changes coalesce behind one outstanding read")
	service.reply(1,9,3)
	check(counts.values.is_empty(),"old draft reply cannot restore counts")
	counts.poll(0)
	check(service.requests.size() == 2 and service.requests[1].count_generation > service.requests[0].count_generation,"latest demand gets fresh request identity")
	service.reply(2,8,4)
	check(counts.values == {"painted":8,"preview":4},"native mixed erase counts remain positive")
	counts.poll(0.49)
	check(service.requests.size() == 2,"idle reads wait for refresh cadence")
	counts.poll(0.02)
	check(service.requests.size() == 3 and counts.values.is_empty(),"unchanged geometry refreshes native dependencies and retires expired counts")
	service.reply(3,-1,0)
	check(counts.values == {"painted":-1,"preview":0},"unknown remains distinct from zero")
	counts.demand([3,5,92],request); counts.poll(0.11)
	counts.clear()
	check(service.detached == [4] and counts.values.is_empty() and counts.ticket == 0,"session/close clears and detaches read")
	counts.demand([3,5,92],request); counts.poll(0)
	service.reply(4,123,4)
	check(counts.values.is_empty() and counts.ticket == 5,"late reply from retired session cannot match reopened read")
	service.reply(5,1,1,service.requests[4].count_generation-1)
	check(counts.values.is_empty(),"wrong echoed generation is rejected")
	counts.poll(0.51); service.reply(6,0,0)
	check(counts.values == {"painted":0,"preview":0},"observed zero counts are retained")
	counts.demand([4,5,89],request); counts.poll(0.11); service.reply(7,32769,0)
	check(counts.values.is_empty(),"malformed count cannot reach the caption")
	counts.clear(); counts.poll(10)
	check(service.requests.size() == 7,"closed painter has no background refresh")
	# This fake intentionally retains callbacks to deliver late replies. Release
	# them after the checks, as the real service does on completion/detachment.
	service.observers.clear()
