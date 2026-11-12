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
func test_case_return(service,state) -> void:
	ready(service,state);state.select_case(10);var old: int=state.ticket
	state.select_tab(2);service.reply(state.ticket,page([0,1],0,2,2));service.reply(state.ticket,report(0,0,1,12,2))
	state.select_tab(0);var current: int=state.ticket
	service.reply(old,report(10));check(state.ticket==current and state.detail.is_empty(),"Hidden case reply revived details")
	check(service.calls[current].intent.expected_list_revision==0,"Case return reused stale list receipt")
	service.reply(current,page());check(state.selected_id==10 and state.detail.is_empty() and service.calls[state.ticket].intent.crime_id==10,"Case return lost selection or reused details")
	service.reply(state.ticket,report(10));state.select_tab(2);state.select_tab(0)
	service.reply(state.ticket,page([9],0,1));check(state.selected_id==9,"Removed retained case did not fall back")
	state.close();ready(service,state);check(state.selected_id==9,"Closed Justice retained case selection")
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
	ready(service,state);state.open_candidates();old=picker.ticket
	check(state.close_candidates() and state.phase==State.Phase.Ready and state.selected_id==9,"Picker return lost parent case")
	service.reply(old,candidates());check(picker.phase==picker.Phase.Closed and picker.rows.is_empty(),"Late candidate read reopened returned picker")
	state.open_candidates();service.reply(picker.ticket,candidates());picker.convict(42)
	check(not state.close_candidates() and picker.phase==picker.Phase.Applying,"Picker return interrupted pending edit")
	service.reply(picker.ticket,{"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Unknown}})
	check(not state.close_candidates() and picker.phase==picker.Phase.Unknown,"Picker return discarded unknown edit")
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
func convicts_page(ids: Array=[42,43]) -> Dictionary:
	var value:=guard_page(ids,0,ids.size());value.justice.tab=4;value.justice.convicts={"rows":value.justice.guard.rows};value.justice.erase("guard");return value
func convict_detail(id:=42,offset:=0,total:=1,revision:=33) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":4,"list_revision":31,"convict_detail":{"unit_id":id,"revision":revision,"sentence":["fixture"],"total":total,"offset":offset,"crimes":[{"crime_id":offset+5,"caption":"fixture"}]}}}
func test_convicts(service,state) -> void:
	state.open(4);var roster=state.convicts;service.reply(roster.ticket,convicts_page())
	check(roster.phase==roster.Phase.DetailReading and roster.cursor_id==42 and service.calls[roster.ticket].intent.unit_id==42,"Convicts initial selection failed")
	service.reply(roster.ticket,convict_detail(42,0,2));check(roster.detail.is_empty() and service.calls[roster.ticket].intent.expected_case_revision==33,"Partial convict details leaked")
	var old: int=roster.ticket;roster.select_unit(43);var current: int=roster.ticket
	service.reply(old,convict_detail(42,1,2));check(roster.ticket==current and roster.detail.is_empty(),"Old convict details replaced selection")
	service.reply(current,convict_detail(43));check(roster.detail.unit_id==43,"Selected convict details lost")
	roster.select_unit(42);old=roster.ticket;roster.search("new");current=roster.ticket
	service.reply(old,convict_detail());check(roster.ticket==current and roster.detail.is_empty(),"Search retained previous convict details")
	service.reply(current,convicts_page());service.reply(roster.ticket,convict_detail(42,0,2))
	service.reply(roster.ticket,convict_detail(42,1,2,34));check(roster.detail.is_empty() and roster.phase==roster.Phase.Ready,"Changed sentence revision mixed pages")
	roster.select_unit(43);old=roster.ticket;state.select_tab(3);service.reply(old,convict_detail(43))
	check(roster.phase==roster.Phase.Closed and roster.detail.is_empty(),"Tab switch retained convict selection")
	state.select_tab(4)
	check(roster.query=="new" and roster.rows.is_empty() and roster.revision==0 and service.calls[roster.ticket].intent.expected_list_revision==0,"Tab return reused stale roster facts or lost query")
	service.reply(roster.ticket,convicts_page());check(roster.cursor_id==43 and roster.detail.is_empty() and service.calls[roster.ticket].intent.unit_id==43,"Tab return lost selected convict or reused detail")
	old=roster.ticket;state.select_tab(3);state.select_tab(4);current=roster.ticket
	service.reply(old,convict_detail(43));check(roster.ticket==current and roster.detail.is_empty(),"Retired tab detail replaced fresh read")
	service.reply(current,convicts_page([42]));check(roster.cursor_id==42,"Shrunken roster did not clamp retained cursor")
	state.close();state.open(4);check(roster.query.is_empty() and roster.draft().cursor==0,"Closed Justice retained roster draft")
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
	test_case_return(service,state)
	test_guard(service,state)
	test_convicts(service,state)
	test_intelligence(service,state)
	test_graph(service,state)
	test_empty_intelligence(service,state)
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("JUSTICE_STATE_PASS")
	quit(1 if failures else 0)

func intelligence_page(selected: int=-1,offset: int=0,total: int=1,revision: int=22,columns: int=0) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":5,"list_revision":revision,"offset":offset,"total":total,"intelligence":{"report_index":selected,"text_columns":columns,"reports":[{"index":offset,"title":"synthetic","officer":"synthetic","viewed":false}] if selected<0 else [],"lines":["synthetic line"] if selected>=0 else []}}}
func test_intelligence(service,state) -> void:
	state.open(5);var model=state.intelligence
	service.reply(model.ticket,intelligence_page(-1,0,2));check(model.rows.is_empty(),"Partial intelligence roster exposed")
	service.reply(model.ticket,intelligence_page(-1,1,2));model.select_report(0)
	service.reply(model.ticket,intelligence_page(0,0,2,22,112));check(model.lines.is_empty(),"Partial intelligence text exposed")
	var old: int=model.ticket;model.resize_columns(70);var current: int=model.ticket
	service.reply(old,intelligence_page(0,1,2,22,112));check(model.ticket==current and model.lines.is_empty(),"Old wrap width replaced report")
	service.reply(current,intelligence_page(0,0,1,22,70));check(model.lines==["synthetic line"],"Intelligence detail did not settle")
	model.select_report(1);old=model.ticket;state.close();service.reply(old,intelligence_page(1,0,1,22,70));check(model.phase==model.Phase.Closed and model.lines.is_empty(),"Closed intelligence accepted late report")
	state.open(5);service.reply(model.ticket,intelligence_page());model.select_report(0)
	service.reply(model.ticket,intelligence_page(0,0,1,23,70));check(model.phase==model.Phase.Rejected and model.lines.is_empty(),"Changed intelligence receipt accepted")

func graph_page(kind: int,offset: int=0,revision: int=33) -> Dictionary:
	var data:={"kind":kind,"actor_count":2,"organization_count":1,"plot_count":1,"node_count":2,"actors":[],"organizations":[],"plots":[],"nodes":[]}
	match kind:
		1:data.actors=[{"historical_figure":offset,"identity":-1,"name":"synthetic","aliases":[],"principal_organization":0,"organizations":[],"plots":[0]}]
		2:data.organizations=[{"name":"synthetic","principal_actor":0,"first_node":0,"node_count":2}]
		3:data.plots=[{"agreement":11,"master":0,"name":"synthetic"}]
		4:data.nodes=[{"organization":0,"actor":0,"parent":-1},{"organization":0,"actor":1,"parent":0}]
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":5,"list_revision":revision,"offset":offset,"total":[2,1,1,2][kind-1],"graph":data}}
func test_graph(service,state) -> void:
	state.open(5);var model=state.intelligence.graph
	service.reply(model.ticket,graph_page(1));check(model.graph.is_empty() and service.calls[model.ticket].intent.offset==1,"Partial graph actor stream escaped")
	service.reply(model.ticket,graph_page(1,1));service.reply(model.ticket,graph_page(2));service.reply(model.ticket,graph_page(3))
	check(model.graph.is_empty(),"Graph published before node stream")
	service.reply(model.ticket,graph_page(4));check(model.phase==model.Phase.Ready and model.graph.nodes.size()==2,"Graph did not assemble")
	var intelligence=state.intelligence
	service.reply(intelligence.ticket,intelligence_page());intelligence.select_report(0)
	var pending_report: int=intelligence.ticket;intelligence.select_mode(1)
	check(intelligence.selected==-1 and intelligence.ticket==0 and intelligence.phase==intelligence.Phase.Ready,"Graph tab retained pending report detail")
	service.reply(pending_report,intelligence_page(0,0,1,22,intelligence.columns));intelligence.select_mode(0)
	check(intelligence.mode==0 and intelligence.lines.is_empty() and intelligence.rows.size()==1,"Late report reply reopened detail after tab switch")
	intelligence.select_report(0);service.reply(intelligence.ticket,intelligence_page(0,0,1,22,intelligence.columns))
	intelligence.select_mode(1);intelligence.select_mode(0)
	check(intelligence.selected==-1 and intelligence.lines.is_empty(),"Returning from graph retained settled report detail")
	state.open(5);service.reply(model.ticket,graph_page(1));service.reply(model.ticket,graph_page(1,1));service.reply(model.ticket,graph_page(2,0,34))
	check(model.phase==model.Phase.Rejected and model.graph.is_empty(),"Graph mixed receipts between kinds")
	state.open(5);var old: int=model.ticket;state.close();service.reply(old,graph_page(1));check(model.phase==model.Phase.Closed and model.graph.is_empty(),"Closed graph accepted late data")
	state.open(5);old=model.ticket;service.session_changed.emit();service.reply(old,graph_page(1));check(model.phase in [model.Phase.Closed,model.Phase.Unavailable] and model.graph.is_empty() and state.phase==state.Phase.Unavailable,"Graph crossed session boundary")

func test_empty_intelligence(service,state) -> void:
	state.open(5);var model=state.intelligence
	check(not model.empty(),"Pending intelligence claimed empty")
	var reports:=intelligence_page(-1,0,0);reports.justice.intelligence.reports=[]
	service.reply(model.ticket,reports)
	check(not model.empty(),"Empty reports concealed pending graph")
	for kind in range(1,5):
		var reply:=graph_page(kind);reply.justice.total=0
		for key in model.graph.COUNTS:reply.justice.graph[key]=0
		for key in model.graph.KEYS:reply.justice.graph[key]=[]
		service.reply(model.graph.ticket,reply)
	check(model.empty(),"Confirmed empty intelligence not recognized")
	state.open(5);service.reply(model.ticket,reports)
	service.reply(model.graph.ticket,{"outcome":"unknown"})
	check(not model.empty(),"Failed graph read claimed empty")
