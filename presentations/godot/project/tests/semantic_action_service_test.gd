extends SceneTree
const Service = preload("res://scripts/semantic_action_service.gd")
const Contract = preload("res://scripts/management_contract.gd")
var failures := 0
class FakeWorld:
	extends RefCounted
	var state := {"world_epoch": 5, "revision": 1, "status": 0}
	var generation := 1
	var calls: Array = []
	var reject := false
	var reconnects := 0
	func reconnect_management(): reconnects += 1
	func poll_management(): return state.duplicate(true)
	func session_generation(): return generation
	func is_live(): return true
	func last_error(): return "Target disappeared"
	func management_request(domain, request):
		if reject: return 0
		calls.append({"domain": domain, "request": request.duplicate(true)})
		return calls.size()
class HeaderWorld:
	extends FakeWorld
	var payload_calls := 0
	var refuse_payload := false
	func poll_management_header():
		var header := {}
		for key in ["world_epoch","revision","status","request_seq","action","transport_alive"]:
			if state.has(key): header[key] = state[key]
		return header
	func management_payload(epoch,revision,sequence):
		payload_calls += 1
		if refuse_payload or epoch!=state.world_epoch or revision!=state.revision or sequence!=state.request_seq: return {}
		return state.duplicate(true)
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func test_continuation_order() -> void:
	for outcome in ["ok","rejected","unknown","read"]:
		var world := FakeWorld.new()
		var service := Service.new(); service.configure(world)
		var continuations: Array = []
		var follow := {"action":11,"kind":1,"id":77,"expected_revision":9007199254740993}
		var first := service.submit("areas",{"action":9 if outcome == "read" else 10},func(ticket,_result,_request):
			check(service.submit_continuation(ticket,"construction",{"action":2},Callable()) == 0,"continuation cannot cross domains")
			check(service.submit_continuation(ticket,"areas",{"action":9},Callable()) == 0,"continuation cannot promote reads")
			continuations.append(service.submit_continuation(ticket,"areas",follow,Callable()))
			check(service.submit_continuation(ticket,"areas",follow,Callable()) == 0,"receipt cannot schedule duplicate continuations"))
		service.poll()
		service.submit("areas",{"action":10},Callable())
		check(service.submit_continuation(first,"areas",follow,Callable()) == 0,"queued interaction cannot borrow a pending receipt")
		if outcome == "unknown":
			service.timeout_seconds = 0.001; service.poll(0.01)
			check(world.calls.size() == 1,"unknown predecessor blocks queued transport")
			world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":2,"action":10}
		else:
			world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":3 if outcome == "rejected" else 2,"action":9 if outcome == "read" else 10}
		service.poll()
		check(continuations.size() == 1 and (int(continuations[0]) > 0) == (outcome == "ok"),"only successful mutation observer owns one continuation")
		check(world.calls.size() == 2 and world.calls[-1].request.action == (11 if outcome == "ok" else 10),"existing interaction continuation precedes newer command")
		check(service.submit_continuation(first,"areas",follow,Callable()) == 0,"continuation authority expires outside observer")
		service.free()

func test_construction_outcomes() -> void:
	for outcome in [Contract.ConstructionOutcome.Partial,Contract.ConstructionOutcome.Unknown]:
		var world := FakeWorld.new()
		var service := Service.new();service.configure(world)
		var ticket := service.submit("construction",{"action":2},Callable())
		service.poll()
		world.state={"world_epoch":5,"revision":2,"request_seq":1,"status":3,"action":2,
			"construction":{"outcome":outcome,"placed":2,"updated":1,"first_building":99,"failed_index":4}}
		service.poll()
		var result: Dictionary = service.result(ticket)
		check(result.outcome==("unknown" if outcome==Contract.ConstructionOutcome.Unknown else "partial"),"construction outcome classification")
		check(result.construction.placed==2 and result.construction.updated==1 and result.construction.failed_index==4,"confirmed construction effects survive failure")
		for i in 5: service.poll()
		check(world.calls.size()==1,"partial/unknown construction must never replay")
		check(service.submit_continuation(ticket,"construction",{"action":2},Callable())==0,"failed construction cannot schedule a success continuation")
		service.free()

