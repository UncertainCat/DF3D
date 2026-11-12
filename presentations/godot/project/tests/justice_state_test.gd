extends SceneTree
const View=preload("res://scripts/justice_view.gd")
const Owner=preload("res://scripts/justice_panel.gd")
const Registry=preload("res://scripts/ui_availability.gd")
const State=preload("res://scripts/justice_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func page(ids: Array=[9,10],offset:=0,total:=2,tab:=0,revision:=8) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":tab,"list_revision":revision,"offset":offset,"total":total,"rows":ids.map(func(id):return {"crime_id":id,"caption":"fixture"})}}
func report(id:=9,offset:=0,total:=1,revision:=12,tab:=0) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":tab,"list_revision":8,"detail":{"crime_id":id,"resolution":C.JusticeCaseResolution.Unsolved,"revision":revision,"caption":"fixture","status":"fixture status","total":total,"offset":offset,"witnesses":[{"witness":"fixture witness","description":"","date":"event","reported":"reported"}]}}}
func _initialize() -> void:call_deferred("run")
func candidates(ids: Array=[42,43],offset:=0,total:=2,revision:=22) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":0,"list_revision":8,"candidates":{"crime_id":9,"revision":revision,
		"offset":offset,"total":total,"rows":ids.map(func(id):return {"unit_id":id,"rank":3,"interrogation_pending":false,"counterintelligence":true,"display":{"columns":28,"name":"fixture","witness_count":0,"witness_label":"fixture","witness_color":6,"deceased":"","name_color":{"color":[4,0,0],"alternate":[4,0,0],"effect":0}}})}}}
func ready(service,state) -> void:
	state.open();service.reply(state.ticket,page());service.reply(state.ticket,report())
func test_candidates(service,state) -> void:
	ready(service,state);state.open_candidates();var picker=state.candidates
	service.reply(picker.ticket,candidates([42],0,2))
	check(picker.rows.is_empty() and service.calls[picker.ticket].intent.offset==1 and service.calls[picker.ticket].intent.expected_candidate_revision==22,"Partial candidates leaked or lost revision")
	service.reply(picker.ticket,candidates([43],1,2));check(picker.rows.size()==2 and picker.phase==picker.Phase.Ready,"Candidate pages failed to assemble")
	picker.search("first");var old: int=picker.ticket;picker.search("second");var current: int=picker.ticket
	service.reply(old,candidates());check(picker.ticket==current and picker.rows.is_empty(),"Old search replaced current query")
	service.reply(current,candidates());picker.convict(42);current=picker.ticket
	var intent: Dictionary=service.calls[current].intent
	check(intent.query=="second" and intent.unit_id==42 and intent.expected_candidate_revision==22 and intent.expected_case_revision==12 and intent.expected_list_revision==8,"Conviction lost selection scope")
	picker.convict(42);picker.search("changed");state.open_candidates()
	check(picker.ticket==current and picker.phase==picker.Phase.Applying,"Pending conviction allowed another request")
	service.reply(current,{"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Unknown}})
	check(picker.phase==picker.Phase.Unknown and picker.rows.size()==2,"Unknown conviction lost disabled rows")
	var count: int=service.next;picker.convict(42);picker.search("retry");state.open_candidates()
	check(service.next==count,"Unknown conviction replayed or refreshed implicitly")
	ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates());picker.convict(42);old=picker.ticket
	state.close();service.reply(old,{"justice":{"outcome":C.JusticeOutcome.Applied}})
	check(state.phase==State.Phase.Closed and picker.phase==picker.Phase.Closed,"Late conviction reopened parent")
	ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates());picker.convict(42)
	service.reply(picker.ticket,{"justice":{"outcome":C.JusticeOutcome.Applied}})
	check(state.phase==State.Phase.Reading and state.rows.is_empty() and picker.phase==picker.Phase.Closed,"Applied conviction failed to refresh parent cases")
	for fault in 3:
		ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates([42],0,2));var continuation:=candidates([43],1,2)
		match fault:
			0:continuation.justice.candidates.revision=23
			1:continuation.justice.candidates.rows[0].unit_id=42
			2:continuation.justice.candidates.rows=[]
		service.reply(picker.ticket,continuation)
		check(picker.phase==picker.Phase.Rejected and picker.rows.is_empty() and picker.ticket==0,"Malformed candidate continuation accepted or replayed")
	ready(service,state);state.open_candidates();old=picker.ticket;state.select_case(10);service.reply(old,candidates())
	check(picker.phase==picker.Phase.Closed and picker.rows.is_empty(),"Case switch retained old candidate picker")
	ready(service,state);state.open_candidates();old=picker.ticket;service.session_changed.emit();service.reply(old,candidates())
	check(state.phase==State.Phase.Unavailable and picker.phase in [picker.Phase.Closed,picker.Phase.Unavailable] and picker.rows.is_empty(),"Session change accepted late candidates")
