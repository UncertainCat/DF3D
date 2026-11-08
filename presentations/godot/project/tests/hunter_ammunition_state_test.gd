extends SceneTree
const State=preload("res://scripts/hunter_ammunition_state.gd")
const Owner=preload("res://scripts/hunter_ammunition_panel.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func snapshot() -> Dictionary:
	return {"hunter_ammunition":{"outcome":C.HunterAmmunitionOutcome.None,"specs":[{"item_type":39,"item_subtype":0,"material_class":-1,"mattype":-1,"matindex":-1,"amount":100,"flags":3,"assigned":PackedInt32Array([7,9])}],"rules":[{"caption":"Bolts","quantity":30,"items":[{"id":7,"caption":"Bolts","quantity":30}]}],"types":[{"item_type":39,"item_subtype":0,"foreign":false,"caption":"Bolts"}]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,snapshot());state.begin_amount(0)
	check(state.amount_text.is_empty(),"Native amount entry starts empty")
	state.set_amount_text("a-12.3x");check(state.amount_text=="123","Native quantity entry accepts digits only")
	state.set_amount_text("12345678901234567890");check(state.amount_text=="123456789012345678","Native quantity draft is capped at 18 digits")
	state.set_amount_text("125");state.begin_add();state.back()
	check(state.mode==State.Mode.Amount and state.amount_text=="125" and state.selected==0,"Add cancellation must restore the active quantity draft")
	state.begin_material(0);state.back()
	check(state.mode==State.Mode.Main and state.specs[0].amount==100,"Material lookup retires amount focus without applying it")
	state.begin_amount(0)
	state.set_amount_text("125");state.commit_amount()
	var pending:=state.ticket
	var intent: Dictionary=service.calls[pending].intent
	check(intent.amount==125 and intent.expected==snapshot().hunter_ammunition.specs,"Amount edit carries full native receipt")
	state.back();state.delete_rule(0)
	check(state.ticket==pending and state.phase==State.Phase.Applying,"Pending mutation cannot navigate or submit again")
	var receipt:=snapshot();receipt.hunter_ammunition.outcome=C.HunterAmmunitionOutcome.Applied;receipt.hunter_ammunition.specs[0].amount=125
	service.reply(pending,receipt)
	check(state.phase==State.Phase.Reading and state.rules.is_empty(),"Applied receipt requires fresh display metadata")
	receipt.hunter_ammunition.outcome=C.HunterAmmunitionOutcome.None
	service.reply(state.ticket,receipt);state.begin_material(0);pending=state.ticket;state.back()
	service.reply(pending,{"hunter_ammunition":{"outcome":0,"item_type":39,"item_subtype":0,"materials":[{"caption":"Wood bolts","material_class":3,"mattype":-1,"matindex":-1}]}})
	check(state.phase==State.Phase.Ready and state.mode==State.Mode.Main and state.materials.is_empty(),"Cancelled material lookup cannot replace main view")
	state.begin_add();state.choose(0)
	check(service.calls[state.ticket].intent.operation==C.HunterAmmunitionOperation.Add,"Type picker submits native identity")
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
	var count:=service.next;state.begin_add();state.choose(0)
	check(state.phase==State.Phase.Unknown and state.specs.is_empty() and service.next==count,"Uncertain mutation discards authority without replay")
	state.open();pending=state.ticket;state.close();service.reply(pending,snapshot())
	check(state.phase==State.Phase.Closed and state.specs.is_empty() and pending in service.detached,"Closed owner ignores late reads")
	state.open();pending=state.ticket;service.session_changed.emit();service.reply(pending,snapshot())
	check(state.phase==State.Phase.Unavailable and state.specs.is_empty(),"Session replacement retires authority")
	state.open();var malformed:=snapshot();malformed.hunter_ammunition.rules[0]=7
	service.reply(state.ticket,malformed)
	check(state.phase==State.Phase.Rejected and state.specs.is_empty(),"Malformed rule cannot publish partial authority")
	state.open();service.reply(state.ticket,snapshot());state.remove_stack(0,8)
	check(state.ticket==0,"Unassigned stack cannot be removed")
	state.remove_stack(0,7)
	check(service.calls[state.ticket].intent.item_id==7,"Removal retains selected assigned identity")
	service.reply(state.ticket,{"status":C.ManagementStatus.Rejected,"hunter_ammunition":{"outcome":C.HunterAmmunitionOutcome.Stale}})
	check(state.phase==State.Phase.Rejected and state.specs.is_empty(),"Stale receipt requires reopening")
	for operation in [C.HunterAmmunitionOperation.Add,C.HunterAmmunitionOperation.Remove,C.HunterAmmunitionOperation.Delete]:
		state.open();service.reply(state.ticket,snapshot());state.begin_amount(0);state.set_amount_text("125")
		var result:=snapshot()
		if operation==C.HunterAmmunitionOperation.Add:
			state.begin_add();state.choose(0)
		elif operation==C.HunterAmmunitionOperation.Remove:
			state.remove_stack(0,7);result.hunter_ammunition.specs[0].assigned=PackedInt32Array([9]);result.hunter_ammunition.rules[0].items=[];result.hunter_ammunition.rules[0].quantity=0
		else:
			state.delete_rule(0);result.hunter_ammunition.specs=[];result.hunter_ammunition.rules=[]
		result.hunter_ammunition.outcome=C.HunterAmmunitionOutcome.Applied;service.reply(state.ticket,result)
		result.hunter_ammunition.outcome=C.HunterAmmunitionOutcome.None;service.reply(state.ticket,result)
		check(state.mode==State.Mode.Amount and state.selected==0 and state.amount_text=="125","Structural action must preserve the active native amount draft")
		state.commit_amount()
		if operation==C.HunterAmmunitionOperation.Delete:check(state.ticket==0 and state.mode==State.Mode.Main,"Enter after deleting the target must clear entry without sending a mutation")
		else:check(service.calls[state.ticket].intent.amount==125 and service.calls[state.ticket].intent.expected==state.specs,"Retained draft must use the refreshed receipt")
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("HUNTER_AMMUNITION_STATE_PASS")
	quit(1 if failures else 0)