func run():
	test_header_payload_delivery()
	test_result_ownership()
	test_construction_outcomes()
	test_location_entry_unknown()
	test_continuation_order()
	test_queued_cancellation()
	test_domain_routing()
	test_construction_materials()
	test_work_orders()
	test_area_operations()
	test_citizens()
	test_production()
	test_reports()
	test_agreements()
	test_transport_replacement()
	test_new_domain_detach()
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	service.timeout_seconds = 1.0
	var observed: Array = []
	var callback := func(ticket, result, request): observed.append([ticket, result, request])
	var mutation := service.submit("construction", {"action": 2}, callback)
	service.poll()
	var query := service.submit("areas", {"action": 7}, callback)
	service.detach(mutation)
	service.poll(0.2)
	check(world.calls.size() == 1 and observed.is_empty(), "closing detaches view while another query queues")
	world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":2,"action":2,"building_id":42}
	service.poll()
	check(observed.is_empty() and service.result(mutation).building_id == 42, "closed mutation result retained outside view")
	check(service.last_detached_mutation("construction").detached, "late detached receipt retains detached ownership")
	check(world.calls.size() == 2 and world.calls.back().request.action == 7, "next view query starts only after old receipt drained")
	service.poll(1.1)
	check(service.result(query).outcome == "unknown" and observed.size() == 1, "timeout reports unknown exactly once")
	var later := service.submit("construction", {"action": 0}, callback)
	service.poll(2.0)
	check(world.calls.size() == 2 and observed.size() == 1, "timed out sequence is never replayed or overwritten")
	world.state = {"world_epoch":5,"revision":3,"request_seq":2,"status":2,"action":7}
	service.poll()
	check(service.result(query).status == 2 and observed.size() == 1, "late receipt updates retained result without reviving old view")
	check(world.calls.size() == 3, "late receipt permits queued request to start")
	var queued := service.submit("areas", {"action":10}, callback)
	world.generation += 1
	service.poll()
	check(service.result(later).outcome == "unknown" and service.result(queued).outcome == "not_sent", "session generation invalidates sent and queued requests distinctly")
	check(world.calls.size() == 3, "session switch never replays queued mutation")
	world.reject = true
	var gone := service.submit("areas", {"action":11,"id":77}, callback)
	service.poll()
	check(service.result(gone).message == "Target disappeared" and service.result(gone).outcome == "not_sent", "immediate admission failure retains disappearing-target outcome")
	world.reject = false
	var old := service.submit("areas", {"action":12,"id":77}, callback)
	service.poll()
	world.state.world_epoch = 6
	service.poll()
	check(service.result(old).outcome == "unknown", "epoch change invalidates an in-flight mutation without replay")
	var calls_before: int = world.calls.size()
	var unsupported := service.submit("unknown", {"action":10}, callback)
	service.poll()
	check(service.result(unsupported).outcome == "not_sent" and world.calls.size()==calls_before,"Unknown domain never routes into area mutation channel")
	var callback_attempts: Array = []
	var reentrant := func(_ticket, _result): callback_attempts.append(service.submit("areas", {"action":10}, callback))
	service.completed.connect(reentrant)
	service.submit("areas", {"action":12}, callback)
	service.poll()
	world.state.world_epoch = 7
	service.poll()
	service.completed.disconnect(reentrant)
	check(callback_attempts == [0] and service._queue.is_empty(),"Invalidated callbacks cannot enqueue mutations into replacement world")
	var uncertain := service.submit("areas", {"action":11,"id":77}, callback)
	service.poll()
	service.detach(uncertain)
	service.poll(1.1)
	check(service.last_detached_mutation("areas").result.outcome=="unknown","Closed timeout remains accessible for reopening/notification without replay")
	world.state.world_epoch = 8
	service.poll()
	service.retention_limit = 2
	for index in 4:
		world.reject = true
		service.submit("areas", {"action":11,"id":index}, callback)
		service.poll()
	check(service._results.size() == 2 and service.result(mutation).is_empty(), "terminal result retention is bounded")
	service.free()
	print("SEMANTIC_ACTION_SERVICE_TEST ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func test_queued_cancellation():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	service.submit("construction", {"action": 0}, Callable())
	service.poll()
	var observed: Array = []
	var cancelled := service.submit("construction", {"action": 2}, func(t, r, q): observed.append(t))
	# Exercise reentrant panel cleanup during the cancellation notification.
	service.completed.connect(func(ticket, _result): service.detach(ticket))
	service.detach(cancelled)
	service.detach(cancelled)
	check(service.result(cancelled).outcome == "not_sent", "queued draft cancellation has a definite unsent outcome")
	check(observed.is_empty(), "cancelled draft does not call its detached observer")
	world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":2}
	service.poll()
	check(world.calls.size() == 1 and service._queue.is_empty(), "cancelled mutation never reaches DF after active receipt arrives")
	service.free()

func test_transport_replacement():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var sent := service.submit("production", {"action": Service.Action.ProductionQueue}, Callable())
	service.poll()
	service.poll(16.0)
	check(service.result(sent).outcome == "unknown", "timeout alone keeps ownership until a definite transport loss")
	var queued := service.submit("trade", {"action": Service.Action.TradeBring}, Callable())
	world.state = {"transport_alive": false}
	service.poll()
	check(service.result(sent).outcome == "unknown" and service.result(queued).outcome == "not_sent", "owner loss distinguishes uncertain sent mutation from unsent drafts")
	for index in 20: service.poll(1.0)
	check(world.reconnects == 2 and world.calls.size() == 1, "owner loss reconnects once without replay or reset storm")
	check(service.submit("areas", {"action":10}, Callable()) == 0, "unavailable connection cannot accumulate stale drafts")
	# Replacement owner reuses epoch, model generation and sequence numbers.
	world.calls.clear()
	world.state = {"transport_alive":true,"world_epoch":5,"revision":1,"status":0}
	service.poll()
	check(world.calls.size() == 1 and world.calls[0].request.action == 0 and world.calls[0].domain == "construction", "replacement owner starts with a fresh read-only catalog")
	world.state = {"transport_alive":true,"world_epoch":5,"revision":2,"request_seq":1,"status":2}
	service.poll()
	service.submit("areas", {"action":10}, Callable())
	service.poll()
	check(world.calls.size() == 2 and world.calls[1].request.action == 10, "fresh user intent proceeds after owner recovery")
	check(service.result(sent).outcome == "unknown", "new owner's matching sequence cannot resolve old mutation")
	world.state = {"transport_alive":false}
	service.poll()
	world.generation += 1
	world.state = {"transport_alive":true,"world_epoch":6,"revision":1,"status":0}
	service.poll()
	var before: int = world.calls.size()
	service.poll()
	check(world.calls.size() == before + 1 and world.calls.back().request.action == 0 and world.calls.back().domain == "construction", "world replacement during outage cannot discard recovery catalog")
	service.free()

func test_domain_routing():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var callback := func(t, r, q): observed.append([t, r, q])
	var routes := {"construction":Service.Action.Place,"areas":Service.Action.AreaUpdate,
		"production":Service.Action.ProductionQueue,"work_orders":Service.Action.WorkOrderCreate,
		"citizens":Service.Action.WorkDetailMembership,"reports":Service.Action.ReportInspect,
		"agreements":Service.Action.AgreementInspect,"trade":Service.Action.TradeBring}
	for domain in routes:
		var request := {"action":routes[domain],"id":123}
		var ticket := service.submit(domain, request, callback)
		var before := observed.size()
		check(ticket > 0 and service.result(ticket).is_empty(), "submit returns ticket before observer")
		service.poll()
		check(world.calls.back() == {"domain":domain,"request":request}, "each domain dispatches original typed intent")
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"status":2,"action":routes[domain]}
		service.poll()
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "each receipt reaches its own ticket once")
		check(service.result(ticket).action == routes[domain], "retained result belongs to request")
	for domain in ["work_orders", "trade"]:
		var ticket := service.submit(domain, {"action":Service.Action.Catalog}, callback)
		service.poll()
		check(world.calls.back().domain == domain and world.calls.back().request.action == Service.Action.Catalog, "catalog routes under any runtime domain")
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"status":2,"action":Service.Action.Catalog}
		service.poll()
		check(service.result(ticket).status == 2 and not service._outcomes.has(ticket), "catalog remains read-only")
	var invalid := [["areas",Service.Action.Place],["trade",Service.Action.TradeExchangeOpen],["citizens",Service.Action.CreatureInspect],["",Service.Action.CreatureInspect],
		["trade",[]],["trade",{}],["trade","0"],["trade",0.0],["trade",null]]
	for pair in invalid:
		var before := observed.size()
		var calls := world.calls.size()
		var ticket := service.submit(pair[0], {"action":pair[1]}, callback)
		check(ticket > 0 and observed.size() == before, "invalid intent observer waits until poll")
		service.poll()
		service.poll()
		check(observed.size() == before+1 and observed.back()[0] == ticket, "invalid ticket rejected exactly once")
		check(service.result(ticket).outcome == "not_sent" and world.calls.size() == calls, "invalid intent never reaches world")
		check(not service._requests.has(ticket) and not service._queue.has(ticket), "invalid ticket is removed after publication")
	service.free()

