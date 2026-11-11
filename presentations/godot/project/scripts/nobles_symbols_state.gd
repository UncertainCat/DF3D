extends RefCounted
# Selection is local; DF owns candidate order, effects and the naming tail.
signal changed
signal finished
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Naming,Rejected,Unknown}
var phase:=Phase.Closed
var service
var ticket:=0
var generation:=0
var target: Dictionary={}
var draft: Array=[]
var base_revision:=0
var candidate_revision:=0
var rows: Array=[]
var selected: Dictionary={}
var first:=0
var step: Dictionary={}
var last_result: Dictionary={}
var naming=preload("res://scripts/nobles_symbol_name_state.gd").new()
var _pending: Array=[]
var _seen: Dictionary={}
var _total:=-1
var _bytes:=0
func _init() -> void:
	naming.configure(self);naming.changed.connect(_name_changed)
func _name_changed() -> void:changed.emit()
func configure(source) -> void:close();service=source
func close() -> void:
	generation+=1
	if service!=null and ticket:service.detach(ticket)
	ticket=0;phase=Phase.Closed;rows=[];selected={};step={};target={};draft=[];first=0
	_pending=[];_seen={};_total=-1;_bytes=0;candidate_revision=0;last_result={};naming.reset();changed.emit()
func open(office: Dictionary,choices: Array,revision: int) -> void:
	close();target=office.duplicate(true);draft=choices.duplicate(true);base_revision=revision
	phase=Phase.Reading;_page()
func busy() -> bool:return ticket!=0 or phase in [Phase.Applying,Phase.Unknown]
func seek(value: int,capacity: int) -> void:
	if phase==Phase.Ready:first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func checked(row: Dictionary) -> bool:return selected.get(row.item_id,row.get("selected_office",{})==target)
func toggle(item: int) -> void:
	if phase!=Phase.Ready:return
	for row in rows:
		if row.item_id==item:
			var value: bool=not checked(row)
			if value==(row.get("selected_office",{})==target):selected.erase(item)
			else:selected[item]=value
			changed.emit();return
func _request(intent: Dictionary,callback: Callable) -> void:
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;callback.call(result)) if service!=null else 0
	if ticket==0:callback.call({"outcome":"not_sent"})
	changed.emit()
func _page() -> void:
	var intent: Dictionary={"action":C.ManagementAction.NoblesSymbolsRead,"offset":_pending.size(),"limit":32,"expected_list_revision":base_revision,"choices":draft,"target":target,"expected_candidate_revision":candidate_revision}
	_request(intent,func(result):
		var value: Dictionary=result.get("nobles",{})
		if result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or value.get("outcome")!=C.NoblesOutcome.None or not _valid_page(value,intent):
			last_result=result.duplicate(true);phase=Phase.Rejected;_pending=[];changed.emit();return
		candidate_revision=value.candidate_revision;_total=value.total;_pending.append_array(value.symbols.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};phase=Phase.Ready;changed.emit())
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("target")!=target or value.get("list_revision")!=base_revision or value.get("offset")!=intent.offset:return false
	if typeof(value.get("candidate_revision"))!=TYPE_INT or value.candidate_revision<=0 or typeof(value.get("total"))!=TYPE_INT or value.total<0 or value.total>1048576 or not value.get("symbols") is Array:return false
	if candidate_revision and (candidate_revision!=value.candidate_revision or _total!=value.total):return false
	if value.symbols.size()>32 or intent.offset+value.symbols.size()>value.total or (intent.offset<value.total and value.symbols.is_empty()):return false
	for row in value.symbols:
		if not row is Dictionary or typeof(row.get("item_id"))!=TYPE_INT or row.item_id<0 or _seen.has(row.item_id):return false
		_seen[row.item_id]=true;_bytes+=128
		for key in ["caption","office_caption","value_caption"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
			_bytes+=row[key].to_utf8_buffer().size()
	return _bytes<=64*1024*1024
func dismiss() -> void:
	if busy():return
	if phase==Phase.Naming:naming.done();return
	if phase==Phase.Reading or (phase==Phase.Rejected and step.is_empty()):_finish();return
	if phase!=Phase.Ready:return
	if selected.is_empty():_finish();return
	var edits: Array=[]
	for item in selected:edits.append({"item_id":item,"selected":selected[item]})
	var intent: Dictionary={"action":C.ManagementAction.NoblesSymbolsApply,"offset":0,"limit":32,"expected_list_revision":base_revision,"choices":draft,"target":target,"expected_candidate_revision":candidate_revision,"symbol_choices":edits}
	phase=Phase.Applying;_request(intent,func(result):_effect(result,intent.action))
func step_intent(action: int) -> Dictionary:
	return {"action":action,"offset":0,"limit":32,"expected_list_revision":0,"step_token":step.token}
func continue_step() -> void:
	if phase!=Phase.Naming or busy() or step.is_empty():return
	var intent:=step_intent(C.ManagementAction.NoblesSymbolsContinue)
	phase=Phase.Applying;_request(intent,func(result):_effect(result,intent.action))
func _effect(result: Dictionary,action: int) -> void:
	last_result=result.duplicate(true)
	var value: Dictionary=result.get("nobles",{})
	if result.get("outcome","")=="unknown" or value.get("outcome")==C.NoblesOutcome.Unknown:phase=Phase.Unknown;changed.emit();return
	if result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=action or value.get("outcome")!=C.NoblesOutcome.Applied:
		phase=Phase.Rejected if result.get("outcome","")=="not_sent" or value.get("outcome") in [C.NoblesOutcome.Stale,C.NoblesOutcome.Rejected] else Phase.Unknown
		changed.emit();return
	if not value.has("step"):_finish();return
	var next: Variant=value.step
	if not next is Dictionary or typeof(next.get("token"))!=TYPE_INT or next.token<=0 or typeof(next.get("naming_artifact_id"))!=TYPE_INT or next.naming_artifact_id<0 or typeof(next.get("remaining"))!=TYPE_INT or next.remaining<0 or next.remaining>4096 or next.get("token")==step.get("token"):
		phase=Phase.Unknown;changed.emit();return
	step=next.duplicate(true);phase=Phase.Naming;naming.open();changed.emit()
func _finish() -> void:close();finished.emit()
