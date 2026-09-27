extends SceneTree
const Contract = preload("res://scripts/management_contract.gd")
const A = Contract.ManagementAction
const S = Contract.ManagementStatus
var world
var child := 0
var status_path := ""

func finish(code: int, message: String) -> void:
	if child > 0 and OS.is_process_running(child): OS.kill(child)
	if not status_path.is_empty(): DirAccess.remove_absolute(status_path)
	if world != null: world.free()
	print(message)
	quit(code)

func receipt(sequence: int) -> Dictionary:
	for i in 300:
		var value: Dictionary = world.poll_management()
		if int(value.get("request_seq",0)) == sequence and int(value.get("status",S.Idle)) == S.Ok:
			return value
		await create_timer(0.01).timeout
	return {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var executable := ProjectSettings.globalize_path("res://../../../build/tools/management_contract_host.exe")
	if not FileAccess.file_exists(executable):
		finish(77,"QA_INCOMPLETE: build management_contract_host first")
		return
	status_path = OS.get_user_data_dir().path_join("management-contract-%d.txt" % OS.get_process_id())
	DirAccess.remove_absolute(status_path)
	child = OS.create_process(executable,[status_path],false)
	for i in 300:
		if FileAccess.file_exists(status_path): break
		await create_timer(0.01).timeout
	var ready := FileAccess.get_file_as_string(status_path) if FileAccess.file_exists(status_path) else "failed"
	if ready != "ready":
		finish(77 if ready == "incomplete" else 1,"QA_INCOMPLETE: management channel occupied" if ready == "incomplete" else "CONTRACT_HOST_START_FAILED")
		return
	world = ClassDB.instantiate("Df3dWorld")
	var state: Dictionary = world.poll_management()
	assert(int(state.world_epoch)==9007199254740993)
	assert(state.status is int and state.action is int)
	assert(Contract.is_mutation(A.Place) and Contract.is_mutation(A.AreaUpdate))
	assert(not Contract.is_mutation(A.Preview))
	# Wrong types and absent identities must fail locally, never reach the ring.
	for request in [{},{"action":float(A.Catalog)},{"action":A.Place,"definition":"Chair"},
		{"action":A.Remove},{"action":A.Inspect,"building_id":2147483000.0},
		{"action":A.Place,"definition":"Chair","origin":Vector3(1,2,3)},
		{"action":A.Place,"definition":"Chair","origin":Vector3i(1,2,3),"items":[1.5]}]:
		assert(world.construction_request(request)==0)
		assert(not str(world.last_error()).is_empty())
	for request in [{"action":A.AreaUpdate},{"action":A.AreaUpdate,"id":1,"owner_id":"-2"},
		{"action":A.AreaCreate},{"action":A.AreaLink,"id":1,"give":1}]:
		assert(world.area_request(request)==0)
	var sequence: int = world.construction_request({"action":A.Catalog})
	assert(sequence>0)
	state = await receipt(sequence)
	assert(not state.is_empty())
	sequence = world.area_request({"action":A.AreaUpdate,"id":2147483000,"kind":Contract.AreaKind.Zone})
	assert(sequence>0)
	state = await receipt(sequence)
	assert(not state.is_empty())
	assert(state.building_id==2147483000 and state.build_stage==-1 and state.max_stage==-1)
	assert(state.area_next_cursor==4294967295)
	assert(state.areas.size()==1)
	assert(state.areas[0].id==2147483000 and state.areas[0].owner_id==-1)
	assert(state.areas[0].origin==Vector3i(11,12,13))
	sequence = world.construction_request({"action":A.Place,"definition":"Chair",
		"origin":Vector3i(11,12,13),"items":[2147483001]})
	assert(sequence>0)
	state = await receipt(sequence)
	assert(not state.is_empty() and state.action==A.Place)
	# Domain and action admission errors precede connection and typed conversion.
	assert(world.management_request("unknown", {}) == 0)
	assert(world.last_error() == "Unknown management domain")
	assert(world.management_request("trade", {}) == 0)
	assert(world.last_error() == "Missing management field: action")
	assert(world.management_request("trade", {"action":float(A.Catalog)}) == 0)
	assert(world.last_error() == "Wrong management field type: action")
	for pair in [["areas", {"action":A.Place}], ["citizens", {"action":A.CreatureInspect}]]:
		assert(world.management_request(pair[0], pair[1]) == 0)
		assert(world.last_error() == "Management action does not match domain")
	for pair in [["trade", {"action":-1}], ["trade", {"action":256}],
		["production", {"action":A.ProductionJobEdit,"building_id":1,"job_id":1.5}],
		["citizens", {"action":A.WorkDetailMode,"detail_index":1,"mode":"1"}],
		["agreements", {"action":A.AgreementInspect,"id":"1"}],
		["trade", {"action":A.TradeUpdate,"depot_id":1,"requested":true}],
		["work_orders", {"action":A.WorkOrderUpdate,"id":1,"expected_revision":1.5}],
		["reports", {"action":A.ReportInspect,"id":1.5}]]:
		assert(world.management_request(pair[0], pair[1]) == 0)
		assert(not str(world.last_error()).is_empty())
	for action in A.values():
		if Contract.is_runtime(action): continue
		assert(Contract.domain_of(action).is_empty())
		assert(world.management_request("trade", {"action":action}) == 0)
		assert(world.last_error() == "Management action does not match domain")
	for domain in ["work_orders", "trade"]:
		assert(world.management_request(domain, {"action":A.Catalog,"width":0}) == 0)
		assert(world.last_error() == "Invalid management request")
	assert(Contract.is_runtime(A.CreatureInspect) and Contract.domain_of(A.CreatureInspect).is_empty())
	assert(not Contract.is_runtime(-1) and not Contract.is_runtime(256))
	assert(Contract.domain_of(-1).is_empty() and Contract.domain_of(256).is_empty())
	# Bounds and semantic identities must also fail without consuming a sequence.
	for pair in [["production", {"action":A.ProductionJobEdit,"building_id":1,"job_id":-1,"repeat":1}],
		["production", {"action":A.FarmSetCrop,"building_id":1,"crop_id":32768,"season":0}],
		["citizens", {"action":A.WorkDetailMode,"detail_index":128,"expected_revision":1,"mode":1}],
		["citizens", {"action":A.WorkDetailMembership,"detail_index":1,"unit_id":1,"expected_revision":0,"member":1}],
		["agreements", {"action":A.AgreementInspect,"id":1,"pending_only":true}],
		["trade", {"action":A.TradeUpdate,"depot_id":1,"expected_revision":0,"requested":1}],
		["trade", {"action":A.TradeList,"receipt":1}]]:
		assert(world.management_request(pair[0],pair[1]) == 0)
	for pair in [["work_orders", {"action":A.Catalog}], ["trade", {"action":A.Catalog}],
		["production", {"action":A.ProductionJobEdit,"building_id":2147483000,"job_id":2147483001,"repeat":1}],
		["work_orders", {"action":A.WorkOrderUpdate,"id":2147483000,"expected_revision":9007199254740993,"remaining":12}],
		["citizens", {"action":A.WorkDetailMembership,"unit_id":2147483000,"detail_index":127,"expected_revision":9007199254740993,"member":1}],
		["reports", {"action":A.ReportInspect,"id":2147483000}],
		["agreements", {"action":A.AgreementInspect,"id":2147483000}],
		["trade", {"action":A.TradeUpdate,"depot_id":2147483000,"expected_revision":9007199254740993,"requested":1}]]:
		sequence = world.management_request(pair[0], pair[1])
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == pair[1].action)
	# Missing identities/receipts and create fields have stable local errors.
	for action in [A.WorkOrderInspect,A.WorkOrderUpdate,A.WorkOrderDelete,A.WorkOrderCondition]:
		reject_work_order({"action":action}, "Missing management field: id")
		if action != A.WorkOrderInspect:
			reject_work_order({"action":action,"id":0}, "Missing management field: expected_revision")
	reject_work_order({"action":A.WorkOrderCreate}, "Missing management field: recipe")
	reject_work_order({"action":A.WorkOrderCreate,"recipe":"Carpenters:10:-1"}, "Missing management field: remaining")
	for key in ["id","expected_revision","cursor","remaining","frequency","workshop_id",
		"max_workshops","condition_kind","condition_index","compare","threshold","item_type",
		"target_order","dependency","candidate_kind"]:
		for bad in [1.5,"1",true]:
			var request := {"action":A.WorkOrderList}
			request[key] = bad
			reject_work_order(request, "Wrong management field type: " + key)
	for key in ["recipe","query","remove_condition"]:
		var request := {"action":A.WorkOrderList}
		request[key] = 1
		reject_work_order(request, "Wrong management field type: " + key)
	var bounds := {"id":[-2,2147483648],"expected_revision":[-1],"cursor":[-1,4294967296],
		"remaining":[-2,32768],"frequency":[-2,5],"workshop_id":[-3,2147483648],
		"max_workshops":[-2,32768],"condition_kind":[-1,2],"condition_index":[-2,64],
		"compare":[-2,6],"threshold":[-2,2147483648],"item_type":[-2,32768],
		"target_order":[-2,2147483648],"dependency":[-2,2],"candidate_kind":[-1,3],
		"recipe":["x".repeat(129),String.chr(233).repeat(65)],"query":["x".repeat(129),String.chr(233).repeat(65)]}
	for key in bounds:
		for bad in bounds[key]:
			var request := {"action":A.WorkOrderList}
			request[key] = bad
			reject_work_order(request, "Invalid bounded work order request")
	var requests := [
		{"action":A.WorkOrderList,"query":"bed","cursor":71},
		{"action":A.WorkOrderInspect,"id":0},
		{"action":A.WorkOrderCreate,"recipe":"Carpenters:10:-1","remaining":0,"frequency":2,"workshop_id":4,"max_workshops":3},
		{"action":A.WorkOrderUpdate,"id":2147483000,"expected_revision":9007199254740993,"remaining":12,"frequency":4,"max_workshops":3},
		{"action":A.WorkOrderDelete,"id":0,"expected_revision":9007199254740993},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_kind":0,"condition_index":-1,"compare":3,"threshold":10,"item_type":2},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_kind":1,"condition_index":0,"target_order":9,"dependency":1},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_index":0,"remove_condition":true},
		{"action":A.WorkOrderCandidates,"candidate_kind":0,"query":"bed","cursor":4},
		{"action":A.WorkOrderCandidates,"candidate_kind":1,"query":"bed","cursor":4},
		{"action":A.WorkOrderCandidates,"candidate_kind":2,"query":"bed","cursor":4},
		{"action":A.WorkOrderCatalog},
		{"action":A.WorkOrderList,"query":"x".repeat(128)}]
	for request in requests:
		sequence = world.management_request("work_orders", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert_work_order(state.work_order)
	# Host signals only after validating every expected payload.
	for i in 300:
		if FileAccess.get_file_as_string(status_path) == "passed": break
		await create_timer(0.01).timeout
	assert(FileAccess.get_file_as_string(status_path)=="passed")
	finish(0,"MANAGEMENT_CONTRACT_TEST_PASS")

func reject_work_order(request: Dictionary, error: String) -> void:
	assert(world.management_request("work_orders", request) == 0)
	assert(world.last_error() == error)

func assert_work_order(work: Dictionary) -> void:
	# Full dictionary equality detects missing, misspelled and incorrectly decoded fields.
	assert(work == {
		"orders":[{
			"id":0,"revision":9007199254740993,"name":"Make wooden bed","total":12,"remaining":3,
			"frequency":1,"validated":true,"active":false,"finished_year":106,"finished_tick":400000,
			"workshop_id":4,"max_workshops":2,"generated_jobs":[555],"editable":false,
			"reason":"Finish outstanding jobs before editing","conditions":[
				{"kind":0,"index":0,"description":"BLOCKS LessThan 10","editable":true,"compare":3,
				"threshold":10,"item_type":2,"target_order":-1,"dependency":-1,"satisfied":false},
				{"kind":1,"index":0,"description":"Order #9 Completed","editable":true,"compare":-1,
				"threshold":-1,"item_type":-1,"target_order":9,"dependency":1,"satisfied":true}]},
			{"id":9,"revision":17,"name":"Any shop order","total":0,"remaining":0,"frequency":4,
			"validated":false,"active":true,"finished_year":-1,"finished_tick":-1,"workshop_id":-1,
			"max_workshops":0,"generated_jobs":[],"editable":true,"reason":"Your manager approves new or changed orders","conditions":[]}],
		"recipes":[{"key":"Carpenters:10:-1","name":"make bed"}],
		"choices":[{"id":4,"name":"Carpenter's Workshop #4"}],
		"managers":[{"unit_id":42,"name":"Urist","position":"Manager","offices":[1492,1493],"job":"Validate work orders"}],
		"next_cursor":71,"detail":"Role and office presence are observations, not approval."})