func test_new_domain_detach():
	for domain in ["production", "trade"]:
		var action: int = Service.Action.ProductionQueue if domain == "production" else Service.Action.TradeBring
		var world := FakeWorld.new()
		var service := Service.new()
		service.configure(world)
		var observed: Array = []
		var ticket := service.submit(domain, {"action":action}, func(t, r, q): observed.append(t))
		service.poll()
		service.detach(ticket)
		world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":2,"action":action}
		service.poll()
		check(observed.is_empty() and service.result(ticket).status == 2, "new domain late receipt stays detached from observer")
		check(service.last_detached_mutation(domain).detached, "new domain late receipt retains detached ownership")
		check(world.calls.size() == 1 and world.calls[0].domain == domain, "detached new domain mutation is never replayed")
		service.free()

func test_work_orders():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var callback := func(t, r, q): observed.append([t, r, q])
	var refusal := "Deleted-order capacity reached; restart DF"
	for action in range(20,28):
		var request := {"action":action,"id":0,"expected_revision":9}
		var ticket := service.submit("work_orders", request, callback)
		var before := observed.size()
		service.poll()
		check(world.calls.back() == {"domain":"work_orders","request":request}, "all eight work-order actions route")
		var status: int = Contract.ManagementStatus.Rejected if action == 24 else Contract.ManagementStatus.Ok
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
			"status":status,"action":action,"message":refusal if action == 24 else "Observed"}
		service.poll()
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "work-order reply reaches matching ticket")
		check(service.result(ticket).status == status, "work-order status retained")
		check(service._outcomes.has(ticket) == (action >= 22 and action <= 25), "only work-order mutations retain receipts")
		check(Contract.is_mutation(action) == (action >= 22 and action <= 25), "work-order mutation classification")
		if action == 24:
			check(service.result(ticket).message == refusal and observed.back()[1].message == refusal, "bridge Delete refusal reaches observer")
		var calls := world.calls.size()
		for index in 3: service.poll(1.0)
		check(world.calls.size() == calls and observed.size() == before+1, "terminal work-order reply never replays")
	var removal := {"action":25,"id":0,"expected_revision":9,"condition_index":0,"remove_condition":true}
	var ticket := service.submit("work_orders", removal, callback)
	service.poll()
	check(world.calls.back().request == removal, "remove condition reaches transport intact")
	world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
		"status":Contract.ManagementStatus.Rejected,"action":25,"message":refusal}
	service.poll()
	check(service.result(ticket).message == refusal and service.result(ticket).status == Contract.ManagementStatus.Rejected, "condition removal refusal reaches ticket")
	check(service._outcomes.has(ticket), "rejected removal retains mutation receipt")
	var count := world.calls.size()
	for index in 3: service.poll(1.0)
	check(world.calls.size() == count, "refused removal never replays")
	for request in [
		{"action":24,"id":0,"expected_revision":9},
		{"action":25,"id":0,"expected_revision":9,"condition_kind":1,"condition_index":0,"remove_condition":true},
		{"action":23,"id":0,"expected_revision":9,"move":1,"expected_neighbor":2,"expected_list_revision":9223372036854775807}]:
		var mutation := service.submit("work_orders", request, callback)
		service.poll(0.0)
		check(world.calls.back() == {"domain":"work_orders","request":request}, "delete, remove and move retain semantic intent")
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"status":Contract.ManagementStatus.Ok,"action":request.action}
		service.poll(0.0)
		check(service.result(mutation).status == Contract.ManagementStatus.Ok and service._outcomes.has(mutation), "successful mutation retains receipt")
	for phase in [1,2,3]:
		var before := observed.size()
		var candidate := service.submit("work_orders", {"action":26,"candidate_kind":4}, callback)
		service.poll(0.0)
		var sent := world.calls.size()
		world.state = {"world_epoch":5,"revision":sent+1,"request_seq":sent,"status":Contract.ManagementStatus.Ok,"action":26,
			"work_order":{"materials":[],"build_phase":phase,"build_done":0,"build_total":100}}
		service.poll(0.0)
		check(service.result(candidate).status == Contract.ManagementStatus.Ok and observed.size() == before+1, "builder progress is an ordinary Ok reply")
		check(service._active == 0 and not service._requests.has(candidate) and not service._outcomes.has(candidate), "builder progress releases transport without pending mutation")
		for index in 3: service.poll(1.0)
		check(world.calls.size() == sent and observed.size() == before+1, "builder progress never replays; panel owns future polling")
	service.free()

