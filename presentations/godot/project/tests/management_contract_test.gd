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
	assert(FileAccess.get_file_as_string(status_path)=="passed")
	finish(0,"MANAGEMENT_CONTRACT_TEST_PASS")
