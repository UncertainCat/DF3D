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

func receipt(sequence: int, expected_status: int = S.Ok) -> Dictionary:
	for i in 300:
		var value: Dictionary = world.poll_management()
		if int(value.get("request_seq",0)) == sequence and int(value.get("status",S.Idle)) in [S.Ok, S.Rejected]:
			assert(value.status == expected_status)
			return value if value.status == expected_status else {}
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
	for bad_revision in ["1", 1.0, true]:
		assert(world.construction_request({"action":A.Place,"definition":"Chair",
			"origin":Vector3i(1,2,3),"selections":[{"filter":0,"count":1,
			"expected_list_revision":bad_revision}]})==0)
		assert(str(world.last_error())=="Wrong construction selection field type: expected_list_revision")
	assert(world.construction_request({"action":A.Place,"definition":"Chair",
		"origin":Vector3i(1,2,3),"selections":[{"filter":0,"count":1,"expected_list_revision":-2}]})==0)
	assert(str(world.last_error())=="Invalid construction selection")
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
		"origin":Vector3i(11,12,13),"selections":[{"filter":0,"count":1,"expected_list_revision":9223372036854775807}]})
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
		"target_order","dependency","candidate_kind","move","expected_neighbor","expected_list_revision",
		"item_subtype","mat_type","mat_index","input_index","group_type","group_subtype","group_custom","encrust_flags"]:
		for bad in [1.5,"1",true]:
			var request := {"action":A.WorkOrderList}
			request[key] = bad
			reject_work_order(request, "Wrong management field type: " + key)
	for key in ["recipe","query","remove_condition"]:
		var request := {"action":A.WorkOrderList}
		request[key] = 1
		reject_work_order(request, "Wrong management field type: " + key)
	for bad in ["f1:0", PackedStringArray(["f1:0"]), [1], ["f1:0", null]]:
		reject_work_order({"action":A.WorkOrderList,"traits":bad}, "Work-order traits must be an Array of String")
	var bounds := {"id":[-2,2147483648],"expected_revision":[-1],"cursor":[-1,4294967296],
		"remaining":[-2,32768],"frequency":[-2,5],"workshop_id":[-3,2147483648],
		"max_workshops":[-2,32768],"condition_kind":[-1,2],"condition_index":[-2,64],
		"compare":[-2,6],"threshold":[-2,2147483648],"item_type":[-2,32768],
		"target_order":[-2,2147483648],"dependency":[-2,2],"candidate_kind":[-1,6],"move":[-2,2],"expected_neighbor":[-2,2147483648],
		"expected_list_revision":[-1],"item_subtype":[-2,32768],"mat_type":[-2,32768],"mat_index":[-2,2147483648],
		"input_index":[-2,32768],"group_type":[-2,32768],"group_subtype":[-2,32768],
		"group_custom":[-2,2147483648],"encrust_flags":[-2,2147483648],"traits":[["x".repeat(65)]],
		"recipe":["x".repeat(129),String.chr(233).repeat(65)],"query":["x".repeat(65),String.chr(233).repeat(33)]}
	for key in bounds:
		for bad in bounds[key]:
			var request := {"action":A.WorkOrderList}
			request[key] = bad
			reject_work_order(request, "Invalid bounded work order request")
	var work_list_revision: int = 0
	var requests := [
		{"action":A.WorkOrderList,"query":"bed","cursor":71},
		{"action":A.WorkOrderInspect,"id":0},
		{"action":A.WorkOrderCreate,"recipe":"Carpenters:10:-1","remaining":0,"frequency":2,"workshop_id":4,"max_workshops":3},
		{"action":A.WorkOrderUpdate,"id":2147483000,"expected_revision":9007199254740993,"remaining":12,"frequency":4,"max_workshops":3},
		{"action":A.WorkOrderDelete,"id":0,"expected_revision":9007199254740993},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_kind":0,"condition_index":-1,"compare":3,"threshold":10,"item_type":2,"item_subtype":3,"mat_type":419,"mat_index":7,"traits":["f1:0","rc:X"]},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_kind":1,"condition_index":0,"target_order":9,"dependency":1},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"condition_index":0,"remove_condition":true},
		{"action":A.WorkOrderCandidates,"candidate_kind":0,"query":"bed","cursor":4},
		{"action":A.WorkOrderCandidates,"candidate_kind":1,"query":"bed","cursor":4},
		{"action":A.WorkOrderCandidates,"candidate_kind":2,"query":"bed","cursor":4},
		{"action":A.WorkOrderCatalog,"group_type":0,"group_subtype":0,"group_custom":-1,"expected_list_revision":9223372036854775807},
		{"action":A.WorkOrderList,"query":"x".repeat(64)}]
	for request in requests:
		sequence = world.management_request("work_orders", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert_work_order(state.work_order, request.action == A.WorkOrderCatalog)
		work_list_revision = state.work_order.list_revision
	# Every required citizen mutation field is checked independently before transport.
	for request in [{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":1},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":1}]:
		for key in request:
			if key == "action": continue
			var missing: Dictionary = request.duplicate()
			missing.erase(key)
			reject_citizen(missing, "Missing management field: " + key)
	for key in ["unit_id","detail_index","expected_revision","cursor","member","mode"]:
		for bad in [1.5,"1",true]:
			var invalid := {"action":28}
			invalid[key] = bad
			reject_citizen(invalid, "Wrong management field type: " + key)
	reject_citizen({"action":28,"query":1}, "Wrong management field type: query")
	for mode in [0,4]:
		reject_citizen({"action":33,"detail_index":1,"expected_revision":7,"mode":mode}, "Invalid bounded citizen request")
	reject_citizen({"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":2}, "Invalid bounded citizen request")
	for query in ["x".repeat(129),String.chr(233).repeat(65)]:
		reject_citizen({"action":30,"query":query}, "Invalid bounded citizen request")
	var citizen_requests := [{"action":30,"query":"","cursor":0}, {"action":30,"query":"","cursor":16},
		{"action":31,"detail_index":1}, {"action":31,"detail_index":1,"unit_id":0},
		{"action":28,"query":"Citizen","cursor":0}, {"action":28,"query":"Citizen","cursor":32},
		{"action":29,"unit_id":0},
		{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":1},
		{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":0},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":1},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":2},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":3},
		# Codec-only editability sentinel, deliberately beyond current citizens.lua output;
		# social_activity is bridge-produced (bridge/plugin/management.cpp:402-409) and
		# this fixture exercises that path.
		{"action":31,"detail_index":1,"unit_id":0,"query":"codec sentinels"}]
	for request in citizen_requests:
		sequence = world.management_request("citizens", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		var c: Dictionary = state.citizen
		assert(not c.external_controller)
		assert(c.detail == "Existing work details only. Roles and office ownership are read-only; appointments are not exposed.")
		if request.action == 30:
			assert(c.details.size() == (16 if request.cursor == 0 else 2))
			assert(c.next_cursor == (16 if request.cursor == 0 else 0))
			assert(c.selected_detail == -1 and c.selected_unit == -1 and c.citizens.is_empty())
			for d in c.details: assert_citizen_detail(d)
		elif request.action == 28:
			assert(c.citizens.size() == (32 if request.cursor == 0 else 2))
			assert(c.next_cursor == (32 if request.cursor == 0 else 0))
			assert(c.details.is_empty() and c.selected_unit == -1)
			for u in c.citizens: assert_citizen_person(u, false)
		elif request.action == 29:
			assert(c.selected_unit == 0 and c.citizens.size() == 1 and c.details.is_empty())
			assert_citizen_person(c.citizens[0], true)
		else:
			assert(c.selected_detail == 1 and c.details.size() == 1 and c.next_cursor == 0)
			assert_citizen_detail(c.details[0], request.get("mode",1), request.get("member",1), request.get("query", "") == "codec sentinels")
			assert(c.selected_unit == request.get("unit_id",-1))
			assert(c.citizens.size() == (1 if request.has("unit_id") else 0))
			for u in c.citizens: assert_citizen_person(u, true, request.get("member",1), request.get("query", "") == "codec sentinels")
	# Echo the fixture revision through move and paging without float conversion.
	for request in [
		{"action":A.WorkOrderUpdate,"id":0,"expected_revision":9007199254740993,"move":-1,"expected_neighbor":9,"expected_list_revision":work_list_revision},
		{"action":A.WorkOrderUpdate,"id":0,"expected_revision":9007199254740993,"input_index":0,"mat_type":0,"mat_index":5,"encrust_flags":1092},
		{"action":A.WorkOrderCondition,"id":0,"expected_revision":9007199254740993,"compare":0,"threshold":0,"item_type":-1,"traits":[]}]:
		sequence = world.management_request("work_orders", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert_work_order(state.work_order, request.action == A.WorkOrderCatalog)
	for malformed in [0, "", {}, true]:
		assert(world.management_request("construction", {"action":A.Place,"definition":"Chair",
			"origin":Vector3i.ZERO,"selections":malformed}) == 0)
		assert(world.last_error() == "Wrong management field type: selections")
	assert(world.management_request("construction", {"action":A.Place,"definition":"Chair",
		"origin":Vector3i.ZERO,"selections":[0]}) == 0)
	assert(world.last_error() == "Construction selection must be a dictionary")
	assert(Contract.domain_of(A.ConstructionMaterials) == "construction")
	assert(not Contract.is_mutation(A.ConstructionMaterials))
	for request in [
		{"action":A.ConstructionMaterials,"definition":"Chair","origin":Vector3i.ZERO,"filter":0,"expected_list_revision":9223372036854775807},
		{"action":A.Preview,"definition":"Construction:Stairs","origin":Vector3i.ZERO,"depth":3,"selections":[]},
		{"action":A.Preview,"definition":"Bridge","origin":Vector3i.ZERO,"retracting":true}]:
		sequence = world.management_request("construction", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert(state.construction.list_revision is int)
		assert(state.construction.list_revision == 9223372036854775807)
		assert(state.construction.building_key == request.definition)
		assert(state.construction.filter == request.get("filter",-1))
		assert(state.construction.footprint.direction == (4 if request.get("retracting",false) else 0))
	await test_production()
	# Exact local refusals must not consume host requests.
	reject_report({"action":35}, "Missing management field: id")
	reject_report({"action":35,"id":-1}, "invalid report inspection")
	for key in ["id", "before_id"]:
		for bad in [1.5, "1", true]:
			var invalid := {"action":34}
			invalid[key] = bad
			reject_report(invalid, "Wrong management field type: " + key)
	for pair in [["query", 1], ["announcements_only", 1]]:
		var invalid := {"action":34}
		invalid[pair[0]] = pair[1]
		reject_report(invalid, "Wrong management field type: " + pair[0])
	for invalid in [{"action":34,"query":"x".repeat(129)}, {"action":34,"query":String.chr(233).repeat(65)},
		{"action":34,"id":5}, {"action":35,"id":0,"before_id":3}, {"action":35,"id":0,"query":"x"},
		{"action":34,"id":-2}, {"action":34,"before_id":-2}, {"action":35,"id":2147483648}, {"action":34,"before_id":2147483648}]:
		reject_report(invalid, "Invalid bounded report request")
	var report_requests := [{"action":34}, {"action":34,"before_id":1084},
		{"action":34,"id":-1,"before_id":-1,"query":"","announcements_only":false},
		{"action":34,"query":String.chr(233).repeat(64)}, {"action":34,"before_id":0},
		{"action":34,"before_id":2147483647}, {"action":35,"id":0,"query":"","before_id":-1},
		# 41 is a report_ids reference in the session fixture.
		{"action":35,"id":41}, {"action":35,"id":999999}, {"action":35,"id":2147483647}]
	for request in report_requests:
		sequence = world.management_request("reports", request)
		assert(sequence > 0)
		state = await receipt(sequence, S.Rejected if request.get("id", -1) == 999999 else S.Ok)
		assert(not state.is_empty() and state.action == request.action)
		if request.get("id", -1) == 999999:
			assert(state.status == S.Rejected and state.message == "Report no longer exists")
			assert(state.report.announcements_only == false)
			continue
		assert(state.status == S.Ok and state.message == ("Native report" if request.action == 35 else "Native reports"))
		var report: Dictionary = state.report
		assert(report.announcements_only == request.get("announcements_only", true) and report.detail == "")
		# build/evidence/native/e7/findings.md:36: pin bridge newest-first pending 08-B.
		var ids: Array = []
		if request.action == 35: ids = [request.id]
		elif request.get("before_id", -1) == 1084: ids = [1083,41,0]
		elif request.get("before_id", -1) != 0 and request.get("query", "").is_empty():
			for id in range(1099,1083,-1): ids.append(id)
		assert(report.next_before_id == (1084 if ids.size() == 16 else -1))
		assert(report.reports.size() == ids.size())
		for index in ids.size(): assert_report_row(report.reports[index], ids[index])
	await test_agreements()
	# Host signals only after validating every expected payload.
	for i in 300:
		if FileAccess.get_file_as_string(status_path) == "passed": break
		await create_timer(0.01).timeout
	assert(FileAccess.get_file_as_string(status_path)=="passed")
	finish(0,"MANAGEMENT_CONTRACT_TEST_PASS")

func reject_work_order(request: Dictionary, error: String) -> void:
	assert(world.management_request("work_orders", request) == 0)
	assert(world.last_error() == error)

func assert_work_order(work: Dictionary, progress: bool = false) -> void:
	if progress:
		# work_orders.lua:651-653,676: progress has no candidate or order rows.
		assert(work == {"orders":[],"recipes":[],"choices":[],"managers":[],
			"materials":[],"traits":[],"types":[],"groups":[],"tasks":[],
			"total":0,"list_revision":0,"build_phase":3,"build_done":17,"build_total":128,
			"next_cursor":0,"detail":""})
		return
	# Full dictionary equality detects missing, misspelled and incorrectly decoded fields.
	assert(work == {
		"orders":[{
			"id":0,"revision":9007199254740993,"name":"Make wooden bed","total":12,"remaining":3,
			"frequency":1,"validated":true,"active":false,"finished_year":106,"finished_tick":400000,
			"workshop_id":4,"max_workshops":2,"generated_jobs":[555],"editable":false,
			"reason":"Finish outstanding jobs before editing",
			"position":0,"detail_kind":2,"size_raw":42,"encrust_flags":1092,"mat_type":0,"mat_index":5,"material_category":2,
			"inputs":[{"index":0,"description":"","mat_type":0,"mat_index":5,"editable":false}],"conditions":[
				{"kind":0,"index":0,"description":"BLOCKS LessThan 10; DF3D estimate: 6 matching (rule met)","editable":true,"compare":3,
				"threshold":10,"item_type":2,"target_order":-1,"dependency":-1,"satisfied":true,
				"item_subtype":3,"mat_type":419,"mat_index":7,"traits":["f1:0","rc:X"],"satisfaction":2,"estimated":true,"estimate_count":6},
				{"kind":1,"index":0,"description":"Order #9 Completed; Satisfied for next check","editable":true,"compare":-1,
				"threshold":-1,"item_type":-1,"target_order":9,"dependency":1,"satisfied":true,
				"item_subtype":-1,"mat_type":-1,"mat_index":-1,"traits":[],"satisfaction":2,"estimated":false,"estimate_count":-1}]},
			{"id":9,"revision":17,"name":"Any shop order","total":0,"remaining":0,"frequency":4,
			"validated":false,"active":true,"finished_year":-1,"finished_tick":-1,"workshop_id":-1,
			"max_workshops":0,"generated_jobs":[],"editable":true,"reason":"Your manager approves new or changed orders","conditions":[],
			"position":1,"detail_kind":0,"size_raw":-1,"encrust_flags":0,"mat_type":-1,"mat_index":-1,"material_category":0,"inputs":[]}],
		"recipes":[{"key":"Carpenters:10:-1","name":"make bed"}],
		"choices":[{"id":4,"name":"Carpenter's Workshop #4"}],
		"managers":[{"unit_id":42,"name":"Urist","position":"Manager","offices":[1492,1493],"job":"Validate work orders"}],
		"materials":[{"mat_type":0,"mat_index":5,"name":"material"}],
		"traits":[{"key":"rc:X","name":""}],"types":[{"item_type":2,"item_subtype":3,"name":"type"}],
		"groups":[{"type":0,"subtype":0,"custom":-1,"name":"Carpenter's Workshop","count":1}],
		"tasks":[{"key":"0:1:a0:0:0:1:/1:21:0","name":"Bed order -1","job_type":10,"reaction":"","item_type":-1,"item_subtype":-1,"mat_type":-1,"mat_index":-1}],
		"total":128,"list_revision":9223372036854775807,"build_phase":0,"build_done":0,"build_total":0,
		"next_cursor":71,"detail":"Role and office presence are observations, not approval."})

func reject_citizen(request: Dictionary, error: String) -> void:
	assert(world.management_request("citizens", request) == 0)
	assert(world.last_error() == error)

func assert_citizen_detail(d: Dictionary, mode: int = 1, member: int = 1, synthetic: bool = false) -> void:
	var index: int = d.index
	assert(d == {"index":index,"revision":7,
		"name":"Miners" if index == 0 else "Custom" if index == 1 else "Detail %d" % index,
		"mode":mode if index == 1 else 3,"no_modify":index == 0,"cannot_be_everybody":index == 0,
		"editable":true,"mode_editable":not synthetic,"reason":"Native work-detail mode is protected" if synthetic else "","labors":[0] if index == 0 else [0,1],
		"labor_names":["mine"] if index == 0 else ["mine","haul stone"],"assigned_units":[0] if index == 1 and member == 1 else []})

func assert_citizen_person(u: Dictionary, inspected: bool, member: int = 1, synthetic: bool = false) -> void:
	assert(u == {"id":u.id,"name":"Citizen %d" % u.id,"profession":"Carpenter" if u.id == 0 else "Miner",
		"job":"Socialize" if synthetic else "Dig" if u.id == 0 else "No current job",
		"reason":"","age":42,"stress":10,"has_stress":true,"origin":Vector3i(1,2,3),
		"can_focus":true,"eligible":true,"only_assigned_jobs":synthetic or u.id == 1,
		"assigned_details":[{"index":1,"icon":9,"name":"Custom"}] if u.id == 0 and member == 1 else [],
		"profession_color":14 if u.id == 0 else 7,"profession_id":2 if u.id == 0 else 0,
		"job_type":-1 if synthetic else 5 if u.id == 0 else -1,"social_activity":synthetic,
		"labors":[0,1] if inspected else [],"labor_names":["mine","haul stone"] if inspected else [],
		"roles":[{"name":"Manager","required_office":250}] if inspected else [],"offices":[]})

func reject_production(request: Dictionary, error: String) -> void:
	assert(world.management_request("production", request) == 0)
	assert(world.last_error() == error)

func test_production() -> void:
	for request in [{"action":16,"building_id":1}, {"action":17,"building_id":1,"recipe":"builtin:114:2"},
		{"action":18,"building_id":1,"job_id":12}, {"action":19,"building_id":3,"season":0,"crop_id":-1}]:
		for key in request:
			if key == "action": continue
			var missing: Dictionary = request.duplicate()
			missing.erase(key)
			reject_production(missing, "Missing management field: " + key)
	for key in ["building_id","job_id","crop_id","cursor","repeat","suspend","season"]:
		for bad in [1.5,"1",true]:
			var request := {"action":15}
			request[key] = bad
			reject_production(request, "Wrong management field type: " + key)
	for key in ["recipe","query","cancel"]:
		var request := {"action":15}
		request[key] = 1
		reject_production(request, "Wrong management field type: " + key)
	var bounds := {"building_id":[-2,2147483648],"job_id":[-2,2147483648],"cursor":[-1,4294967296],
		"repeat":[2],"suspend":[-2],"season":[4],"crop_id":[32768],
		"recipe":["x".repeat(129),String.chr(233).repeat(65)],"query":["x".repeat(129),String.chr(233).repeat(65)]}
	for key in bounds:
		for bad in bounds[key]:
			var request := {"action":15}
			request[key] = bad
			reject_production(request, "Invalid bounded production request")
	for request in [{"action":18,"building_id":1,"job_id":12,"cancel":true,"repeat":1},
		{"action":18,"building_id":1,"job_id":12}]:
		reject_production(request, "invalid job edit")
	var requests := [{"action":15,"query":"","cursor":0}, {"action":16,"building_id":1},
		{"action":16,"building_id":3}, {"action":17,"building_id":1,"recipe":"builtin:114:2","repeat":0},
		{"action":17,"building_id":1,"recipe":"builtin:114:2","repeat":1},
		{"action":18,"building_id":1,"job_id":10,"repeat":0}, {"action":18,"building_id":1,"job_id":10,"repeat":1},
		{"action":18,"building_id":1,"job_id":10,"suspend":0}, {"action":18,"building_id":1,"job_id":10,"suspend":1},
		{"action":18,"building_id":1,"job_id":12,"cancel":true}]
	for season in 4:
		for crop in [0,-1]: requests.append({"action":19,"building_id":3,"season":season,"crop_id":crop})
	requests.append({"action":15,"query":"#1024","cursor":1024})
	for request in requests:
		var sequence: int = world.management_request("production", request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert_production(state.production, request)

func assert_production(p: Dictionary, request: Dictionary) -> void:
	var building := {"id":1,"name":"Kitchen","kind":"Kitchen","origin":Vector3i(5,6,2),"build_stage":2,"max_stage":3,"queue_size":2}
	var farm := {"id":3,"name":"Farm","kind":"FarmPlot","origin":Vector3i(5,6,2),"build_stage":2,"max_stage":3,"queue_size":0}
	# Mutations require complete construction (production.lua:221).
	if request.action >= 17:
		building.build_stage = 3
		farm.build_stage = 3
	var expected := {"buildings":[],"recipes":[],"jobs":[],"crops":[],"seasonal_crops":[],
		"next_cursor":0,"current_season":-1,"selected_building":request.get("building_id",-1),"created_job":-1,"detail":""}
	if request.action == 15:
		var carp: Dictionary = building.duplicate()
		carp.merge({"id":0,"name":"Carpenters","kind":"Carpenters","queue_size":0},true)
		expected.buildings = [carp,farm]
		expected.next_cursor = 1024
		if request.cursor == 1024:
			carp.id = 1024
			expected.buildings = [carp]
			expected.next_cursor = 0
	elif request.building_id == 3:
		expected.buildings = [farm]
		expected.crops = [{"id":0,"name":"allseason","seasons":15,"seeds":600},{"id":1,"name":"spring only","seasons":1,"seeds":0}]
		expected.seasonal_crops = [0,-1,0,-1]
		if request.action == 19: expected.seasonal_crops[request.season] = request.crop_id
		expected.current_season = 0
		expected.detail = "Seasonal crop selection; seed counts are informational. Fertilization and new farm placement are not yet exposed."
	else:
		expected.buildings = [building]
		var needs := [{"description":"NONE, unrotten, cookable, solid","quantity":1,"item_type":-1},{"description":"NONE, unrotten, cookable","quantity":1,"item_type":-1}]
		expected.recipes = [{"key":"builtin:114:2","name":"prepare easy meal","requirements":needs}]
		expected.jobs = [
			{"id":10,"name":"job 10","job_type":114,"repeat":true,"suspended":false,
			"worker_id":7,"worker_name":"Worker","completion_timer":17,"attached_items":1,"editable":true,"status":"Worker assigned","requirements":needs},
			{"id":11,"name":"job 11","job_type":114,"repeat":false,"suspended":true,"worker_id":-1,"worker_name":"",
			"completion_timer":-1,"attached_items":0,"editable":true,"status":"Suspended by native state","requirements":needs}]
		if request.action == 18 and not request.get("cancel",false):
			if request.has("repeat"): expected.jobs[0].repeat = request.repeat == 1
			if request.get("suspend",-1) == 1:
				expected.jobs[0].suspended = true
				expected.jobs[0].worker_id = -1
				expected.jobs[0].worker_name = ""
				expected.jobs[0].status = "Suspended by native state"
		if request.action == 17:
			building.queue_size = 3
			expected.jobs.append({"id":12,"name":"job 12","job_type":114,"repeat":request.repeat == 1,
				"suspended":false,"worker_id":-1,"worker_name":"","completion_timer":-1,"attached_items":0,
				"editable":true,"status":"Awaiting worker or inputs; native cause is not exposed","requirements":needs})
		expected.created_job = 12 if request.action == 17 else -1
		expected.detail = "Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed. Workshop restricts workers (2)."
	assert(p == expected)

func reject_report(request: Dictionary, message: String) -> void:
	assert(world.management_request("reports", request) == 0)
	assert(world.last_error() == message)

func assert_report_row(row: Dictionary, id: int) -> void:
	assert(row.id == id)
	assert(row.category == ("MOOD_BUILDING_CLAIMED" if id == 1098 else "Unknown" if id == 1097 else "CANCEL_JOB"))
	assert(row.text == ("x".repeat(16384) if id == 1096 else "Doren Thosbutalath, Dwarven Child cancels Store item in stockpile: Item inaccessible."))
	assert(row.year == 106 and row.year_tick == 139200 and row.repeat_count == 2)
	assert(row.continuation == (id == 1099) and row.text_complete == (id != 1096))
	assert(row.position_visible == (id != 1097) and row.position2_visible == (id not in [1097,1098]))
	assert(row.position == (Vector3i(-1,-1,-1) if id == 1097 else Vector3i(2,3,4)))
	assert(row.position2 == (Vector3i(-1,-1,-1) if id in [1097,1098] else Vector3i(5,6,7)))

func reject_agreement(request: Dictionary, message: String) -> void:
	assert(world.management_request("agreements", request) == 0)
	assert(world.last_error() == message)

func test_agreements() -> void:
	reject_agreement({"action":37}, "Missing management field: id")
	reject_agreement({"action":37,"id":-1}, "invalid agreement inspection")
	for key in ["id","before_id"]:
		for bad in [1.5,"1",true]:
			var request := {"action":36}
			request[key] = bad
			reject_agreement(request, "Wrong management field type: " + key)
	for pair in [["query",1],["query",[]],["pending_only",1],["pending_only",""]]:
		var request := {"action":36}
		request[pair[0]] = pair[1]
		reject_agreement(request, "Wrong management field type: " + pair[0])
	for request in [{"action":36,"query":"q".repeat(129)}, {"action":36,"query":String.chr(233).repeat(65)},
		{"action":36,"id":5}, {"action":36,"id":0}, {"action":37,"id":212,"before_id":3},
		{"action":37,"id":212,"query":"guild"}, {"action":37,"id":212,"pending_only":true},
		{"action":36,"id":-2}, {"action":36,"before_id":-2},
		{"action":37,"id":2147483648}, {"action":36,"before_id":2147483648}]:
		reject_agreement(request, "Invalid bounded agreement request")
	var requests := [{"action":36}, {"action":36,"pending_only":true}, {"action":36,"query":"guild"},
		{"action":36,"query":"205"}, {"action":36,"before_id":205}, {"action":37,"id":212},
		{"action":37,"id":0,"before_id":-1,"query":"","pending_only":false}, {"action":37,"id":2147483000},
		{"action":36,"query":"q".repeat(128)}, {"action":36,"id":-1,"before_id":0,"query":"","pending_only":false},
		{"action":36,"before_id":2147483647}, {"action":37,"id":2147483647}]
	for index in requests.size():
		var request: Dictionary = requests[index]
		var sequence: int = world.management_request("agreements", request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action and state.message == "Native agreements")
		var ids: Array = [212,205,190,150,120]
		if index == 1: ids = [212,190]
		elif index == 2: ids = [212,120]
		elif index == 3: ids = [205]
		elif index == 4: ids = [190,150,120]
		elif request.action == 37: ids = [request.id]
		elif index in [8,9]: ids = []
		var rows: Array = []
		for id in ids: rows.append(agreement_row(id, request.action == 37))
		assert(state.agreement == {"agreements":rows,"next_before_id":-1,"pending_only":index == 1,
			"detail":"Pending means a native unapproved petition. Accepted and concluded are native states; no denial or expiry is inferred."})

func agreement_row(id: int, inspect: bool) -> Dictionary:
	var source := 212 if inspect else id
	var partial := source in [190,150]
	var pending := source in [212,190]
	var temple := source == 205
	# agreements.lua:35-57; e8/findings.md Native wording and e12/findings.md 2,4:
	# pin enum descriptions; native captions require 07-B bridge work.
	var description := ("Residency" if source == 190 else "Citizenship") if partial else ("TEMPLE tier 1 / The Bejeweled Creed" if temple else "GUILDHALL tier 1 for MASON")
	var reason := "Partial record: some native subject terms are not yet displayed" if partial else ""
	if pending: reason += ("; " if partial else "") + "Pending native petition; response controls are not yet verified"
	return {"id":id,"status":0 if pending else 2 if source == 150 else 3 if source == 120 else 1,
		"not_approved":pending or source == 150,"concluded":source == 120,"continuing":temple,"complete":not partial,
		"summary":description,"reason":reason,
		"details":[{"id":0,"kind":(2 if source == 190 else 3) if partial else 12,"site_id":378,"year":106,"year_tick":168260,
			"applicant_party":0,"government_party":1,"location_type":-1 if partial else 2 if temple else 11,
			"tier":-1 if partial else 1,"profession":-1 if partial or temple else 9,"deity_type":1 if temple else -1,
			"deity_id":2210 if temple else -1,"description":description}],
		"parties":[{"id":0,"name":"Urist Lorbamoth" if partial else "The Bejeweled Creed" if temple else "The Whiskered Guild",
			"entity_ids":[] if partial else [2210] if temple else [780],"histfig_ids":[5120] if partial else []},
			{"id":1,"name":"The Iron Realm","entity_ids":[483],"histfig_ids":[]}]}