func test_citizens():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var callback := func(t, r, q): observed.append([t, r, q])
	var refusal := "Work-detail contents changed; refresh before editing"
	var requests := [{"action":28,"query":"Citizen","cursor":32}, {"action":29,"unit_id":0},
		{"action":30,"query":"Custom","cursor":16}, {"action":31,"detail_index":1,"unit_id":0},
		{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":1},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":3},
		{"action":64,"expected_revision":7}, {"action":65,"detail_index":1,"expected_revision":7},
		{"action":66,"detail_index":1,"expected_revision":7,"edit":1,"name":"MinersX"},
		{"action":67,"unit_id":0,"expected_revision":7,"only_assigned":1}]
	for request in requests:
		var action: int = request.action
		var ticket := service.submit("citizens", request, callback)
		var before := observed.size()
		service.poll(0.0)
		check(world.calls.back() == {"domain":"citizens","request":request}, "all ten citizen actions dispatch intact")
		var status: int = Contract.ManagementStatus.Rejected if action in [32,65] else Contract.ManagementStatus.Ok
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
			"status":status,"action":action,"message":refusal if action in [32,65] else "Citizens inspected",
			"citizen":{"recalc_done":1,"recalc_total":5000}}
		service.poll(0.0)
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "citizen reply reaches its ticket")
		check(service.result(ticket).status == status, "citizen status retained")
		check(service._outcomes.has(ticket) == (action >= 32), "only citizen mutations retain receipts")
		check(Contract.is_mutation(action) == (action >= 32), "citizen mutation classification")
		if action in [32,65]:
			check(service.result(ticket).message == refusal and observed.back()[1].message == refusal, "stale revision refusal reaches observer")
		var calls := world.calls.size()
		for index in 3: service.poll(1.0)
		check(world.calls.size() == calls and observed.size() == before+1, "citizen terminal outcome never replays")
	service.free()

