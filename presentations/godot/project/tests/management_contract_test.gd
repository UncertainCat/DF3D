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

	sequence = world.area_request({"action":A.AreaUpdate,"id":2147483000,"kind":Contract.AreaKind.Zone,"expected_revision":9007199254740993})
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
		["production", {"action":A.FarmEdit,"building_id":1,"crop_id":32768,"season":0,"expected_revision":17}],
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
	var citizen_requests := [{"action":30,"query":"","cursor":0}, {"action":30,"query":"","cursor":16,"expected_list_revision":9223372036854775807},
		{"action":31,"detail_index":1}, {"action":31,"detail_index":1,"unit_id":0},
		{"action":28,"query":"Citizen","cursor":0}, {"action":28,"query":"Citizen","cursor":32},
		{"action":29,"unit_id":0},
		{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":1},
		{"action":32,"detail_index":1,"expected_revision":7,"unit_id":0,"member":0},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":1},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":2},
		{"action":33,"detail_index":1,"expected_revision":7,"mode":3},
		{"action":31,"detail_index":1,"unit_id":0,"query":"codec sentinels"}]
	for request in citizen_requests:
		sequence = world.management_request("citizens", request)
		assert(sequence > 0)
		state = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		var c: Dictionary = state.citizen
		var sentinels: bool = request.get("query", "") == "codec sentinels"
		assert(c.external_controller == sentinels)
		assert(c.detail == "Roles and office ownership are read-only; appointments are not exposed.")
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
			assert_citizen_detail(c.details[0], request.get("mode",1), request.get("member",1), sentinels)
			assert(c.selected_unit == request.get("unit_id",-1))
			assert(c.citizens.size() == (1 if request.has("unit_id") else 0))
			for u in c.citizens: assert_citizen_person(u, true, request.get("member",1), sentinels)
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
	for key in ["id", "before_id", "notification_category"]:
		for bad in [1.5, "1", true]:
			var invalid := {"action":34}
			invalid[key] = bad
			reject_report(invalid, "Wrong management field type: " + key)
	for pair in [["query", 1], ["announcements_only", 1], ["alert_button", 1]]:
		var invalid := {"action":34}
		invalid[pair[0]] = pair[1]
		reject_report(invalid, "Wrong management field type: " + pair[0])
	for invalid in [{"action":34,"query":"x".repeat(129)}, {"action":34,"query":String.chr(233).repeat(65)},
		{"action":34,"id":5}, {"action":35,"id":0,"before_id":3}, {"action":35,"id":0,"query":"x"},
		{"action":34,"id":-2}, {"action":34,"before_id":-2}, {"action":35,"id":2147483648}, {"action":34,"before_id":2147483648}]:
		reject_report(invalid, "Invalid bounded report request")
	for invalid in [{"action":34,"view":6}, {"action":34,"view":6,"notification_category":37},
		{"action":34,"view":6,"notification_category":20,"alert_button":true},
		{"action":34,"view":6,"notification_category":20,"cursor":1},
		{"action":35,"view":5,"id":1,"notification_category":20},
		{"action":35,"view":5,"id":1,"notification_category":20,"expected_list_revision":1,"tab":1},
		{"action":35,"view":5,"id":1,"notification_category":20,"expected_list_revision":1,"unit_id":17,"unit_category":1}]:
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
	await test_work_detail_edits()
	await test_area_operations()
	await test_location_names()
	await test_location_recognition()
	await test_location_religious_staff()
	await test_location_religious_assignment()
	await test_location_specialization()
	await test_location_staff_assignments()
	assert(Contract.is_mutation(A.DismissAlert) and not Contract.is_mutation(A.PrepareAlertDismissal))
	for request in [{"action":A.DismissAlert},{"action":A.DismissAlert,"expected_list_revision":0},
		{"action":A.PrepareAlertDismissal,"expected_list_revision":1},
		{"action":A.DismissAlert,"expected_list_revision":1.0},
		{"action":A.DismissAlert,"expected_list_revision":1,"alert_button":true}]:
		assert(world.management_request("reports",request)==0)
	sequence=world.management_request("reports",{"action":A.PrepareAlertDismissal})
	assert(sequence>0)
	state=await receipt(sequence)
	assert(state.report.list_revision==9007199254740993 and state.report.total==4)
	sequence=world.management_request("reports",{"action":A.DismissAlert,"expected_list_revision":state.report.list_revision})
	assert(sequence>0)
	state=await receipt(sequence)
	assert(state.report.list_revision==9007199254740993 and state.report.total==4)

	for item_id in [47492,47493]:
		var request: Dictionary={"action":A.ProductionInspect,"building_id":968,"item_id":item_id}
		for field in ["item_id","building_id"]:
			var invalid:=request.duplicate();invalid[field]=float(request[field]);assert(world.management_request("production",invalid)==0)
		for fields in [{"contents":true},{"expected_revision":17},{"item_value":0},{"season":0},{"cursor":1}]:
			var invalid:=request.duplicate();invalid.merge(fields,true);assert(world.management_request("production",invalid)==0)
		sequence=world.management_request("production",request);assert(sequence>0);state=await receipt(sequence)
		var item: Dictionary=state.production.item
		assert(item.id==item_id and item.building_id==968 and item.revision==9007199254740993)
		assert(item.item_type==53 and item.material_token=="PLANT:POD_SWEET:SEED" and item.subtype_raw=="")
		assert(item.name=="Synthetic item" and item.weight=="<1" and item.description=="Synthetic description")
		assert(item.forbid and item.hidden and item.can_dump and not item.can_melt and item.completed and not item.removing)
		assert(item.has("holder")==bool(item_id==47492))
		if item.has("holder"):assert(item.holder=={"id":968,"type":4,"name":"Synthetic holder"})
	var locate: Dictionary={"action":A.ProductionInspect,"locate_item":true,"item_id":47492}
	for fields in [{"locate_item":1},{"item_id":47492.0},{"building_id":968},{"contents":true},{"expected_revision":17},{"season":0},{"item_value":0}]:
		var invalid:=locate.duplicate();invalid.merge(fields,true);assert(world.management_request("production",invalid)==0)
	sequence=world.management_request("production",locate);assert(sequence>0);state=await receipt(sequence)
	assert(state.production.item_position=={"id":47492,"position":Vector3i(123,456,17)})
	assert(not state.production.has("item") and not state.production.has("contents") and not state.production.has("farm"))
	assert(Contract.domain_of(A.CreatureKnowledgeRead)=="creature_knowledge" and not Contract.is_mutation(A.CreatureKnowledgeRead))
	for bad in [{"action":A.CreatureKnowledgeRead},
		{"action":A.CreatureKnowledgeRead,"unit_id":86.0,"kind":14,"id":42},
		{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":13,"id":42},
		{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":18,"id":42},
		{"action":A.CreatureKnowledgeRead,"unit_id":-1,"kind":14,"id":42},
		{"action":A.CreatureKnowledgeRead,"unit_id":2147483648,"kind":14,"id":42},
		{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":14,"id":2147483648},
		{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":14,"id":-1},
		{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":14,"id":42,"extra":1}]:
		assert(world.management_request("creature_knowledge",bad)==0)
	for kind in range(14,18):
		sequence=world.management_request("creature_knowledge",{"action":A.CreatureKnowledgeRead,"unit_id":86,"kind":kind,"id":42})
		assert(sequence>0)
		state=await receipt(sequence,S.Rejected if kind in [15,16] else S.Ok)
		var knowledge: Dictionary=state.creature_knowledge
		assert(knowledge.unit_id==86 and knowledge.kind==kind and knowledge.id==42)
		assert(knowledge.outcome==(Contract.CreatureKnowledgeOutcome.Unavailable if kind==15 else Contract.CreatureKnowledgeOutcome.Rejected if kind==16 else Contract.CreatureKnowledgeOutcome.Ready))
		assert(knowledge.text==("" if kind in [15,16] else "[B]Synthetic detail"))
	await test_work_detail_workers()
	await test_work_detail_settings()
	await test_standing_orders()
	await test_hunter_ammunition()
	await test_chores()
	await test_kitchen_menu()
	await test_stone_use()
	await test_stocks_menu()
	# Host signals only after validating every expected payload.
	for i in 300:
		if FileAccess.get_file_as_string(status_path) == "passed": break
		await create_timer(0.01).timeout
	assert(FileAccess.get_file_as_string(status_path)=="passed")
	finish(0,"MANAGEMENT_CONTRACT_TEST_PASS")

func reject_work_order(request: Dictionary, error: String) -> void:
	assert(world.management_request("work_orders", request) == 0)
	assert(world.last_error() == error)

func test_work_detail_edits() -> void:
	for bad_labors in ["1", 1, [1.0], ["1"]]:
		var request := {"action":A.WorkDetailEdit,"detail_index":0,"expected_revision":1,"edit":2,"labors":bad_labors}
		reject_citizen(request, "Citizen labors must be integers" if bad_labors is Array else "Wrong management field type: labors")
	var requests := [
		{"action":A.WorkDetailCreate}, {"action":A.WorkDetailDelete,"detail_index":0},
		{"action":A.WorkDetailEdit,"detail_index":0,"edit":1,"name":"MinersX"},
		{"action":A.WorkDetailEdit,"detail_index":0,"edit":2,"labors":[1]},
		{"action":A.WorkDetailEdit,"detail_index":0,"edit":3},
		{"action":A.CitizenWorkScope,"unit_id":0,"only_assigned":1},
		{"action":A.WorkDetailEdit,"detail_index":0,"edit":1,"name":"UnknownMarker"}]
	for request in requests:
		request.expected_revision = 9223372036854775807
		var sequence: int = world.management_request("citizens", request)
		assert(sequence > 0)
		var uncertain: bool=request.get("name","")=="UnknownMarker"
		var state: Dictionary = await receipt(sequence,S.Rejected if uncertain else S.Ok)
		assert(not state.is_empty())
		var c: Dictionary = state.citizen
		assert(c.outcome_unknown==uncertain)
		if uncertain:
			assert(state.outcome=="unknown" and c.details.is_empty() and c.citizens.is_empty() and c.detail_list_revision==0)
			continue
		assert(c.detail_list_revision == 9223372036854775807)
		assert(c.recalc_done == 1 and c.recalc_total == 5000)
		assert(c.recalc_error == ("Native recalculation failed; labors may be stale" if request.action == A.WorkDetailDelete else ""))
		if request.action == A.WorkDetailCreate:
			assert(c.details[0].name == "Custom Detail 0" and c.details[0].icon == 10)
		elif request.action == A.WorkDetailEdit:
			assert(c.details[0].revision == 9223372036854775807)
			assert(c.details[0].icon == [-2,-1,18][request.edit-1])
			assert(c.details[0].row_error == "Row exceeds name cap")
		elif request.action == A.CitizenWorkScope:
			assert(c.citizens[0].revision == 9223372036854775807 and c.citizens[0].only_assigned_jobs)
			assert(c.citizens[0].portrait_state == 3 and c.citizens[0].row_error == "Row exceeds name cap")

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

func assert_citizen_detail(d: Dictionary, mode: int = 1, member: int = 1, sentinels: bool = false) -> void:
	var index: int = d.index
	var comparable := d.duplicate()
	for key in ["icon","row_error"]: comparable.erase(key)
	assert(comparable == {"index":index,"revision":7,
		"name":"Miners" if index == 0 else "Custom" if index == 1 else "Detail %d" % index,
		"mode":mode if index == 1 else 3,"no_modify":index == 0,"cannot_be_everybody":index == 0,
		"editable":not sentinels,"mode_editable":not sentinels,"reason":"An external labor controller owns assignments" if sentinels else "","labors":[0] if index == 0 else [0,1],
		"labor_names":["Mining"] if index == 0 else ["Mining","Stone Hauling"],"assigned_units":[0] if index == 1 and member == 1 else []})

func assert_citizen_person(u: Dictionary, inspected: bool, member: int = 1, sentinels: bool = false) -> void:
	var comparable := u.duplicate()
	for key in ["revision","detail_member","detail_skill","detail_skill_rating","detail_skill_name","portrait_state","row_error"]: comparable.erase(key)
	assert(comparable == {"id":u.id,"name":"Citizen %d" % u.id,"profession":"Carpenter" if u.id == 0 else "Miner",
		"job":"Socialize" if sentinels else "Dig" if u.id == 0 else "No current job",
		"reason":"","age":42,"stress":10,"has_stress":true,"origin":Vector3i(1,2,3),
		"can_focus":true,"eligible":true,"only_assigned_jobs":u.id == 1,
		"assigned_details":[{"index":1,"icon":9,"name":"Custom" if inspected else ""}] if u.id == 0 and member == 1 else [],
		"profession_color":14 if u.id == 0 else 7,"profession_id":2 if u.id == 0 else 0,
		"job_type":-1 if sentinels else 5 if u.id == 0 else -1,"social_activity":sentinels,
		"labors":[0,1] if inspected else [],"labor_names":["Mining","Stone Hauling"] if inspected else [],
		"roles":[{"name":"Manager","required_office":250}] if inspected else [],"offices":[]})

func reject_production(request: Dictionary, error: String) -> void:
	assert(world.management_request("production", request) == 0)
	assert(world.last_error() == error)

func test_production() -> void:
	for request in [{"action":16,"building_id":1}, {"action":17,"building_id":1,"recipe":"builtin:114:2"},
		{"action":18,"building_id":1,"job_id":12}, {"action":19,"building_id":3,"season":0,"crop_id":-1,"expected_revision":9007199254740993}]:
		for key in request:
			if key == "action": continue
			var missing: Dictionary = request.duplicate()
			missing.erase(key)
			reject_production(missing, "Missing management field: " + key)
	for key in ["building_id","job_id","crop_id","cursor","repeat","suspend","season","expected_revision","farm_operation","seasonal_fertilization"]:
		for bad in [1.5,"1",true]:
			var request := {"action":15}
			request[key] = bad
			reject_production(request, "Wrong management field type: " + key)
	for key in ["recipe","query","cancel","farm_name"]:
		var request := {"action":15}
		request[key] = 1
		reject_production(request, "Wrong management field type: " + key)
	var bounds := {"building_id":[-2,2147483648],"job_id":[-2,2147483648],"cursor":[-1,4294967296],
		"repeat":[2],"suspend":[-2],"season":[4],"crop_id":[32768],"expected_revision":[-1],"farm_operation":[Contract.FarmOperation.WorkerSpecialize+1],"seasonal_fertilization":[2],
		"recipe":["x".repeat(129),String.chr(233).repeat(65)],"query":["x".repeat(129),String.chr(233).repeat(65)]}
	for key in bounds:
		for bad in bounds[key]:
			var request := {"action":15}
			request[key] = bad
			reject_production(request, "Invalid bounded production request")
	for request in [{"action":18,"building_id":1,"job_id":12,"cancel":true,"repeat":1},
		{"action":18,"building_id":1,"job_id":12}]:
		reject_production(request, "invalid job edit")
	reject_production({"action":19,"building_id":3,"season":1,"farm_operation":3,"expected_revision":1},"Missing management field: farm_name")
	reject_production({"action":19,"building_id":3,"season":1,"farm_operation":3,"farm_name":"x".repeat(91),"expected_revision":1},"Invalid bounded production request")
	reject_production({"action":15,"farm_name":""},"unexpected farm name")
	var requests := [{"action":15,"query":"","cursor":0}, {"action":16,"building_id":1},
		{"action":16,"building_id":3}, {"action":17,"building_id":1,"recipe":"builtin:114:2","repeat":0},
		{"action":17,"building_id":1,"recipe":"builtin:114:2","repeat":1},
		{"action":18,"building_id":1,"job_id":10,"repeat":0}, {"action":18,"building_id":1,"job_id":10,"repeat":1},
		{"action":18,"building_id":1,"job_id":10,"suspend":0}, {"action":18,"building_id":1,"job_id":10,"suspend":1},
		{"action":18,"building_id":1,"job_id":12,"cancel":true}]
	for season in 2:
		for crop in [0,-1]: requests.append({"action":19,"building_id":3,"season":season,"crop_id":crop,"expected_revision":9007199254740993})
	for operation in [{"season":2,"farm_operation":1},{"season":2,"farm_operation":2,"seasonal_fertilization":0},
		{"season":3,"farm_operation":2,"seasonal_fertilization":1},{"season":3,"farm_operation":3,"farm_name":"new farm"}]:
		operation.merge({"action":19,"building_id":3,"expected_revision":9007199254740993})
		requests.append(operation)
	requests.append({"action":15,"query":"#1024","cursor":1024})
	for request in requests:
		var sequence: int = world.management_request("production", request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty() and state.action == request.action)
		assert_production(state.production, request)

func assert_production(p: Dictionary, request: Dictionary) -> void:
	if (request.action==A.ProductionInspect and request.building_id==3) or request.action==A.FarmEdit:
		var native_farm: Dictionary=p.farm
		assert(native_farm.revision==9007199254740993 and typeof(native_farm.revision)==TYPE_INT)
		assert(native_farm.building_id==3 and native_farm.current_season==1)
		assert(native_farm.custom_name==("new farm" if request.get("farm_operation",0)==3 else "test farm") and native_farm.header_name=="Test farm")
		assert(not native_farm.removing and not native_farm.removal_suspended and not native_farm.removal_has_worker)
		var selected_season: int=request.season if request.action==A.FarmEdit else 1
		assert(native_farm.selected_season==selected_season)
		var seasons := [175,-1,176,-1]
		if request.action==A.FarmEdit and request.get("farm_operation",0)==0: seasons[selected_season]=request.crop_id
		assert(native_farm.seasonal_crops==seasons)
		assert(native_farm.current_fertilization==4 and native_farm.max_fertilization==29)
		assert(native_farm.pending_fertilization==(25 if request.get("farm_operation",0)==1 else 2))
		assert(native_farm.seasonal_fertilization==(request.seasonal_fertilization!=0 if request.get("farm_operation",0)==2 else true))
		assert(p.farm_edit_outcome==(1 if request.action==A.FarmEdit else 0))
		assert(native_farm.choices==[{"id":176,"name":"Sweet pods","raw_id":"POD_SWEET","seeds_available":false,"current_season_warning":true},
			{"id":175,"name":"Plump helmets","raw_id":"MUSHROOM_HELMET_PLUMP","seeds_available":true,"current_season_warning":false}])
		assert(p.crops.is_empty() and p.seasonal_crops.is_empty())
		return

	var building := {"id":1,"name":"Kitchen","kind":"Kitchen","origin":Vector3i(5,6,2),"build_stage":2,"max_stage":3,"queue_size":2}
	var farm := {"id":3,"name":"Farm","kind":"FarmPlot","origin":Vector3i(5,6,2),"build_stage":2,"max_stage":3,"queue_size":0}
	# Mutations require complete construction (production.lua:221).
	if request.action >= 17:
		building.build_stage = 3
		farm.build_stage = 3
	var expected := {"buildings":[],"recipes":[],"jobs":[],"crops":[],"seasonal_crops":[],
		"next_cursor":0,"current_season":-1,"selected_building":request.get("building_id",-1),"created_job":-1,"detail":"","farm_edit_outcome":0}
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
	for invalid in [{"action":36,"tracker":1},{"action":37,"id":-1,"tracker":true},{"action":36,"tracker":true,"query":"x"},{"action":36,"tracker":true,"pending_only":true},{"action":36,"tracker":true,"before_id":1}]:
		assert(world.management_request("agreements",invalid)==0)
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
		assert(state.agreement == {"agreements":rows,"next_before_id":-1,"pending_only":index == 1,"tracker":false,"tracker_rows":[],
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

func test_location_names() -> void:
	var request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationNameRead,
		"location_site_id":651,"location_id":0}
	for key in ["location_site_id","location_id"]:
		var invalid := request.duplicate(true);invalid.erase(key)
		assert(world.area_request(invalid)==0)
	var sequence: int=world.area_request(request);assert(sequence>0)
	var state: Dictionary=await receipt(sequence)
	var snapshot: Dictionary=state.area.location_name
	assert(snapshot.revision==9007199254740993 and snapshot.site_id==651 and snapshot.id==0)
	assert(snapshot.native_header=="Synthetic native header" and snapshot.english_header=="Synthetic English header")
	assert(snapshot.value.first_name_bytes==PackedByteArray([130,255]))
	assert(snapshot.value.words==[0,-1,-1,-1,-1,-1,-1] and snapshot.value.parts==[0,8,0,0,0,0,0])
	request.operation=Contract.AreaOperation.LocationNameChoices;request.expected_revision=snapshot.revision
	request.name_query={"component":6,"cursor":37,"query_bytes":PackedByteArray([130,255])}
	for pair in [["component",7],["component",1.5],["cursor",-1],["cursor",4294967296],["query_bytes",[]]]:
		var invalid := request.duplicate(true);invalid.name_query[pair[0]]=pair[1]
		assert(world.area_request(invalid)==0)
	sequence=world.area_request(request);assert(sequence>0)
	state=await receipt(sequence)
	var page: Dictionary=state.area.location_name_page
	assert(page.snapshot==snapshot and page.cursor==37 and page.total==39 and page.next_cursor==0 and not page.truncated)
	assert(page.component==6 and page.query_bytes==PackedByteArray([130,255]))
	assert(page.choices==[{"word":0,"part":0,"english":"Synthetic noun","translated":"Synthetic native"},
		{"word":0,"part":1,"english":"Synthetic plural","translated":"Synthetic native"}])
	request.erase("name_query");request.action=A.AreaUpdate;request.operation=Contract.AreaOperation.LocationNameEdit
	for mode in 4:
		request.name_edit={"mode":mode,"target":-1 if mode==3 else 6,"displayed":-1 if mode==3 else 6,
			"word":0 if mode==1 else -1,"part":1 if mode==1 else -1,
			"query_bytes":PackedByteArray() if mode==3 else PackedByteArray([130,255])}
		for key in ["mode","target","displayed","word","part","query_bytes"]:
			var invalid := request.duplicate(true);invalid.name_edit.erase(key)
			assert(world.area_request(invalid)==0)
		for pair in [["mode",4],["mode",false],["target",128],["word",2147483648],["part",9],["query_bytes",[]]]:
			var invalid := request.duplicate(true);invalid.name_edit[pair[0]]=pair[1]
			assert(world.area_request(invalid)==0)
		sequence=world.area_request(request);assert(sequence>0)
		state=await receipt(sequence)
		assert(state.area.location_name==snapshot and state.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)

func test_area_operations() -> void:
	# Codec boundary fixtures; these do not establish native mutation effects.
	for operation in [Contract.AreaOperation.MultiCreate, Contract.AreaOperation.MultiUndo, Contract.AreaOperation.MultiFinish]:
		var request := {"action":A.AreaCreate if operation == Contract.AreaOperation.MultiCreate else A.AreaUpdate,
			"operation":operation,"kind":1,"interaction_id":9223372036854775807}
		if operation == Contract.AreaOperation.MultiCreate:
			assert(world.area_request(request) == 0)
			assert(world.last_error() == "Missing management field: origin")
			request.merge({"origin":Vector3i(0,0,32767),"width":32768,"height":32768,"room_furniture":1})
		if operation == Contract.AreaOperation.MultiUndo: request.undo_token = 9223372036854775807
		var sequence: int = world.area_request(request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty())
		var area: Dictionary = state.area
		assert(area.operation == operation and area.interaction_id == 9223372036854775807)
		assert(area.room_outcome == Contract.AreaRoomOutcome.Completed and area.areas.is_empty())
		assert(area.rooms_created == (129 if operation == Contract.AreaOperation.MultiCreate else 0))
		assert(area.rooms_removed == (129 if operation == Contract.AreaOperation.MultiUndo else 0))
		assert(area.undo_token == (9223372036854775807 if operation == Contract.AreaOperation.MultiCreate else 0))
		assert(area.rooms_in_use == (1000 if operation == Contract.AreaOperation.MultiCreate else 0))
		assert(area.rooms_unenclosed == (2000 if operation == Contract.AreaOperation.MultiCreate else 0))
		assert(area.rooms_dormitories == (7 if operation == Contract.AreaOperation.MultiCreate else 0))
	for key in ["operation","expected_revision","expected_list_revision","scope","value","preset","paint_mode","paint_z",
		"location_id","location_kind","profession","deity_kind","deity_id","unit_id","item_id","assign","squad_id","squad_use","organic","inorganic","candidate_kind","sort",
		"room_furniture","interaction_id","undo_token","count_generation","location_site_id","occupation_id"]:
		for bad in [1.5,"1",true]:
			var request := {"action":A.AreaInspect,"id":7}
			request[key] = bad
			assert(world.area_request(request) == 0)
			assert(world.last_error() == "Wrong management field type: " + key)
	for pair in [["list_key",1],["row_key",1],["category_opening",1],["sort_descending",1],["spans",{}],["zone_settings",[]]]:
		var request := {"action":A.AreaInspect,"id":7}
		request[pair[0]] = pair[1]
		assert(world.area_request(request) == 0)
		assert(world.last_error() == "Wrong area field type: " + pair[0])
	for spans in [[1],[{"x":1,"y":2}],[{"x":1.0,"y":2,"length":1}],
		[{"x":32767,"y":0,"length":2}],[{"x":0,"y":0,"length":32769}]]:
		assert(world.area_request({"action":A.AreaCreate,"operation":5,"paint_mode":1,"paint_z":0,"spans":spans}) == 0)
	for key in ["pond_mode","facing","tomb_citizens","tomb_pets","gather_trees","gather_shrubs","gather_fallen"]:
		for bad in [1.5,"1",true]:
			assert(world.area_request({"action":A.AreaUpdate,"id":7,"kind":1,"operation":9,"zone_settings":{key:bad}}) == 0)
			assert(world.last_error() == "Wrong area field type: " + key)
	assert(world.area_request({"action":A.AreaInspect,"id":7,"operation":1,"origin":Vector3i()}) == 0)
	assert(world.last_error() == "Legacy area fields cannot be combined with an operation")
	assert(world.area_request({"action":A.AreaInspect,"id":7,"operation":1,"expected_revision":-1}) == 0)
	for bad_bytes in [[195],"x",PackedByteArray(range(34))]:
		assert(world.area_request({"action":A.AreaCandidates,"operation":14,"id":7,"kind":1,"candidate_kind":1,"query_bytes":bad_bytes}) == 0)
	var actions := [9,11,11,11,10,9,11,11,11,9,11,11,11,14,13]
	for operation in range(1,16):
		var kind := 2 if operation == 15 else 1 if operation in [6,7,8,9,11,12,14] else 0
		var request := {"action":actions[operation-1],"id":7,"kind":kind,"operation":operation,
			"expected_revision":9223372036854775807,"query":"native","cursor":17}
		if operation in [1,6,10,14]: request.expected_list_revision = 9223372036854775807
		if operation in [1,2]: request.list_key = "food/meat"
		if operation == 1: request.category_opening = true
		if operation == 2: request.merge({"row_key":"material:4","scope":1,"value":2})
		if operation == 3: request.preset = 19
		if operation == 4: request.name = "Native name"
		if operation == 5:
			request.merge({"paint_mode":1,"paint_z":17,"zone_type":1,
				"spans":[{"y":14,"x":15,"length":128},{"y":15,"x":15,"length":256}]})
		if operation == 7: request.location_id = -1
		if operation == 8: request.merge({"location_kind":2,"deity_kind":3,"deity_id":900})
		if operation == 9: request.zone_settings = {"pond_mode":2,"facing":4,"tomb_citizens":0,"tomb_pets":1,"gather_trees":1,"gather_shrubs":0,"gather_fallen":1}
		if operation == 11: request.merge({"unit_id":0,"assign":0})
		if operation == 12: request.merge({"squad_id":0,"squad_use":0})
		if operation == 13: request.merge({"organic":0,"inorganic":1})
		if operation == 14: request.merge({"candidate_kind":1,"sort":3,"sort_descending":true,"query":"","query_bytes":PackedByteArray([195])},true)
		if operation == 15: request.merge({"link_id":8,"give":false,"unlink":true})
		var sequence: int = world.area_request(request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty())
		var area: Dictionary = state.area
		assert(area.operation == operation and area.area_id == 7 and area.list_key == "food/meat")
		assert(area.query == ("" if operation == 14 else "native") and area.list_revision == 9223372036854775807)
		if operation == 14: assert(area.query_bytes == PackedByteArray([195]))
		else: assert(not area.has("query_bytes"))
		assert(area.captured_tick == 9876543210 and area.omitted == 2 and area.next_cursor == 128)
		assert(area.build_phase == 0 and area.build_done == 0 and area.build_total == 0)
		assert(area.settings_count == -1) # Older/other response families have no filtered count.
		assert(area.areas == state.areas and area.choices == state.area_choices)
		var row: Dictionary = area.areas[0]
		assert(row.revision == 9223372036854775807 and row.zone_label == "observed")
		assert(row.location_id == 99 and row.location_name == "observed" and row.religion == "observed")
		assert(row.overlapping == 1)
		assert(row.organic == 0 and row.inorganic == 1 and row.tile_count == 1 and row.assigned_count == 4)
		assert(row.zone_settings == {"pond_mode":2,"facing":4,"tomb_citizens":0,"tomb_pets":1,"gather_trees":1,"gather_shrubs":0,"gather_fallen":1})
		if operation == 1: assert(area.settings == [{"key":"food/meat","index":5,"label":"observed","kind":4,"state":3,"estimated":true}])
		if operation == 6: assert(area.locations == [{"id":99,"name":"observed","location_kind":2,"religion":"observed","guild_profession":-1,"location_tier":-1,"site_id":-1}])
		if operation == 10: assert(area.links == [{"id":9,"kind":2,"direction":2,"name":"observed"}])
		if operation == 14:
			assert(area.candidate_kind == 1 and area.sort == 3 and area.sort_descending)
			assert(area.candidates == [{"id":8,"entity":Contract.AreaCandidateEntity.Unknown,"name":"observed","profession":"observed","sex":1,"mood":7,"grazer":true,"assigned":true,"squad_use":15,"owner_display":{"columns":45,"first_line":"Native first line","second_line":"Native second line","status":"Has Quarters","room_value":343,"name_color":{"color":[3,3,1],"alternate":[0,3,0],"effect":1}},"sheet_icon":{"tile_pages":["OWNER_PAGE"],"palettes":["OWNER_PALETTE"],"layers":[[0,2,3,1,1,0,4,5,-1,2]]}}])
	var animal_sequence: int = world.area_request({"action":A.AreaCandidates,"operation":Contract.AreaOperation.CandidateList,
		"id":7,"kind":1,"candidate_kind":2,"sort":2,"query":""})
	assert(animal_sequence > 0)
	var animal_reply: Dictionary = await receipt(animal_sequence)
	assert(not animal_reply.is_empty())
	var animal_row: Dictionary = animal_reply.area.candidates[0]
	assert(animal_row.entity == Contract.AreaCandidateEntity.Unit and not animal_row.has("owner_display"))
	assert(animal_row.animal_display == {"columns":27,"first_line":"","second_line":"Shortened profession",
		"combined_fits":false,"warning":"Grazer: requires pasture","name_color":{"color":[6,0,0],"alternate":[6,0,0],"effect":0}})
	assert(animal_row.animal_status == {"kind":4,"containment":2,"item_id":17})
	assert(animal_row.animal_container == {"material_family":1,"solid_color":"TEST_COLOR","occupant_entity":1,"occupant_id":9,
		"occupant":{"tile_pages":["TEST_OCCUPANT"],"palettes":[],"layers":[[0,2,3,1,1,65535,0,0,-1,2]]}})
	var restraint_row: Dictionary = animal_reply.area.candidates[1]
	assert(restraint_row.animal_restraint == {"rope":true,"solid_color":"TEST_ROPE_COLOR"} and not restraint_row.has("animal_container"))
	assert(animal_reply.area.candidates[2].animal_item_color == {"foreground":2,"background":3,"bright":1})
	var squad_sequence: int = world.area_request({"action":A.AreaCandidates,"operation":Contract.AreaOperation.CandidateList,
		"id":7,"kind":1,"candidate_kind":3,"query":""})
	assert(squad_sequence > 0)
	var squad_reply: Dictionary = await receipt(squad_sequence)
	assert(not squad_reply.is_empty())
	assert(squad_reply.area.candidates[0].entity == Contract.AreaCandidateEntity.Squad)
	assert(squad_reply.area.candidates[0].squad_symbol == {"index":22,"foreground":[0,127,255],"background":[233,61,7]})
	assert(not animal_row.has("squad_symbol"))
	for variant in 3:
		var request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.PaintCounts,
			"zone_type":92,"paint_z":32767,"count_generation":9223372036854775807 - variant}
		if variant > 0:
			request.spans = [{"x":11,"y":12,"length":2},{"x":11,"y":13,"length":2}]
			request.paint_preview = {"x":11,"y":12,"width":4,"height":3}
		for bad in [[],{}, {"x":1,"y":1,"width":0,"height":1}, {"x":1.5,"y":1,"width":1,"height":1}]:
			var invalid := request.duplicate(true)
			invalid.paint_preview = bad
			assert(world.area_request(invalid) == 0)
		var sequence: int = world.area_request(request)
		assert(sequence > 0)
		var state: Dictionary = await receipt(sequence)
		assert(not state.is_empty())
		var area: Dictionary = state.area
		assert(area.operation == Contract.AreaOperation.PaintCounts and area.count_generation == request.count_generation)
		assert(area.painted_count == [0,4,-1][variant] and area.preview_count == [0,8,2][variant])
		assert(area.captured_tick == 9876543210 and area.interaction_id == 0 and area.undo_token == 0)
		assert(area.areas.is_empty() and area.room_outcome == Contract.AreaRoomOutcome.None)
	var staff_request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationStaffCandidates,
		"location_site_id":651,"location_id":0,"occupation_id":87,"cursor":128,"expected_list_revision":9223372036854775807}
	for key in ["location_site_id","location_id","occupation_id","expected_list_revision"]:
		var invalid := staff_request.duplicate()
		invalid.erase(key)
		assert(world.area_request(invalid) == 0)
	var staff_sequence: int = world.area_request(staff_request)
	assert(staff_sequence > 0)
	var staff_state: Dictionary = await receipt(staff_sequence)
	assert(not staff_state.is_empty())
	var staff: Dictionary = staff_state.area.location_staff_candidates
	assert(staff.site_id == 651 and staff.location_id == 0 and staff.occupation_id == 87 and staff.role == 8)
	assert(staff.revision == 9223372036854775807 and staff.cursor == 128 and staff.next_cursor == 0 and staff.total == 129)
	assert(staff.rows == [{"unit_id":100,"histfig_id":900,"name":"Synthetic candidate","base_name":"Synthetic","profession_name":"candidate","profession_color":13,"legendary":true,"score":3,
		"source_index":128,"profession_order":809,"status_order":100000,"name_sort_key":PackedByteArray([97,255]),"profession_sort_key":PackedByteArray([128,0]),
		"skills":[{"id":58,"rating":3,"experience":2000000,"weight":1}]}])

	var edit_request := {"action":A.AreaUpdate,"kind":1,"operation":Contract.AreaOperation.LocationStaffEdit,
		"location_site_id":651,"location_id":0,"occupation_id":87,"unit_id":-1,
		"expected_revision":9007199254740993,"expected_list_revision":9223372036854775807}
	for key in ["location_site_id","location_id","occupation_id","unit_id","expected_revision","expected_list_revision"]:
		var invalid := edit_request.duplicate()
		invalid.erase(key)
		assert(world.area_request(invalid) == 0)
	for unit_id in [-1,2147483647]:
		edit_request.unit_id = unit_id
		var sequence: int = world.area_request(edit_request)
		assert(sequence > 0)
		var edited: Dictionary = await receipt(sequence)
		assert(edited.area.operation == Contract.AreaOperation.LocationStaffEdit)
		assert(edited.area.location_edit_outcome == Contract.LocationEditOutcome.Completed)
		assert(edited.area.location_details.revision == 9223372036854775807)
		assert(edited.area.location_details.site_id == 651 and edited.area.location_details.id == 0)

	var quantity_request := {"action":A.AreaUpdate,"kind":1,"operation":Contract.AreaOperation.LocationQuantity,
		"location_site_id":651,"location_id":0,"expected_revision":9007199254740993,
		"quantity_id":10,"quantity_mode":Contract.LocationQuantityMode.Set,"quantity_value":999}
	for key in ["location_site_id","location_id","expected_revision","quantity_id","quantity_mode","quantity_value"]:
		var invalid := quantity_request.duplicate();invalid.erase(key)
		assert(world.area_request(invalid)==0)
	for pair in [["quantity_id",11],["quantity_mode",3],["quantity_value",1000],["quantity_value",-1],["quantity_value",1.5],["quantity_mode",true]]:
		var invalid := quantity_request.duplicate();invalid[pair[0]]=pair[1]
		assert(world.area_request(invalid)==0)
	for mode in 3:
		quantity_request.quantity_mode=mode;quantity_request.quantity_value=999 if mode==0 else 0
		var sequence: int=world.area_request(quantity_request);assert(sequence>0)
		var edited: Dictionary=await receipt(sequence)
		assert(edited.area.operation==Contract.AreaOperation.LocationQuantity)
		assert(edited.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)
		assert(edited.area.location_details.revision==9223372036854775807)

func test_location_recognition() -> void:
	var request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationRecognitionRead,
		"location_site_id":651,"location_id":0}
	for key in ["location_site_id","location_id"]:
		var invalid := request.duplicate(true);invalid.erase(key)
		assert(world.area_request(invalid)==0)
	var sequence: int=world.area_request(request);assert(sequence>0)
	var state: Dictionary=await receipt(sequence)
	var snapshot: Dictionary=state.area.location_recognition
	assert(snapshot=={"site_id":651,"location_id":0,"religion_id":383,"revision":9007199254740993,
		"tier":2,"rank":1,"worshippers":53,"priest_threshold":10,"high_priest_threshold":25,
		"state":Contract.LocationRecognitionState.RecognizeHighPriest,"continuing_agreements":[41,42]})
	request.action=A.AreaUpdate;request.operation=Contract.AreaOperation.LocationRecognize
	request.expected_revision=snapshot.revision
	for key in ["location_site_id","location_id","expected_revision"]:
		var invalid := request.duplicate(true);invalid.erase(key)
		assert(world.area_request(invalid)==0)
	for value in [0,-1,1.5]:
		var invalid := request.duplicate(true);invalid.expected_revision=value
		assert(world.area_request(invalid)==0)
	sequence=world.area_request(request);assert(sequence>0)
	state=await receipt(sequence)
	assert(state.area.location_recognition==snapshot)
	assert(state.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)

func test_location_religious_staff() -> void:
	var request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationReligiousStaffRead,
		"location_site_id":651,"location_id":0,"religious_entity_id":383,"religious_assignment_id":2}
	for key in ["location_site_id","location_id","religious_entity_id","religious_assignment_id"]:
		var invalid := request.duplicate(true);invalid.erase(key)
		assert(world.area_request(invalid)==0)
		invalid=request.duplicate(true);invalid[key]=1.5
		assert(world.area_request(invalid)==0)
	var sequence: int=world.area_request(request);assert(sequence>0)
	var state: Dictionary=await receipt(sequence)
	var snapshot: Dictionary=state.area.location_religious_staff
	assert(snapshot=={"site_id":651,"location_id":0,"entity_id":383,"assignment_id":2,"position_id":0,
		"holder_id":9375,"unit_id":5813,"revision":9007199254740993,"removable":true})
	request.action=A.AreaUpdate;request.operation=Contract.AreaOperation.LocationReligiousStaffRemove
	request.expected_revision=snapshot.revision;request.religious_holder_id=snapshot.holder_id
	for key in ["location_site_id","location_id","religious_entity_id","religious_assignment_id","religious_holder_id","expected_revision"]:
		var invalid := request.duplicate(true);invalid.erase(key)
		assert(world.area_request(invalid)==0)
	for value in [0,-1,1.5]:
		var invalid := request.duplicate(true);invalid.expected_revision=value
		assert(world.area_request(invalid)==0)
	sequence=world.area_request(request);assert(sequence>0)
	state=await receipt(sequence)
	snapshot.holder_id=-1;snapshot.unit_id=-1;snapshot.removable=false
	assert(state.area.location_religious_staff==snapshot)
	assert(state.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)

func test_location_religious_assignment() -> void:
	var request := {"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationReligiousCandidates,
		"location_site_id":651,"location_id":0,"religious_entity_id":383,"religious_assignment_id":2}
	var sequence: int=world.area_request(request);assert(sequence>0)
	var state: Dictionary=await receipt(sequence)
	var page: Dictionary=state.area.location_religious_candidates
	assert(page.revision==9007199254740993 and page.cursor==0 and page.next_cursor==0 and page.total==1 and page.rows.size()==1)
	assert(page.rows[0].unit_id==7123 and page.rows[0].histfig_id==10379 and page.rows[0].skills==[{"id":70,"rating":3,"experience":25,"weight":1}])
	assert(page.rows[0].name_sort_key==PackedByteArray([97,255]) and page.rows[0].profession_sort_key==PackedByteArray([128,0]))
	assert(page.target.holder_id==-1 and page.target.revision==9007199254740994)
	request.operation=Contract.AreaOperation.LocationReligiousAssignmentRead
	request.unit_id=7123;request.expected_list_revision=page.revision;request.religious_holder_id=-1
	for key in ["unit_id","expected_list_revision","religious_holder_id"]:
		var invalid := request.duplicate(true);invalid.erase(key);assert(world.area_request(invalid)==0)
	sequence=world.area_request(request);assert(sequence>0)
	state=await receipt(sequence)
	var selected: Dictionary=state.area.location_religious_assignment
	assert(selected.target==page.target and selected.unit_id==7123 and selected.histfig_id==10379 and selected.nemesis_id==7120)
	assert(selected.revision==9007199254740995 and selected.list_revision==page.revision and selected.eligible)
	request.operation=Contract.AreaOperation.LocationReligiousAssign;request.action=A.AreaUpdate;request.expected_revision=selected.revision
	for key in ["expected_revision","expected_list_revision","religious_holder_id","unit_id"]:
		var invalid := request.duplicate(true);invalid.erase(key);assert(world.area_request(invalid)==0)
	sequence=world.area_request(request);assert(sequence>0)
	state=await receipt(sequence)
	assert(state.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)
	assert(state.area.location_religious_staff.holder_id==10379 and state.area.location_religious_staff.unit_id==7123)

func test_location_specialization() -> void:
	for occupation in [false,true]:
		var request: Dictionary={"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationSpecializationRead,
			"location_site_id":651,"location_id":0,"unit_id":5813}
		if occupation:request.occupation_id=87
		else:request.religious_entity_id=383;request.religious_assignment_id=2
		var sequence: int=world.area_request(request);assert(sequence>0)
		var state: Dictionary=await receipt(sequence)
		var observed: Dictionary=state.area.location_specialization
		assert(observed.unit_id==5813 and observed.histfig_id==9375 and observed.revision==9007199254740993 and observed.eligible and observed.specialized)
		assert(observed.occupation_id==(87 if occupation else -1))
		request.action=A.AreaUpdate;request.operation=Contract.AreaOperation.LocationSpecializationSet
		request.expected_revision=observed.revision;request.value=0
		for key in ["value","expected_revision","unit_id"]:
			var invalid:=request.duplicate(true);invalid.erase(key);assert(world.area_request(invalid)==0)
		sequence=world.area_request(request);assert(sequence>0);state=await receipt(sequence)
		assert(not state.area.location_specialization.specialized and state.area.location_edit_outcome==Contract.LocationEditOutcome.Completed)

func test_location_staff_assignments() -> void:
	for occupation in [false,true]:
		var request: Dictionary={"action":A.AreaInspect,"kind":1,"operation":Contract.AreaOperation.LocationStaffAssignmentsRead,
			"location_site_id":651,"location_id":0,"unit_id":5813}
		if occupation:request.occupation_id=87
		else:request.religious_entity_id=383;request.religious_assignment_id=2
		for key in ["location_site_id","location_id","unit_id"]:
			var bad:=request.duplicate(true);bad.erase(key);assert(world.area_request(bad)==0)
		var sequence: int=world.area_request(request);assert(sequence>0)
		var state: Dictionary=await receipt(sequence)
		var observed: Dictionary=state.area.location_staff_assignments
		assert(observed.unit_id==5813 and observed.histfig_id==9375 and observed.revision==9007199254740993)
		assert(observed.occupation_id==(87 if occupation else -1))
		assert(observed.entries.size()==(0 if occupation else 4))
		if not occupation:
			for i in 4:assert(observed.entries[i].kind==i and observed.entries[i].id==i)
			assert(observed.entries[3].name=="Synthetic detail" and observed.entries[1].subtype==23 and observed.entries[1].custom==7 and observed.entries[1].custom_code=="SYNTHETIC_WORKSHOP")

func test_work_detail_workers() -> void:
	var request: Dictionary={"action":A.WorkDetailWorkersQuery,"detail_index":7,"expected_revision":9007199254740993,"sorts":[{"column":3,"descending":true},{"column":1,"descending":false},{"column":3,"descending":true}],"query_bytes":PackedByteArray([84,195])}
	for patch in [{"detail_index":-1},{"detail_index":128},{"expected_revision":0},{"expected_revision":1.5},{"sorts":[]},{"sorts":[{"column":4,"descending":false}]},{"sorts":[{"column":1,"descending":1}]},{"sorts":[{"column":1,"descending":false},{"column":1,"descending":true}]},{"sorts":[1]},{"sort":3},{"query_bytes":PackedByteArray([0])},{"query_bytes":[84,195]},{"cursor":1}]:
		var invalid:=request.duplicate();invalid.merge(patch,true)
		assert(world.management_request("work_detail_workers",invalid)==0)
	var sequence: int=world.management_request("work_detail_workers",request)
	assert(sequence>0)
	var state:=await receipt(sequence)
	assert(state.get("residents",{}).get("unit_ids",PackedInt32Array())==PackedInt32Array([7,2,9]))

func test_work_detail_settings() -> void:
	for action in [A.WorkDetailSettingsRead,A.WorkDetailSettingsToggle]:
		var request: Dictionary={"action":action,"detail_index":7,"expected_revision":9007199254740993}
		if action==A.WorkDetailSettingsToggle:request.setting_id=-2
		for patch in [{"detail_index":128},{"expected_revision":0},{"expected_revision":1.5},{"setting_id":-1},{"setting_id":94},{"cursor":1}]:
			var invalid:=request.duplicate();invalid.merge(patch,true)
			assert(world.management_request("work_detail_settings",invalid)==0)
		var sequence: int=world.management_request("work_detail_settings",request);assert(sequence>0)
		var state:=await receipt(sequence);var value: Dictionary=state.get("work_detail_settings",{})
		assert(value.get("revision")==9007199254740993 and value.get("detail_index")==7)
		assert(value.get("labors")==PackedInt32Array([11,59]) and value.get("catalog",[]).size()==91)
		assert(Contract.is_mutation(action)==(action==A.WorkDetailSettingsToggle))

func test_standing_orders() -> void:
	var query: Dictionary={"action":A.StandingOrdersRead,"category":0}
	for patch in [{"category":5},{"category":7},{"category":0.5},{"value":1}]:
		var invalid:=query.duplicate();invalid.merge(patch,true)
		assert(world.management_request("standing_orders",invalid)==0)
	var sequence: int=world.management_request("standing_orders",query);assert(sequence>0)
	var reply:=await receipt(sequence)
	assert(reply.standing_orders.settings.size()==11 and reply.standing_orders.settings[0].value==2)
	assert(not reply.standing_orders.settings[10].visible and reply.standing_orders.outcome==Contract.StandingOrdersOutcome.None)
	var intent: Dictionary={"action":A.StandingOrdersSet,"category":0,"setting_id":1,"expected_value":0,"value":1}
	for patch in [{"setting_id":11},{"value":2},{"expected_value":-1},{"value":1.5},{"cursor":1}]:
		var invalid:=intent.duplicate();invalid.merge(patch,true)
		assert(world.management_request("standing_orders",invalid)==0)
	sequence=world.management_request("standing_orders",intent);assert(sequence>0);reply=await receipt(sequence)
	assert(reply.standing_orders.outcome==Contract.StandingOrdersOutcome.Applied and reply.standing_orders.settings[1].value==1)
	intent.merge({"setting_id":0,"expected_value":2,"value":0},true)
	sequence=world.management_request("standing_orders",intent);assert(sequence>0);reply=await receipt(sequence,S.Rejected)
	assert(reply.outcome=="unknown" and reply.standing_orders.settings.is_empty())
	assert(Contract.is_mutation(A.StandingOrdersSet) and not Contract.is_mutation(A.StandingOrdersRead))

	for category in [1,2,3,4,6]:
		query.category=category;sequence=world.management_request("standing_orders",query);assert(sequence>0)
		reply=await receipt(sequence)
		assert(reply.standing_orders.category==category and reply.standing_orders.settings.size()==(6 if category in [1,4] else 7 if category==6 else 10))
		assert(reply.standing_orders.settings[2].visible and reply.standing_orders.settings[2].editable==(category!=2))
		intent={"action":A.StandingOrdersSet,"category":category,"setting_id":1,"expected_value":0,"value":1}
		for patch in [{"setting_id":6 if category in [1,4] else 7 if category==6 else 10},{"setting_id":0,"value":3 if category in [3,4] else 4 if category==6 else 2}]:
			var invalid:=intent.duplicate();invalid.merge(patch,true);assert(world.management_request("standing_orders",invalid)==0)
		sequence=world.management_request("standing_orders",intent);assert(sequence>0);reply=await receipt(sequence)
		assert(reply.standing_orders.category==category and reply.standing_orders.settings[1].value==1 and reply.standing_orders.settings[2].editable)

func test_hunter_ammunition() -> void:
	var seq: int=world.management_request("hunter_ammunition",{"action":A.HunterAmmunitionRead});assert(seq>0)
	var reply:=await receipt(seq);var value: Dictionary=reply.hunter_ammunition
	assert(value.specs[0].assigned==PackedInt32Array([13119]) and value.rules[0].quantity==30)
	assert(value.rules[0].items[0].caption=="fixture stack" and value.types[0].item_type==39)
	assert(value.rules[0].items[0].appearance=={"material_token":"INORGANIC:SILVER","subtype_raw":"ITEM_AMMO_BOLTS","color_token":"","stack":30,"flags":0})
	seq=world.management_request("hunter_ammunition",{"action":A.HunterAmmunitionCandidates,"item_type":39,"item_subtype":0});assert(seq>0)
	reply=await receipt(seq);assert(reply.hunter_ammunition.materials[0].material_class==3)
	var base: Dictionary={"action":A.HunterAmmunitionApply,"operation":1,"index":0,"item_id":-1,"amount":-1,"item_type":-1,"item_subtype":-1,"material_class":-1,"mattype":-1,"matindex":-1,"expected":value.specs}
	for operation in range(1,6):
		var intent:=base.duplicate(true);intent.operation=operation
		if operation==1:intent.amount=125
		if operation==2:intent.material_class=3
		if operation==3:intent.merge({"index":-1,"item_type":39,"item_subtype":0},true)
		if operation==5:intent.item_id=13119
		for patch in [{"index":1.5},{"amount":5001},{"item_subtype":32768},{"expected":0}]:
			var invalid:=intent.duplicate(true);invalid.merge(patch,true);assert(world.management_request("hunter_ammunition",invalid)==0)
		seq=world.management_request("hunter_ammunition",intent);assert(seq>0);reply=await receipt(seq)
		assert(reply.hunter_ammunition.outcome==Contract.HunterAmmunitionOutcome.Applied and reply.hunter_ammunition.specs.size()==1)
	base.amount=126;seq=world.management_request("hunter_ammunition",base);assert(seq>0);reply=await receipt(seq,S.Rejected)
	assert(reply.outcome=="unknown" and reply.hunter_ammunition.specs.is_empty())
	assert(Contract.is_mutation(A.HunterAmmunitionApply) and not Contract.is_mutation(A.HunterAmmunitionRead))

func test_chores() -> void:
	var seq: int=world.management_request("chores",{"action":A.ChoresRead});assert(seq>0)
	var reply:=await receipt(seq);var value: Dictionary=reply.chores
	assert(value.snapshot.children==PackedInt32Array([42,7]) and value.snapshot.exempted==PackedInt32Array([7]))
	assert(value.children[0].caption=="fixture child" and value.labors[0].caption=="fixture labor")
	var base: Dictionary={"action":A.ChoresApply,"operation":1,"id":-1,"value":true,"expected":value.snapshot}
	for operation in range(1,4):
		var intent:=base.duplicate(true);intent.operation=operation
		if operation==2:intent.id=23;intent.value=false
		if operation==3:intent.id=42
		for patch in [{"id":1.5},{"value":1},{"expected":0},{"operation":4},{"cursor":1}]:
			var invalid:=intent.duplicate(true);invalid.merge(patch,true);assert(world.management_request("chores",invalid)==0)
		for patch in [{"children":PackedInt32Array([42,42])},{"exempted":PackedInt32Array([7,7])},{"labors":[]},{"enabled":1}]:
			var invalid:=intent.duplicate(true);invalid.expected.merge(patch,true);assert(world.management_request("chores",invalid)==0)
		seq=world.management_request("chores",intent);assert(seq>0);reply=await receipt(seq)
		assert(reply.chores.outcome==Contract.ChoresOutcome.Applied and reply.chores.children.is_empty())
		if operation==2:assert(not reply.chores.snapshot.labors[0].enabled)
		if operation==3:assert(reply.chores.snapshot.exempted==PackedInt32Array([7,42]))
	base.value=false;seq=world.management_request("chores",base);assert(seq>0);reply=await receipt(seq,S.Rejected)
	assert(reply.outcome=="unknown" and not reply.chores.has("snapshot"))
	assert(Contract.is_mutation(A.ChoresApply) and not Contract.is_mutation(A.ChoresRead))

func test_kitchen_menu() -> void:
	var query: Dictionary={"action":A.KitchenRead,"type_filter":-1,"capability_filter":0,"query":"plump","sorts":[{"column":1,"reverse":true},{"column":2,"reverse":false}]}
	query.sorts.append_array(query.sorts.duplicate(true))
	query.sorts.append_array(query.sorts.duplicate(true))
	for patch in [{"type_filter":4},{"capability_filter":4},{"query":12},{"sorts":[]},{"sorts":[{"column":1,"reverse":true},{"column":1,"reverse":false}]},{"sorts":[{"column":1,"reverse":1}]},{"target":{}}]:
		var invalid:=query.duplicate(true);invalid.merge(patch,true);assert(world.management_request("kitchen_menu",invalid)==0)
	var seq: int=world.management_request("kitchen_menu",query);assert(seq>0)
	var reply:=await receipt(seq);var value: Dictionary=reply.kitchen_menu
	assert(value.rows.size()==1 and value.exclusions.size()==2)
	assert(value.rows[0].name=="fixture food" and value.rows[0].count_caption=="12?" and value.rows[0].estimated and value.rows[0].excluded==2)
	assert(value.rows[0].material_token=="PLANT_MAT:MUSHROOM_HELMET_PLUMP:STRUCTURAL")
	var intent: Dictionary={"action":A.KitchenApply,"target":value.rows[0].receipt,"permission":1,"expected":value.exclusions}
	for patch in [{"permission":3},{"permission":1.5},{"expected":0},{"query":"x"},{"target":{"key":{"item_type":32768,"item_subtype":-1,"mat_type":419,"mat_index":0},"count":12,"capabilities":3}},{"target":{"key":value.rows[0].receipt.key,"count":12,"capabilities":2}}]:
		var invalid:=intent.duplicate(true);invalid.merge(patch,true);assert(world.management_request("kitchen_menu",invalid)==0)
	seq=world.management_request("kitchen_menu",intent);assert(seq>0);reply=await receipt(seq)
	assert(reply.kitchen_menu.outcome==Contract.KitchenMenuOutcome.Applied and reply.kitchen_menu.rows.is_empty() and reply.kitchen_menu.exclusions.is_empty())
	intent.permission=2;seq=world.management_request("kitchen_menu",intent);assert(seq>0);reply=await receipt(seq,S.Rejected)
	assert(reply.outcome=="unknown" and reply.kitchen_menu.outcome==Contract.KitchenMenuOutcome.Unknown and reply.kitchen_menu.rows.is_empty() and reply.kitchen_menu.exclusions.is_empty())
	assert(Contract.is_mutation(A.KitchenApply) and not Contract.is_mutation(A.KitchenRead))

func test_stone_use() -> void:
	assert(world.management_request("stone_use",{"action":A.StoneUseRead,"index":0})==0)
	var seq: int=world.management_request("stone_use",{"action":A.StoneUseRead});assert(seq>0)
	var reply:=await receipt(seq);var value: Dictionary=reply.stone_use
	assert(value.restrictions==[0,1,0] and value.rows.size()==1)
	assert(value.rows[0]=={"category":0,"index":1,"restricted":true,"name":"fixture stone","uses":"fixture use","magma_safe":true,"material_token":"INORGANIC:FIXTURE"})
	var intent: Dictionary={"action":A.StoneUseApply,"category":0,"index":1,"expected":value.restrictions}
	for patch in [{"category":2},{"index":1.5},{"index":3},{"expected":[0,true,0]},{"expected":[0,2,0]},{"extra":0}]:
		var invalid:=intent.duplicate(true);invalid.merge(patch,true);assert(world.management_request("stone_use",invalid)==0)
	seq=world.management_request("stone_use",intent);assert(seq>0);reply=await receipt(seq)
	assert(reply.stone_use.outcome==Contract.StoneUseOutcome.Applied and reply.stone_use.rows.is_empty() and reply.stone_use.restrictions.is_empty())
	intent.category=1;seq=world.management_request("stone_use",intent);assert(seq>0);reply=await receipt(seq,S.Rejected)
	assert(reply.outcome=="unknown" and reply.stone_use.outcome==Contract.StoneUseOutcome.Unknown and reply.stone_use.rows.is_empty() and reply.stone_use.restrictions.is_empty())
	assert(Contract.is_mutation(A.StoneUseApply) and not Contract.is_mutation(A.StoneUseRead))

func test_stocks_menu() -> void:
	var read: Dictionary={"action":A.StocksMenuRead,"category":39,"query":"iron","item_ids":[17]}
	for patch in [{"category":93},{"category":true},{"query":5},{"item_ids":[17,17]},{"item_ids":[-1]},{"extra":0}]:
		var invalid:=read.duplicate(true);invalid.merge(patch,true);assert(world.management_request("stocks_menu",invalid)==0)
	var seq: int=world.management_request("stocks_menu",read);assert(seq>0)
	var reply:=await receipt(seq);var value: Dictionary=reply.stocks_menu
	assert(value.category==39 and value.categories.size()==93 and value.groups.size()==1 and value.items.size()==1)
	assert(value.categories[39].matches and value.categories[39].stored=="~20")
	assert(value.groups[0].item_ids==[42,17] and value.groups[0].revision==9223372036854775807 and value.groups[0].caption=="fixture group [3]")
	assert(value.items[0].id==17 and value.items[0].can_dump and value.items[0].material_token=="INORGANIC:IRON")
	var edit: Dictionary={"action":A.StocksGroupApply,"category":39,"subtype":0,"subcat1":0,"subcat2":0,"expected_revision":value.groups[0].revision,"operation":Contract.StocksFlagAction.Forbid,"value":1}
	for patch in [{"category":-1},{"subtype":32768},{"expected_revision":0},{"operation":4},{"value":true},{"extra":0}]:
		var invalid:=edit.duplicate(true);invalid.merge(patch,true);assert(world.management_request("stocks_menu",invalid)==0)
	seq=world.management_request("stocks_menu",edit);assert(seq>0);reply=await receipt(seq)
	assert(reply.stocks_menu.outcome==Contract.StocksMenuOutcome.Applied and reply.stocks_menu.groups[0].revision==9223372036854775806)
	edit.value=0;seq=world.management_request("stocks_menu",edit);assert(seq>0);reply=await receipt(seq,S.Rejected)
	assert(reply.outcome=="unknown" and reply.stocks_menu.category==-1 and reply.stocks_menu.groups.is_empty() and reply.stocks_menu.categories.is_empty())
	assert(Contract.is_mutation(A.StocksGroupApply) and not Contract.is_mutation(A.StocksMenuRead))