func test_sorts(service,state) -> void:
	ready(service,state);state.open_candidates();var picker=state.candidates
	var old: int=picker.ticket
	picker.select_sort(C.JusticeCandidateColumn.Name)
	var current: int=picker.ticket
	check(picker.priorities==[1] and picker.directions[1] and picker.candidate_revision==0,"Name header did not reverse/reset native default")
	service.reply(old,candidates());check(picker.ticket==current and picker.rows.is_empty(),"Retired sort read replaced current rows")
	picker.select_sort(3,true);picker.select_sort(0,true);picker.select_sort(1,true);picker.select_sort(1,true)
	check(picker.priorities==[1,3,0,1,1] and picker.directions[1],"Repeated priorities lost shared direction")
	var intent: Dictionary=service.calls[picker.ticket].intent
	check(intent.sorts==[{"column":1,"reverse":true},{"column":3,"reverse":false},{"column":0,"reverse":false},{"column":1,"reverse":true},{"column":1,"reverse":true}],"Sort request lost priorities")
	picker.select_sort(1,false,true);check(picker.priorities==[3,0],"Ctrl did not remove all matching priorities")
	picker.select_sort(3,false,true);picker.select_sort(0);picker.select_sort(0,false,true)
	check(picker.priorities==[0] and picker.directions[0],"Empty-priority fallback lost remembered Category direction")
	service.reply(picker.ticket,candidates());picker.convict(42);current=picker.ticket
	picker.select_sort(2);check(picker.ticket==current and picker.priorities==[0],"Sort changed during mutation")
	service.reply(current,{"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Unknown}})
	picker.select_sort(2);check(picker.priorities==[0] and picker.ticket==0,"Unknown mutation allowed sorting")
	state.close();check(picker.priorities==[3,1] and picker.directions==[false,false,false,false],"Close retained old sort state")
func test_interrogation(service,state) -> void:
	ready(service,state);state.open_candidates(true);var picker=state.candidates
	var read:=candidates();read.justice.candidates.interrogate=true
	service.reply(picker.ticket,read);picker.seek(1,1);picker.toggle_interrogation(43)
	var sent: Dictionary=service.calls[picker.ticket].intent
	check(sent.action==C.ManagementAction.JusticeInterrogate and sent.interrogate and not sent.expected_selected and sent.unit_id==43,"Interrogation lost comparison scope")
	var current: int=picker.ticket;picker.toggle_interrogation(43);picker.search("retry");picker.select_sort(0)
	check(picker.ticket==current,"Pending interrogation replayed")
	service.reply(current,{"justice":{"outcome":C.JusticeOutcome.Applied}})
	read=candidates([43,42],0,2,23);read.justice.candidates.interrogate=true;read.justice.candidates.rows[0].interrogation_pending=true
	service.reply(picker.ticket,read)
	check(picker.rows.map(func(row):return row.unit_id)==[42,43] and picker.rows[1].interrogation_pending and picker.first==1 and picker.cursor_id==43,"Checkbox refresh reordered rows or lost scroll/selection")
	picker.select_sort(1);service.reply(picker.ticket,read)
	check(picker.rows[0].unit_id==43,"Explicit sort did not adopt native partition")
	picker.toggle_interrogation(43);check(service.calls[picker.ticket].intent.expected_selected,"Cancellation lost selected comparison")
	service.reply(picker.ticket,{"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Unknown}})
	var count: int=service.next;picker.toggle_interrogation(43);picker.search("");picker.select_sort(0)
	check(picker.phase==picker.Phase.Unknown and service.next==count,"Unknown interrogation replayed")
	state.close();check(picker.phase==picker.Phase.Closed,"Unknown interrogation could not retire")
	ready(service,state);state.open_candidates(true);service.reply(picker.ticket,candidates())
	check(picker.phase==picker.Phase.Rejected,"Wrong candidate mode accepted")
func guard_page(ids: Array=[42],offset:=0,total:=1,revision:=31) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":3,"list_revision":revision,"offset":offset,"total":total,"rows":[],"guard":{"caption":"fixture","color":12,"rows":ids.map(func(id):return {"unit_id":id,"rank":2000,"first_line":"fixture","second_line":"","name_color":{"color":[5,0,1],"alternate":[5,0,1],"effect":0},"position":Vector3i(1,2,3)})}}}
func test_guard(service,state) -> void:
	state.open(3);var guard=state.guard
	check(service.calls[guard.ticket].intent.action==C.ManagementAction.JusticeGuardRead and service.calls[guard.ticket].intent.sorts==[{"column":0,"reverse":false}],"Guard lost native default sort or request")
	service.reply(guard.ticket,guard_page([42],0,2))
	check(guard.rows.is_empty() and service.calls[guard.ticket].intent.expected_list_revision==31 and service.calls[guard.ticket].intent.offset==1,"Partial guard roster exposed")
	service.reply(guard.ticket,guard_page([43],1,2));check(guard.rows.size()==2 and guard.phase==guard.Phase.Ready,"Guard pages failed to assemble")
	guard.search("old");var old: int=guard.ticket;guard.search("new");var current: int=guard.ticket
	service.reply(old,guard_page());check(guard.ticket==current and guard.rows.is_empty(),"Old guard query replaced current rows")
	service.reply(current,guard_page());guard.inspect(42);old=guard.ticket
	state.select_tab(0);service.reply(old,{"creature_position":{"unit_id":42,"position":Vector3i(1,2,3)}})
	check(guard.phase==guard.Phase.Closed,"Navigation survived guard retirement")
	for fault in 3:
		state.open(3);service.reply(guard.ticket,guard_page([42],0,2));var continuation:=guard_page([43],1,2)
		match fault:
			0:continuation.justice.list_revision=32
			1:continuation.justice.guard.rows[0].unit_id=42
			2:continuation.justice.guard.caption="changed"
		service.reply(guard.ticket,continuation)
		check(guard.phase==guard.Phase.Rejected and guard.rows.is_empty(),"Inconsistent guard continuation accepted")
	state.open(3);old=guard.ticket;state.close();service.reply(old,guard_page())
	check(guard.phase==guard.Phase.Closed and guard.rows.is_empty(),"Late guard page reopened closed panel")
func run() -> void:
	check(Registry.PANEL_SCRIPTS.has("justice") and not Registry.PANEL_ROUTES.has("Justice"),"Justice public gate changed")
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([9],0,2));check(state.rows.is_empty() and state.phase==State.Phase.Reading,"Partial cases exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_list_revision==8,"Case continuation lost receipt")
	service.reply(state.ticket,page([10],1,2));check(state.rows.size()==2 and state.selected_id==9 and state.phase==State.Phase.DetailReading,"Initial native selection missing")
	service.reply(state.ticket,report(9,0,2));check(state.detail.is_empty(),"Partial witnesses exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_case_revision==12,"Witness continuation lost receipt")
	service.reply(state.ticket,report(9,1,2));check(state.phase==State.Phase.Ready and state.detail.witnesses.size()==2 and not state.detail.has("injured_party"),"Witness pages not assembled")
	state.seek_witness(99,1);check(state.witness_first==1,"Witness scroll not clamped")
	state.select_case(10);var old: int=state.ticket;state.select_case(9);var current: int=state.ticket
	service.reply(old,report(10));check(state.ticket==current and state.detail.is_empty() and service.detached.has(old),"Late old case replaced current detail")
	service.reply(current,report());state.select_case(10);old=state.ticket;state.select_tab(2);current=state.ticket
	service.reply(old,report(10));check(state.ticket==current and state.rows.is_empty() and state.selected_id==-1,"Tab switch retained old selection")
	service.reply(current,page([],0,0,2));check(state.phase==State.Phase.Ready and state.detail.is_empty(),"Empty tab rejected")
	state.open();service.reply(state.ticket,page());old=state.ticket;state.close();service.reply(old,report())
	check(state.phase==State.Phase.Closed and state.detail.is_empty(),"Close accepted late detail")
	state.open();service.reply(state.ticket,page());old=state.ticket;service.session_changed.emit();service.reply(old,report())
	check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Session change retained case rows")
	for fault in 4:
		state.open();service.reply(state.ticket,page());service.reply(state.ticket,report(9,0,2));var second:=report(9,1,2)
		match fault:
			0:second.justice.detail.revision=13
			1:second.justice.detail.crime_id=10
			2:second.justice.detail.witnesses=[]
			3:second.justice.detail.status="changed"
		service.reply(state.ticket,second);check(state.phase==State.Phase.Ready and state.detail.is_empty() and state.ticket==0,"Malformed detail accepted or replayed")
	state.open();var stale: Dictionary={"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Stale,"tab":0}}
	service.reply(state.ticket,stale);check(service.calls[state.ticket].intent.expected_list_revision==0,"Stale list restart lost initial request")
	service.reply(state.ticket,stale);check(state.phase==State.Phase.Rejected and state.ticket==0,"Stale retry unbounded")
	test_candidates(service,state)
	test_sorts(service,state)
	test_interrogation(service,state)
	test_guard(service,state)
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("JUSTICE_STATE_PASS")
	quit(1 if failures else 0)