func test_construction_materials():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var callback := func(t, r, q): observed.append([t,r,q])
	var request := {"action":Contract.ManagementAction.ConstructionMaterials,"definition":"Chair","filter":0}
	var ticket := service.submit("construction", request, callback)
	service.poll()
	check(world.calls.size() == 1 and world.calls[0].domain == "construction", "materials action routes to construction")
	world.state = {"world_epoch":5,"revision":2,"request_seq":1,"status":2,"action":63,
		"construction":{"build_phase":1,"build_done":0,"build_total":1024}}
	service.poll()
	check(observed.size() == 1 and service.result(ticket).status == 2, "builder progress is an ordinary Ok reply")
	check(service.result(ticket).construction.build_phase == 1, "builder progress reaches observer")
	var place := service.submit("construction", {"action":Contract.ManagementAction.Place}, callback)
	service.poll()
	world.state = {"world_epoch":5,"revision":3,"request_seq":2,"status":3,"action":2,
		"message":"Selected material was taken during placement",
		"construction":{"placed":256,"skipped":0,"first_building":101}}
	service.poll()
	check(service.result(place).status == 3 and service.result(place).construction.placed == 256,
		"partial rejected placement retains counts")
	check(service.result(place).message == "Selected material was taken during placement", "exact partial refusal reaches view")
	check(observed.size() == 2 and observed.back()[1].construction.placed == 256, "partial reply displayed once")
	for i in 10: service.poll(1.0)
	check(world.calls.size() == 2 and observed.size() == 2, "partial rejection never replays")
	service.free()

