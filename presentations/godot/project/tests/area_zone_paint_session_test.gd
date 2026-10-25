extends SceneTree
const Session = preload("res://scripts/area_paint_session.gd")
const Service = preload("res://scripts/semantic_action_service.gd")
const FakeWorld = preload("res://tests/areas_test.gd").FakeWorld
var failures := 0
var revision := 10

func check(value: bool, reason: String) -> void:
	if not value: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func observed(count: int, id := 77, version := 9007199254740993) -> Dictionary:
	return {"id":id,"revision":version,"kind":1,"origin":Vector3i(3,4,2),"width":2,"height":1,
		"extents":PackedByteArray([1 if count > 0 else 0,1 if count > 1 else 0]),"tile_count":count,"zone_type":92}

func reply(service, world, rows: Array, status := 2, outcome := "") -> void:
	revision += 1
	world.state = {"world_epoch":42,"revision":revision,"request_seq":world.seq,
		"status":status,"action":world.calls[-1].action,"areas":rows,"outcome":outcome}
	service.poll()

func start(service, area := {}) -> Node:
	var session = Session.new(); service.add_child(session)
	session.configure(service,area,92,Vector2i(48,48),2)
	return session

func run() -> void:
	var world = FakeWorld.new()
	var service = Service.new(); service.configure(world); root.add_child(service); service.set_process(false)
	service.poll() # establish epoch before attaching an interaction
	var first := Vector3i(3,4,2); var last := Vector3i(4,4,2)
	var session = start(service)
	check(session.can_follow_elevation(),"never-painted interaction may follow elevation")
	session.rectangle(first,last); service.poll()
	check(world.calls[-1].action == 10 and world.calls[-1].spans == [{"x":3,"y":4,"length":2}],"completed gesture creates before Accept")
	session.rectangle(last,last,true)
	check(not session.can_follow_elevation(),"queued native work retains its original elevation")
	check(world.calls.size() == 1,"queued erase waits for authoritative identity")
	session.finish("exit")
	reply(service,world,[observed(2)])
	check(world.calls[-1].action == 11 and world.calls[-1].paint_mode == 2 and world.calls[-1].expected_revision == 9007199254740993,"exit drains queued erase with exact revision")
	reply(service,world,[observed(1,77,9007199254740994)])
	check(session.stopped and world.calls.size() == 2,"nonempty Escape keeps native zone after draining")
	await process_frame

	session = start(service); session.rectangle(first,last); service.poll()
	session.rectangle(last,last,true); session.finish("cancel")
	reply(service,world,[observed(2,78)])
	check(world.calls[-1].action == 12 and world.calls[-1].id == 78,"Cancel deletes resolved creation and discards later queued gestures")
	reply(service,world,[]); await process_frame

	session = start(service); session.rectangle(first,last); service.poll()
	session.rectangle(last,last,true); session.finish("multi")
	reply(service,world,[observed(2,82)])
	check(not session.stopped and world.calls[-1].action == 12 and world.calls[-1].id == 82,"Multi switch waits for deletion instead of retaining ordinary zone")
	var destinations: Array = []
	session.finished.connect(func(destination,_area): destinations.append(destination))
	reply(service,world,[])
	check(destinations == ["multi"],"Multi transition publishes only after deletion receipt")
	await process_frame

	session = start(service,observed(2,79))
	check(not session.finish("cancel"),"existing repaint has no new-zone Cancel authority")
	session.rectangle(first,last,true); service.poll()
	reply(service,world,[observed(0,79,9007199254740994)])
	check(not session.finish("accept") and not session.stopped,"Accept remains inert on an empty zone")
	session.stroke(first,first); service.poll()
	check(world.calls[-1].action == 11 and world.calls[-1].id == 79 and world.calls[-1].paint_mode == 1,"redraw keeps the empty zone identity")
	reply(service,world,[observed(1,79,9007199254740995)])
	session.finish("accept"); check(session.stopped,"Accept finishes a nonempty repaint without another mutation")
	await process_frame

	session = start(service,observed(2,80)); session.rectangle(first,last,true); service.poll()
	session.finish("exit"); reply(service,world,[observed(0,80,9007199254740994)])
	check(world.calls[-1].action == 12 and world.calls[-1].id == 80,"Escape deletes an authoritative empty zone")
	reply(service,world,[]); await process_frame

	session = start(service); session.rectangle(first,last); service.poll()
	session.finish("cancel")
	var before: int = world.calls.size()
	service.timeout_seconds = 0.001; service.poll(0.01)
	check(session.stopped and world.calls.size() == before,"unknown creation does not manufacture or replay deletion")
	reply(service,world,[observed(2,81)])
	check(world.calls.size() == before,"late creation receipt does not restart failed interaction")
	await process_frame
	check(not service.last_detached_mutation("areas").is_empty(),"unknown/late receipt remains owned by the service")

	service.timeout_seconds = 15
	var brush_session = start(service)
	brush_session.stroke(first,first); service.poll()
	brush_session.stroke(first,first+Vector3i(2,2,0))
	check(brush_session.geometry.cells.size() == 2 and not brush_session.geometry.cells.has(Vector2i(4,5)),"native brush samples do not interpolate between pointer events")
	reply(service,world,[observed(1,85)])
	check(world.calls[-1].spans == [{"x":5,"y":6,"length":1}],"queued sparse brush sends only sampled endpoint")
	var brush_result := observed(2,85,9007199254740994)
	brush_result.width = 3; brush_result.height = 3; brush_result.extents = PackedByteArray([1,0,0,0,0,0,0,0,1])
	reply(service,world,[brush_result]); brush_session.finish("cancel")
	service.poll(); reply(service,world,[]); await process_frame

	var old_session = start(service)
	old_session.rectangle(first,last); service.poll()
	old_session.rectangle(first,last,true); old_session.finish("exit")
	var new_session = start(service)
	new_session.rectangle(first,last)
	reply(service,world,[observed(2,83)])
	check(world.calls[-1].action == 11 and world.calls[-1].id == 83,"old queued erase precedes reopened painter creation")
	reply(service,world,[observed(0,83,9007199254740994)])
	check(world.calls[-1].action == 12 and world.calls[-1].id == 83,"old empty exit deletion precedes reopened painter creation")
	reply(service,world,[])
	check(world.calls[-1].action == 10 and old_session.stopped,"reopened painter starts after old interaction completes")
	reply(service,world,[observed(2,84)])
	new_session.finish("exit")
	await process_frame

	var pile := observed(2,90)
	pile.kind = 0; pile.erase("zone_type")
	session = Session.new(); service.add_child(session)
	session.configure(service,pile,-1,Vector2i(48,48),2,0)
	session.rectangle(first,last,true); service.poll()
	check(world.calls[-1].kind == 0 and world.calls[-1].paint_mode == 2,"stockpile erase commits as its own gesture")
	pile.extents = PackedByteArray([0,0]); pile.tile_count = 0; pile.revision += 1
	reply(service,world,[pile])
	check(not session.finish("accept") and not session.stopped,"empty stockpile retains identity with Accept disabled")
	session.stroke(first,first); service.poll()
	check(world.calls[-1].kind == 0 and world.calls[-1].id == 90,"stockpile regrowth reuses its empty identity")
	pile.extents = PackedByteArray([1,0]); pile.tile_count = 1; pile.revision += 1
	reply(service,world,[pile]); session.finish("exit")
	check(session.stopped,"exiting nonempty stockpile retains completed gestures")
	await process_frame
	session = Session.new(); service.add_child(session)
	session.configure(service,{},-1,Vector2i(48,48),2,0)
	session.rectangle(first,first); service.poll()
	check(world.calls[-1].kind == 0 and world.calls[-1].action == 10 and not world.calls[-1].has("zone_type"),"new stockpile creation has no zone fields")
	session.rectangle(first,first,true); session.finish("exit")
	pile.id = 91; reply(service,world,[pile])
	check(world.calls[-1].kind == 0 and world.calls[-1].paint_mode == 2,"closed stockpile painter drains its queued erase")
	pile.extents = PackedByteArray([0,0]); pile.tile_count = 0; pile.revision += 1
	reply(service,world,[pile])
	check(world.calls[-1].action == 12 and world.calls[-1].kind == 0 and world.calls[-1].id == 91,"empty stockpile exit waits for erase then removes the same pile")
	reply(service,world,[]); await process_frame

	for hit in ["existing","accepted-existing","empty","rejected"]:
		session = Session.new(); service.add_child(session)
		session.configure(service,{},-1,Vector2i(48,48),2,0)
		before = world.calls.size()
		session.resolve_initial_hit(first); session.stroke(first,first); service.poll()
		session.finish("accept" if hit == "accepted-existing" else "exit")
		check(world.calls.size() == before+1 and world.calls[-1].action == 8,"first brush waits for initial hit lookup")
		if hit in ["existing","accepted-existing"]:
			reply(service,world,[pile])
			check(session.stopped and world.calls.size() == before+1,"existing empty pile hit must not create or delete on exit")
			if hit == "accepted-existing": check(session.ending == "inspect","Accept during lookup still requires inspecting the existing pile summary")
		elif hit == "empty":
			reply(service,world,[])
			check(world.calls[-1].action == 10,"closed painter preserves completed brush after empty lookup")
			pile.extents = PackedByteArray([1,0]); pile.tile_count = 1; pile.id = 92
			reply(service,world,[pile])
			check(session.stopped,"closed painter completes after creation receipt")
		else:
			reply(service,world,[],3)
			check(session.stopped and world.calls.size() == before+1,"failed lookup never dispatches queued creation")
		await process_frame

	session = Session.new(); service.add_child(session)
	session.configure(service,{},-1,Vector2i(48,48),2,0)
	session.rectangle(first,last+Vector3i(1,0,0)); service.poll()
	# The repeated add is explicit even though its cell is already speculative.
	session.stroke(last,last); session.stroke(last,last)
	check(session._queue.size() == 1,"identical adjacent unsent samples coalesce")
	pile = observed(1,93); pile.kind = 0
	reply(service,world,[pile])
	check(world.calls[-1].spans == [{"x":last.x,"y":last.y,"length":1}],"clipped earlier creation cannot discard later overlapping add")
	check(session.geometry.cells.size() == 2 and not session.geometry.cells.has(Vector2i(last.x+1,last.y)),"reconciliation removes clipped ghosts but retains queued intent")
	session.rectangle(first,last,true)
	pile.extents = PackedByteArray([1,1]); pile.tile_count = 2; pile.revision += 1
	reply(service,world,[pile])
	check(session.geometry.cells.is_empty(),"queued erase reapplies over authoritative growth")
	pile.extents = PackedByteArray([0,0]); pile.tile_count = 0; pile.revision += 1
	reply(service,world,[pile]); session.finish("exit"); service.poll()
	check(world.calls[-1].action == 12 and world.calls[-1].id == 93,"reconciled empty exit deletes correct pile")
	reply(service,world,[]); await process_frame

	session = Session.new(); service.add_child(session)
	session.configure(service,pile,-1,Vector2i(48,48),2,0)
	session.stroke(first,first); service.poll(); session.finish("accept")
	reply(service,world,[pile]) # Native clips the speculative addition.
	check(not session.stopped and session.ending.is_empty() and session.geometry.cells.is_empty(),"clipped empty result must disarm pending Accept and retain painting")
	session.finish("exit"); service.poll(); reply(service,world,[]); await process_frame

	session = start(service); session.rectangle(first,last); service.poll()
	session.rectangle(last,last,true)
	before = world.calls.size()
	world.state = {"world_epoch":43,"revision":revision+1,"status":0}; service.poll()
	check(session.stopped and world.calls.size() == before,"epoch replacement cannot dispatch queued edits")
	await process_frame
	service.free()
	print("AREA_ZONE_PAINT_SESSION PASS" if failures == 0 else "AREA_ZONE_PAINT_SESSION FAIL")
	quit(0 if failures == 0 else 1)
