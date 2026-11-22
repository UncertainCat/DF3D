extends SceneTree
const State=preload("res://scripts/residents_state.gd")
const View=preload("res://scripts/residents_view.gd")
const C=preload("res://scripts/management_contract.gd")
const Owner=preload("res://scripts/residents_panel.gd")
const Shell=preload("res://scripts/fortress_ui.gd")
const PetState=preload("res://scripts/pet_management_state.gd")
const PetView=preload("res://scripts/pet_management_view.gd")
class MissingCreatureWorld extends RefCounted:
	func inspect_tile(_tile):return [{"kind":1,"id":7}]
	func inspect_entity(_kind,_id):return {}
class Interaction extends Node:
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=true
	var panel:=Control.new()
	func _ready():add_child(panel)
	func cancel_selection():pass
	func set_play_enabled(_value):pass
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,request: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"request":request.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket]
		var result:=payload.duplicate(true);result.status=C.ManagementStatus.Ok;result.action=call.request.action
		call.observer.call(ticket,result,call.request)
var failures:=0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func sibling_row(kind: int,id: int,inspectable:=true) -> Dictionary:
	return {"kind":kind,"id":id,"first_line":"fixture","second_line":"","can_inspect":inspectable,
		"activity":{"text":"fixture activity","foreground":2,"background":0,"bright":true},
		"pet":{"revision":9,"controls":[{"action":C.PetAction.Adoption,"value":false}]}}
func siblings() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.capacity=2;state.open()
	var residents_ticket:=state.ticket;state.select_tab(1)
	check(service.calls[state.ticket].domain=="creature_list" and service.calls[state.ticket].request.tab==1,"Pets uses the native sibling query")
	service.reply(residents_ticket,{"residents":{"unit_ids":PackedInt32Array([999])}})
	check(state.ids.is_empty(),"Tab replacement retires the resident query")
	service.reply(state.ticket,{"creature_list":{"tab":1,"entries":[{"kind":0,"id":7},{"kind":1,"id":7}]}})
	check(state.ids==PackedInt32Array([7,-8]) and service.calls[state.ticket].request.targets==[{"kind":0,"id":7},{"kind":1,"id":7}],"Typed identities survive equal native IDs")
	service.reply(state.ticket,{"creature_list_rows":{"tab":1,"rows":[sibling_row(0,7),sibling_row(1,7)]}})
	check(state.rows.size()==2 and state.row_at(1).kind==1 and state.row_at(0).activity.caption=="fixture activity","Sibling rows retain typed identity and native activity")
	var inspected: Array[int]=[];state.item_inspect_ready.connect(func(id):inspected.append(id))
	var before:=service.next;state.inspect(-8)
	check(inspected==[7] and service.next==before,"Item sheet handoff never sends a creature-unit request")
	state.pet_action(-8,C.PetAction.Adoption)
	var edit:=state.ticket;var intent: Dictionary=service.calls[edit].request
	check(intent.target=={"kind":1,"id":7} and intent.expected_revision==9 and intent.desired,"Pet edit carries typed identity and observed receipt")
	state.select_tab(2);check(state.tab==1,"Pending mutation blocks tab replacement")
	service.reply(edit,{"pet_edit":{"target":{"kind":1,"id":7},"outcome":C.PetOutcome.Unknown}})
	check(state.phase==State.Phase.Rejected and state.ticket==0 and service.next==edit,"Unknown mutation is not refreshed or replayed")
	state.select_tab(2);var other:=state.ticket;state.select_tab(3)
	service.reply(other,{"creature_list":{"tab":2,"entries":[{"kind":0,"id":999}]}})
	check(state.ids.is_empty(),"Late sibling query cannot enter another tab")
	service.reply(state.ticket,{"creature_list":{"tab":3,"entries":[{"kind":0,"id":7}]}})
	var dead:=sibling_row(0,7,false);dead.erase("pet")
	service.reply(state.ticket,{"creature_list_rows":{"tab":3,"rows":[dead]}})
	before=service.next;state.inspect(7);state.select_sort(C.ResidentsSort.Stress);state.select_sort(C.CreatureListSort.Slaughterability)
	check(service.next==before and not state.row_at(0).can_inspect,"Dead rows suppress sheet navigation and unsupported sorts")
	state.refresh();var pending:=state.ticket;state.close()
	service.reply(pending,{"creature_list":{"tab":3,"entries":[{"kind":0,"id":7}]}})
	check(state.phase==State.Phase.Closed and state.ids.is_empty(),"Closing retires sibling reads")
	state.dispose()