func test_production():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var requests := [{"action":15,"query":"#0","cursor":0}, {"action":16,"building_id":0},
		{"action":17,"building_id":0,"recipe":"builtin:27:-1","repeat":1},
		{"action":18,"building_id":0,"job_id":10,"cancel":true},
		{"action":19,"building_id":3,"season":0,"crop_id":-1}]
	for request in requests:
		var ticket := service.submit("production", request, func(t, r, q): observed.append([t,r,q]))
		var before := observed.size()
		service.poll(0.0)
		check(world.calls.back() == {"domain":"production","request":request}, "all production actions dispatch intact")
		var status: int = Contract.ManagementStatus.Rejected if request.action == 17 else Contract.ManagementStatus.Ok
		var message := "Native workshop queue is full (10 jobs)" if request.action == 17 else "Observed"
		world.state = {"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),
			"status":status,"action":request.action,"message":message}
		service.poll(0.0)
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "production reply reaches matching ticket")
		check(service.result(ticket).status == status and service.result(ticket).message == message, "production refusal preserved")
		check(service._outcomes.has(ticket) == (request.action >= 17), "only production mutations retain receipts")
		check(Contract.is_mutation(request.action) == (request.action >= 17), "production mutation classification")
		var calls := world.calls.size()
		for i in 3: service.poll(1.0)
		check(world.calls.size() == calls and observed.size() == before+1, "production outcomes never replay")
	service.free()

func test_reports():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	for action in [34,35]:
		var request := {"action":action}
		if action == 35: request.id = 999999
		var ticket := service.submit("reports", request, func(t,r,q): observed.append([t,r,q]))
		var before := observed.size()
		service.poll(0.0)
		var sent := world.calls.size()
		check(world.calls.back() == {"domain":"reports","request":request}, "both report actions route intact")
		check(not Contract.is_mutation(action), "reports are read-only")
		if action == 34:
			world.state = {"world_epoch":5,"revision":sent+10,"request_seq":sent,"action":action,
				"status":Contract.ManagementStatus.Pending,"message":"Searching native reports"}
			service.poll(0.0)
			check(service.result(ticket).is_empty() and observed.size() == before and service._active == ticket, "Pending retains ticket without publishing")
		var status: int = Contract.ManagementStatus.Ok if action == 34 else Contract.ManagementStatus.Rejected
		var message := "Native reports" if action == 34 else "Report no longer exists"
		world.state = {"world_epoch":5,"revision":sent+20,"request_seq":sent,"action":action,"status":status,"message":message}
		service.poll(0.0)
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "report resolves matching ticket once")
		check(service.result(ticket).status == status and service.result(ticket).message == message and observed.back()[1].message == message, "exact report reply retained")
		check(not service._outcomes.has(ticket), "report has no mutation receipt")
		for i in 3: service.poll(1.0)
		check(world.calls.size() == sent and observed.size() == before+1, "report never replays")
	check(not Contract.is_runtime(Service.Action.Alert), "native Alert stays retired")
	service.free()

func test_agreements():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	for action in [36,37]:
		var request := {"action":action}
		if action == 37: request.id = 999999
		var ticket := service.submit("agreements", request, func(t,r,q): observed.append([t,r,q]))
		var before := observed.size()
		service.poll(0.0)
		var sent := world.calls.size()
		check(world.calls.back() == {"domain":"agreements","request":request}, "both agreement actions route intact")
		check(not Contract.is_mutation(action), "agreements are read-only")
		if action == 36:
			world.state = {"world_epoch":5,"revision":sent+10,"request_seq":sent,"action":action,
				"status":Contract.ManagementStatus.Pending,"message":"Searching native agreements"}
			service.poll(0.0)
			check(service.result(ticket).is_empty() and observed.size() == before and service._active == ticket, "Pending retains ticket without publishing")
		var status: int = Contract.ManagementStatus.Ok if action == 36 else Contract.ManagementStatus.Rejected
		var message := "Native agreements" if action == 36 else "Agreement is unavailable or unrelated to this fortress"
		world.state = {"world_epoch":5,"revision":sent+20,"request_seq":sent,"action":action,"status":status,"message":message}
		service.poll(0.0)
		check(observed.size() == before+1 and observed.back()[0] == ticket and observed.back()[2] == request, "agreement resolves matching ticket once")
		check(service.result(ticket).status == status and service.result(ticket).message == message and observed.back()[1].message == message, "exact agreement reply retained")
		check(not service._outcomes.has(ticket), "agreement has no mutation receipt")
		for i in 3: service.poll(1.0)
		check(world.calls.size() == sent and observed.size() == before+1, "agreement never replays")
	service.free()

func test_area_operations():
	var world := FakeWorld.new()
	var service := Service.new()
	service.configure(world)
	var observed: Array = []
	var callback := func(t, r, q): observed.append([t, r, q])
	# Op selectors never override action-level mutation ownership.
	for action in [Service.Action.AreaCreate, Service.Action.AreaUpdate, Service.Action.AreaDelete, Service.Action.AreaLink]:
		var operations: Array = [0, 5] if action == Service.Action.AreaCreate else [0, 15] if action == Service.Action.AreaLink else [0]
		if action == Service.Action.AreaUpdate:
			operations = [0, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13]
		for operation in operations:
			var request := {"action":action, "operation":operation, "id":7, "expected_revision":19}
			var before := observed.size()
			var ticket := service.submit("areas", request, callback)
			service.poll(0.0)
			var sent := world.calls.size()
			check(world.calls.back().request == request, "area operation and revision reach transport unchanged")
			world.state = {"world_epoch":5,"revision":sent+1,"request_seq":sent,"action":action,
				"status":Contract.ManagementStatus.Rejected,"message":"Area changed; inspect again"}
			service.poll(0.0)
			check(service._outcomes.has(ticket), "every area mutation selector retains a receipt")
			check(service.result(ticket).message == "Area changed; inspect again" and observed.size() == before+1, "area rejection reaches its observer once")
			for index in 3: service.poll(1.0)
			check(world.calls.size() == sent and observed.size() == before+1, "rejected area mutations never replay")
	for operation in [1, 6, 10, 14]:
		var action: int = Service.Action.AreaCandidates if operation == 14 else Service.Action.AreaInspect
		for phase in [1, 2, 3]:
			var request := {"action":action,"operation":operation,"id":7}
			var ticket := service.submit("areas", request, callback)
			service.poll(0.0)
			var sent := world.calls.size()
			world.state = {"world_epoch":5,"revision":sent+1,"request_seq":sent,"action":action,
				"status":Contract.ManagementStatus.Ok,"area":{"operation":operation,"build_phase":phase,"build_done":0,"build_total":100}}
			service.poll(0.0)
			check(service.result(ticket).area.build_phase == phase and service.result(ticket).status == Contract.ManagementStatus.Ok, "area build progress remains an ordinary Ok reply")
			check(service._active == 0 and not service._requests.has(ticket) and not service._outcomes.has(ticket), "area progress releases transport without mutation receipt")
			for index in 3: service.poll(1.0)
			check(world.calls.size() == sent, "area list polling belongs to the panel")
	service.free()