func pet_panes() -> void:
	var service:=Service.new();var state:=PetState.new();state.configure(service);state.capacity=2
	var animal: Dictionary={"kind":0,"id":7,"pet":{"revision":9,"controls":[{"action":C.PetAction.Trainer}]}}
	state.open_trainers(animal)
	check(service.calls[state.ticket].request.unit_ids.is_empty(),"Trainer root reads complete native order before row content")
	var trainer_root: Dictionary={"animal_id":7,"revision":9,"assigned":false,"trainer_id":-1,"any_trainer":false,"unassigned_only":false,"unit_ids":PackedInt32Array([11,12]),"rows":[]}
	service.reply(state.ticket,{"pet_trainers":trainer_root})
	check(state.total==5 and state.row_at(0).mode==C.PetTrainerMode.Any and state.row_at(2).mode==C.PetTrainerMode.None,"Native generic trainer choices precede candidates")
	state.seek(3,2);var page_ticket:=state.ticket
	check(service.calls[page_ticket].request.unit_ids==PackedInt32Array([11,12]),"Trainer viewport requests native candidate IDs")
	trainer_root.unit_ids=PackedInt32Array([12,11]);trainer_root.rows=[{"id":11,"skills":[]},{"id":12,"skills":[]}]
	service.reply(page_ticket,{"pet_trainers":trainer_root})
	check(state.phase==PetState.Phase.Ready and state.row_at(3).id==12,"Fresh native candidate order replaces the displayed order")
	state.select_trainer(C.PetTrainerMode.Individual,11)
	var edit:=state.ticket
	check(service.calls[edit].request.expected_revision==9 and service.calls[edit].request.trainer_id==11,"Trainer selection uses the observed revision")
	state.open_knowledge();check(state.ticket==edit and state.pane==PetState.Pane.Trainers,"Pending trainer edit blocks pane replacement")
	service.reply(edit,{"pet_edit":{"target":{"kind":0,"id":7},"outcome":C.PetOutcome.Unknown}})
	check(state.phase==PetState.Phase.Unknown and service.next==edit,"Unknown trainer result neither refreshes nor retries")
	state.close();state.open_knowledge()
	service.reply(state.ticket,{"pet_knowledge":{"revision":91,"total":5,"offset":0,"rows":[{"race":1},{"race":2}]}})
	state.seek(3,2);page_ticket=state.ticket
	check(service.calls[page_ticket].request.offset==3 and service.calls[page_ticket].request.expected_revision==91,"Knowledge continuation binds the complete list receipt")
	state.seek(1,2)
	service.reply(page_ticket,{"pet_knowledge":{"revision":91,"total":5,"offset":3,"rows":[{"race":4},{"race":5}]}})
	check(service.calls[state.ticket].request.offset==2,"Scrolling during a knowledge read fills the current viewport")
	service.reply(state.ticket,{"pet_knowledge":{"revision":92,"total":5,"offset":2,"rows":[{"race":3}]}})
	check(state.phase==PetState.Phase.Rejected,"Changed knowledge receipt cannot combine pages")
	state.open_trainers(animal);page_ticket=state.ticket;state.close()
	service.reply(page_ticket,{"pet_trainers":trainer_root})
	check(state.phase==PetState.Phase.Closed and state.rows.is_empty(),"Closing the picker retires late candidate reads")
	state.open_trainers(animal);trainer_root.unit_ids=PackedInt32Array();trainer_root.rows=[]
	service.reply(state.ticket,{"pet_trainers":trainer_root})
	state.select_trainer(C.PetTrainerMode.None);edit=state.ticket
	var call: Dictionary=service.calls[edit]
	call.observer.call(edit,{"status":C.ManagementStatus.Rejected,"action":C.ManagementAction.PetTrainerApply,"pet_edit":{"target":{"kind":0,"id":7},"outcome":C.PetOutcome.Rejected}},call.request)
	check(state.phase==PetState.Phase.Closed and service.next==edit,"Authoritative no-op permits local dismissal without replay")
	state.open_trainers(animal);service.reply(state.ticket,{"pet_trainers":trainer_root})
	var view:=PetView.new();view.state=state;root.add_child(view);view.size=Vector2(944,708);view.refresh()
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(80,view.content_top()+18)
	view._gui_input(click)
	check(service.calls[state.ticket].request.mode==C.PetTrainerMode.Any,"Actual generic trainer row click dispatches its native mode")
	service.reply(state.ticket,{"pet_edit":{"target":{"kind":0,"id":7},"outcome":C.PetOutcome.Applied}})
	check(state.phase==PetState.Phase.Closed,"Applied trainer choice closes the pane")
	view.free();state.dispose()