func test_location_entry_unknown() -> void:
	var world := FakeWorld.new()
	var service := Service.new();service.configure(world)
	var observations: Array=[]
	var ticket := service.submit("areas",{"action":Contract.ManagementAction.AreaUpdate,"operation":Contract.AreaOperation.LocationOpen},
		func(_ticket,result,_request): observations.append(result))
	service.poll()
	world.state={"world_epoch":5,"revision":2,"request_seq":1,"status":3,"action":11,
		"area":{"operation":Contract.AreaOperation.LocationOpen,"location_entry_outcome":Contract.LocationEntryOutcome.Unknown}}
	service.poll()
	check(observations.size()==1 and observations[0].get("outcome","")=="unknown","partial entry must remain unknown")
	check(service.result(ticket).get("outcome","")=="unknown","entry outcome retained")
	service.poll();check(world.calls.size()==1,"partial entry is never replayed")
	service.free()

func test_result_ownership() -> void:
	for listen in [false,true]:
		var world := FakeWorld.new()
		var service := Service.new(); service.configure(world)
		if listen:
			service.completed.connect(func(_ticket,result): result.construction.materials[0].name="signal mutation")
		var seen := []
		var ticket := service.submit("construction",{"action":Contract.ManagementAction.ConstructionMaterials},func(_ticket,result,_request):
			seen.append(result.construction.materials[0].name)
			result.construction.materials[0].name="observer mutation")
		service.poll()
		world.state={"world_epoch":5,"revision":2,"request_seq":1,"status":2,"action":Contract.ManagementAction.ConstructionMaterials,"construction":{"materials":[{"name":"fixture name"}]}}
		service.poll()
		check(seen==["fixture name"] and service.result(ticket).construction.materials[0].name=="fixture name","one-shot payload transfer isolates signal, observer and retained receipt")
		service.free()

func test_header_payload_delivery() -> void:
	var world := HeaderWorld.new()
	var service := Service.new(); service.configure(world)
	var seen := []
	var ticket := service.submit("construction",{"action":Contract.ManagementAction.ConstructionMaterials},func(_ticket,result,_request):seen.append(result.construction.materials[0].name))
	service.poll()
	world.state={"world_epoch":5,"revision":1,"request_seq":1,"status":1,"action":Contract.ManagementAction.ConstructionMaterials}
	for frame in 120: service.poll()
	check(world.payload_calls==0 and service._active==ticket,"pending metadata never converts a material payload")
	world.state.status=2; world.state.revision=2; world.state.construction={"materials":[{"name":"fixture material"}]}
	world.refuse_payload=true; service.poll()
	check(service._active==ticket and seen.is_empty(),"identity mismatch retains the active ticket without a partial receipt")
	world.refuse_payload=false; service.poll()
	check(seen==["fixture material"] and service._active==0,"matching receipt publishes a complete payload once")
	for frame in 120: service.poll()
	check(world.payload_calls==2,"unchanged terminal metadata does not reconvert delivered payloads")
	service.submit("construction",{"action":Contract.ManagementAction.ConstructionMaterials},Callable()); service.poll()
	world.state.request_seq=999; service.poll()
	check(world.payload_calls==2,"unrelated sequence does not fetch a payload")
	world.generation+=1; service.poll()
	check(world.payload_calls==2 and service._active==0,"generation replacement invalidates before fetching a stale receipt")
	service.free()