func roster_tab_input() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.open()
	var view:=View.new();view.state=state;view.search=Control.new();view.add_child(view.search);root.add_child(view)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Vector2(140,view.list_top()-48);view._gui_input(click)
	check(state.tab==0,"Unqualified sibling tabs retain their public gate")
	view.creature_tabs_enabled=true;view._gui_input(click)
	check(state.tab==1 and service.calls[state.ticket].request.tab==1,"Pets tab dispatches its native roster query")
	var specs:=view.sort_specs()
	check(specs.size()==5 and specs[4].sort==C.CreatureListSort.Slaughterability and specs[4].x==92,"Pets header targets native Slaughterability rather than Residents stress")
	service.reply(state.ticket,{"creature_list":{"tab":1,"entries":[{"kind":1,"id":7}]}})
	service.reply(state.ticket,{"creature_list_rows":{"tab":1,"rows":[sibling_row(1,7)]}})
	view.page_rows=1;view.size=Vector2(944,708)
	var training: Array=[];view.knowledge_requested.connect(func():training.append(true))
	click.position=view.activity_close_rect().position+Vector2(20,12);view._gui_input(click)
	check(training==[true],"Overall Training button opens the knowledge workflow")
	click.position=Vector2(964,view.list_top()+12);view._input(click)
	check(service.calls[state.ticket].request.target=={"kind":1,"id":7} and service.calls[state.ticket].request.pet_action==C.PetAction.Adoption,"Pet adoption button submits the displayed typed target")
	service.reply(state.ticket,{"pet_edit":{"target":{"kind":1,"id":7},"outcome":C.PetOutcome.Applied}})
	click.position=Vector2(740,view.list_top()-18);view._gui_input(click)
	check(service.calls[state.ticket].request.sort==C.CreatureListSort.Slaughterability,"Pets sort arrow dispatches its native sort")
	state.phase=State.Phase.Applying;click.position=Vector2(280,view.list_top()-48);view._gui_input(click)
	check(state.tab==1,"Pending pet action blocks sibling-tab replacement")
	state.phase=State.Phase.Ready;view._gui_input(click);specs=view.sort_specs()
	check(state.tab==2 and specs.size()==4 and specs[3].x==46,"Other omits the Residents stress control")
	click.position=Vector2(360,view.list_top()-48);view._gui_input(click);specs=view.sort_specs()
	check(state.tab==3 and specs.size()==4 and specs[3].x==38,"Dead activity sort uses the column without navigation buttons")
	click.position=Vector2(308,view.list_top()-18);view._gui_input(click)
	check(service.calls[state.ticket].request.sort==C.CreatureListSort.Activity,"Dead activity arrow dispatches the native activity sort")
	view.free();state.dispose()
func pet_help_input() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service)
	var view:=View.new();view.state=state;view.search=Control.new();view.add_child(view.search);root.add_child(view);view.set_process(false)
	view.size=Vector2(944,708);view.page_rows=1;state.tab=1
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.set_process(false);view.hover_help=help
	var trainers: Array=[];view.trainer_requested.connect(func(key):trainers.append(key))
	var cases=[[C.PetAction.Trainer,247,KEY_T,656],[C.PetAction.War,249,KEY_W,680],[C.PetAction.Hunting,250,KEY_H,704],[C.PetAction.Adoption,251,KEY_E,960],[C.PetAction.Slaughter,270,KEY_B,936],[C.PetAction.Gelding,271,KEY_G,984]]
	for sample in cases:
		state.retire()
		var key: int=-8 if sample[0]==C.PetAction.Adoption else 7
		var control: Dictionary={"action":sample[0],"value":false,"help_observed":true,"hover_help":sample[1]}
		state.ids=PackedInt32Array([key]);state.rows={key:{"kind":1 if key<0 else 0,"id":7,"pet":{"revision":9,"controls":[control]}}};state.phase=State.Phase.Ready
		view.pointer_known=true;view.pointer_position=Vector2(sample[3]+8,view.list_top()+18);view.update_hover()
		check(help.state.key=="pet_"+str(sample[1]),"Pet control owns its native help even in overlapping Residents columns")
		var event:=InputEventKey.new();event.pressed=true;event.ctrl_pressed=true;event.keycode=KEY_Q
		var before:=service.next;view._input(event);check(service.next==before,"Unrelated shortcut cannot activate pet control")
		event.keycode=sample[2];view._input(event)
		if sample[0]==C.PetAction.Trainer:check(trainers==[7] and service.next==before,"Ctrl+t opens trainer picker without submitting a mutation")
		else:
			check(service.next==before+1 and service.calls[state.ticket].request.target==state.identity(key) and service.calls[state.ticket].request.pet_action==sample[0] and service.calls[state.ticket].request.expected_revision==9,"Pet shortcut submits current typed target and observed receipt")
		state.phase=State.Phase.Applying;before=service.next;view._input(event);view.update_hover()
		check(service.next==before and help.state.key.is_empty(),"Pending pet edit excludes shortcuts and releases hover help")
	state.phase=State.Phase.Ready;state.rows[state.ids[0]].pet.controls[0].help_observed=false
	view.update_hover();check(help.state.key.is_empty(),"Unobserved help does not invent a tooltip")
	view.hide();view.update_hover();help.free();view.hover_help=null;view.free();state.dispose()

func pet_scrollbar_input() -> void:
	root.size=Vector2i(1200,800)
	var view:=View.new();root.add_child(view);view.set_process(false)
	view.state=State.new();view.state.tab=1;view.state.phase=State.Phase.Ready
	view.position=Vector2(32,52);view.size=Vector2(944,708);view.page_rows=13
	var bar=preload("res://scripts/area_location_scrollbar.gd").new();view.add_child(bar)
	bar.configure(null);bar.position=Vector2(view.roster_scrollbar_x(),view.list_top());bar.size=Vector2(16,504);bar.page=13;bar.set_rows(17)
	bar.input_allowed=view.allowed
	await process_frame
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=view.position+bar.position+Vector2(8,498);root.push_input(click,true)
	click.pressed=false;root.push_input(click,true)
	check(bar.first==1,"Pets scrollbar outside the frame receives actual viewport input")
	view.free()
func other_activity_selection() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service)
	state.tab=2;state.phase=State.Phase.Ready;state.roster_ready=true
	state.ids=PackedInt32Array([7,42]);state.rows={7:{"id":7},42:{"id":42,"activity_target":{"activity_id":50,"event_id":8}}}
	state.show_activity(42,110)
	check(state.cursor==1 and state.phase==State.Phase.ActivityReading,"Native Other Details selects its row")
	service.reply(state.ticket,{"residents_activity":{"unit_id":42,"activity_id":50,"event_id":8,"columns":110,"max_y":1,"words":[],"links":[]}})
	state.close_activity()
	check(state.cursor==1 and state.phase==State.Phase.Ready,"Other Close retains selected row")
	state.dispose()
func cursor_navigation() -> void:
	var state:=State.new();state.tab=3;state.phase=State.Phase.Ready;state.capacity=13
	for id in 55:state.ids.append(id)
	var view:=View.new();view.state=state;view.search=Control.new();view.add_child(view.search);root.add_child(view);view.set_process(false)
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_PAGEDOWN;view._input(key)
	check(state.cursor==13 and state.first==1,"Native page-down moves13 rows and scrolls just one row")
	state.cursor=0;state.first=0;key.keycode=KEY_DOWN
	for repeat in 20:view._input(key)
	check(state.cursor==20 and state.first==8,"Native repeated down keeps cursor visible")
	key.keycode=KEY_UP
	for repeat in 20:view._input(key)
	check(state.cursor==0 and state.first==0,"Native repeated up returns to first row")
	state.ids=PackedInt32Array([1,2,3,4,5,6,7,8]);key.keycode=KEY_PAGEDOWN;view._input(key)
	check(state.cursor==7 and state.first==0,"Short roster cursor clamps without scrolling")
	state.phase=State.Phase.Applying;key.keycode=KEY_UP;view._input(key)
	check(state.cursor==7,"Pending mutation excludes cursor changes")
	view.free();state.dispose()
func run() -> void:
	other_activity_selection()
	cursor_navigation()
	pet_help_input()
	await pet_scrollbar_input()
	roster_tab_input()
	siblings()
	var trainer_display:=preload("res://scripts/pet_row_view.gd").training_captions({"pet":{"training":[
		{"text":"","foreground":7,"bright":true},
		{"text":"Trainer: Kumil Dorenothlest, Animal Trainer, ♂","foreground":7,"bright":true}]}},120)
	check(trainer_display.size()==1 and trainer_display[0].text=="Trainer: Kumil Doreno..." and trainer_display[0].point==Vector2(368,156),"Native125944 trainer caption keeps its activity column and24 glyph ellipsis; blank placeholder occupies no line")
	var pet_layout:=View.new();pet_layout.state=State.new();pet_layout.size=Vector2(944,708)
	pet_layout.state.tab=1
	check(pet_layout.roster_scrollbar_x()==1048 and pet_layout.row_background_columns()==128,"Native Pets minimum width keeps scrollbar beyond action columns")
	pet_layout.size.x=1344
	check(pet_layout.roster_scrollbar_x()==1312,"Pets scrollbar follows a wider viewport")
	pet_layout.state.tab=0;pet_layout.size.x=944
	check(pet_layout.roster_scrollbar_x()==912 and pet_layout.row_background_columns()==111,"Residents retains its accepted row layout")
	pet_layout.free()
	pet_panes()
	var service:=Service.new();var state:=State.new();state.configure(service);state.capacity=2;state.open()
	var stale:=state.ticket
	state.set_query(PackedByteArray([84,195]))
	check(service.detached.has(stale) and service.calls[state.ticket].request.query_bytes==PackedByteArray([84,195]),"Raw textbox bytes survive replacement")
	service.reply(stale,{"residents":{"unit_ids":PackedInt32Array([999])}})
	check(state.ids.is_empty(),"Late superseded roster cannot publish")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7,19,3])}})
	var first_batch:=state.ticket
	check(service.calls[first_batch].request.unit_ids==PackedInt32Array([42,7]),"Rows follow native order")
	state.seek(2,2)
	service.reply(first_batch,{"residents_rows":{"rows":[{"id":42},{"id":7}]}})
	check(service.calls[state.ticket].request.unit_ids==PackedInt32Array([19,3]),"Scroll during read fills current viewport next")
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":19},{"id":3}]}})
	check(state.phase==State.Phase.Ready and state.row_at(2).id==19 and state.rows.size()<=4,"Visible rows become ready without reordering")
	state.select_sort(C.ResidentsSort.Name);state.select_sort(C.ResidentsSort.Name)
	state.select_sort(C.ResidentsSort.Activity);state.select_sort(C.ResidentsSort.Name)
	check(state.directions[C.ResidentsSort.Name] and service.calls[state.ticket].request.descending,"Reselecting inactive header retains direction")
	var old:=state.ticket;service.session_changed.emit()
	service.reply(old,{"residents":{"unit_ids":PackedInt32Array([42])}})
	check(state.phase==State.Phase.Unavailable and state.ids.is_empty() and state.rows.is_empty(),"Session retirement rejects late rows")
	state.open();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array()}})
	check(state.phase==State.Phase.Ready and state.ticket==0,"Empty native search requires no content request")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":7},{"id":42}]}})
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Mismatched row receipt cannot acquire identity authority")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":false,"revision":91}}]}})
	state.specialize(42);var edit_ticket:=state.ticket
	check(state.phase==State.Phase.Applying and service.calls[edit_ticket].request.only_assigned and service.calls[edit_ticket].request.expected_revision==91,"Specialization uses the displayed receipt")
	state.specialize(42);check(state.ticket==edit_ticket,"Pending edit cannot be repeated")
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":true}})
	check(state.phase==State.Phase.Reading and service.calls[state.ticket].request.action==C.ManagementAction.ResidentsQuery,"Successful edit refreshes native rows")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":true,"revision":92}}]}})
	state.specialize(42);edit_ticket=state.ticket;state.close()
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":false}})
	check(state.phase==State.Phase.Closed and state.ticket==0 and state.rows.is_empty(),"Late edit completion cannot reopen a closed screen")
	state.open();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"activity_target":{"activity_id":50,"event_id":8}}]}})
	state.activity_capacity=44;state.show_activity(42,110)
	var activity_ticket:=state.ticket
	check(service.calls[activity_ticket].domain=="residents_activity" and service.calls[activity_ticket].request.event_id==8,"Activity opens the displayed native event")
	state.resize_activity(80)
	var page: Dictionary={"unit_id":42,"activity_id":50,"event_id":8,"columns":110,"max_y":60,"words":[],"links":[]}
	service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.ActivityReading and state.activity_page.is_empty(),"Late layout cannot replace resized Activity")
	page.columns=80;service.reply(state.ticket,{"residents_activity":page})
	state.scroll_activity(100,44)
	check(state.phase==State.Phase.ActivityReady and state.activity_first==17,"Activity scroll uses native line extent")
	state.resize_activity(90);activity_ticket=state.ticket;state.close_activity()
	page.columns=90;service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.Ready and not state.activity_open() and state.row_at(0).id==42,"Close restores roster and retires pending description")
	state.show_activity(42,110);page.columns=110;page.event_id=9
	service.reply(state.ticket,{"residents_activity":page})
	check(state.phase==State.Phase.ActivityRejected and state.activity_page.is_empty(),"Changed event cannot appear under the selected activity")
	state.close_activity();state.show_activity(42,110);activity_ticket=state.ticket
	service.session_changed.emit();page.event_id=8;service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.Unavailable and not state.activity_open(),"Session replacement retires Activity and late content")
	state.dispose()
	var view:=View.new();view.state=state;view.ticks_override=0
	view.search=LineEdit.new();view.add_child(view.search);root.add_child(view)
	view.size=Vector2(944,708);view.page_rows=2
	var inspected: Array[int]=[]
	var focused: Array[Vector3i]=[]
	view.inspect_requested.connect(func(id):inspected.append(id))
	view.focus_requested.connect(func(tile):focused.append(tile))
	state.ids=PackedInt32Array([7,42]);state.rows={7:{"id":7},42:{"id":42,"position":Vector3i(25,31,4)}};state.first=1;state.phase=State.Phase.Ready
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Vector2(348,view.list_top()+18);view._gui_input(click)
	check(inspected==[42],"Details uses the scrolled row identity")
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.set_process(false)
	view.hover_help=help;view.pointer_known=true;view.pointer_position=click.position;view.update_hover()
	check(help.state.key=="residents_details","Visible details control claims shared native help")
	view.hide();view.update_hover();check(help.state.key.is_empty(),"Hidden Residents releases its help claim")
	view.show();help.free();view.hover_help=null
	click.position.x=316;view._gui_input(click)
	check(focused==[Vector3i(25,31,4)],"Recenter uses the captured row position")
	state.rows[42].can_inspect=false;click.position.x=348;view._gui_input(click)
	check(inspected==[42] and view.hover_target(click.position).is_empty(),"Absent native sheet control has neither input nor hover target")
	state.rows[42].can_inspect=true
	state.rows[-43]={"kind":1,"id":42};state.ids=PackedInt32Array([42,-43]);view._gui_input(click)
	check(inspected==[42,-43],"Item and unit sheet buttons retain distinct typed identities")
	state.close();view._gui_input(click)
	check(inspected==[42,-43] and focused==[Vector3i(25,31,4)],"Closed rows cannot navigate using retired identity")
	view.free()
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner:=Owner.new();root.add_child(owner);owner.set_process(false)
	owner.panel=Control.new();owner.add_child(owner.panel);owner.ui_host=host;owner.state.configure(service);host.register(owner)
	var navigated: Array=[]
	owner.inspect_requested.connect(func(tile,id):navigated.append([tile,id]))
	owner.open_panel();service.reply(owner.state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(owner.state.ticket,{"residents_rows":{"rows":[{"id":42}]}})
	check(host.active==owner and interaction.construction_active and owner.panel.visible,"Residents owns the modal input gate")
	owner.job_state.configure(service)
	owner.state.rows[42].job_target={"job_id":71,"building_id":3}
	owner._job(42)
	var job_read: int=owner.job_state.ticket
	check(owner.job_open() and not owner.panel.visible and host.active==owner,"Job details retains the roster input owner")
	check(service.calls[job_read].request.job_id==71 and service.calls[job_read].request.building_id==3 and service.calls[job_read].request.unit_id==42,"Job entry uses the displayed row target")
	owner.job_state.close()
	check(owner.panel.visible and owner.state.rows[42].job_target.job_id==71 and host.active==owner,"Closing job details restores the retained roster")
	service.reply(job_read,{"job_settings":{}})
	check(not owner.job_open(),"Retired job read cannot reopen details")
	owner.state.inspect(42);var navigation: int=owner.state.ticket;owner.state.inspect(42)
	check(owner.state.ticket==navigation and service.calls[navigation].domain=="creature_sheet_location","Details has one semantic navigation request")
	service.reply(navigation,{"creature_position":{"unit_id":42,"position":Vector3i(5,6,7)}})
	check(navigated==[[Vector3i(5,6,7),42]],"Owner hands off resolved position and exact identity")
	owner.state.inspect(42);navigation=owner.state.ticket;host.reset_local_views()
	service.reply(navigation,{"creature_position":{"unit_id":42,"position":Vector3i(8,9,10)}})
	check(navigated.size()==1 and not owner.panel.visible and host.active==null and not interaction.construction_active,"Retired owner cannot navigate from a late reply")
	owner.open_panel();service.reply(owner.state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(owner.state.ticket,{"residents_rows":{"rows":[{"id":42}]}})
	owner.focus_requested.connect(func(tile):focused.append(tile))
	owner._focus(Vector3i(11,12,13))
	check(focused[-1]==Vector3i(11,12,13) and host.active==null and not owner.panel.visible,"Recenter closes the roster and releases world input")
	owner.free();host.free();interaction.free()
	var inspector=preload("res://scripts/context_inspector.gd").new()
	inspector.world=MissingCreatureWorld.new();inspector.panel=Panel.new();inspector.add_child(inspector.panel)
	check(not inspector.open_target(Vector3i(1,2,3),1,42,true) and inspector.selected.is_empty(),"Missing exact creature cannot select another tile occupant")
	# This isolated target check deliberately does not run the asset-heavy _ready.
	# Adopt the editor that _ready normally parents before tearing down the owner.
	inspector.customize.add_child(inspector.customize.entry)
	inspector.add_child(inspector.customize);inspector.free();var shell:=Shell.new();shell.free()
	if failures==0:print("RESIDENTS_STATE_PASS")
	quit(1 if failures else 0)
