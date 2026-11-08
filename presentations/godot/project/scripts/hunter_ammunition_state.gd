extends RefCounted
# Staged owner of native ammunition snapshots and local picker/entry state.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
enum Mode { Main, Types, Materials, Amount }
var service
var phase:=Phase.Closed
var mode:=Mode.Main
var specs: Array=[]
var rules: Array=[]
var types: Array=[]
var materials: Array=[]
var selected:=-1
var first:=0
var choice_first:=0
var amount_text:=""
var resume_amount:=false
var ticket:=0
var generation:=0
var last_result: Dictionary={}
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func _clear() -> void:
	specs=[];rules=[];types=[];materials=[];selected=-1;amount_text="";resume_amount=false;mode=Mode.Main
func close() -> void:
	_retire();_clear();first=0;choice_first=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();_read()
func _read() -> void:
	phase=Phase.Reading
	_submit({"action":C.ManagementAction.HunterAmmunitionRead})
func back() -> void:
	if phase==Phase.Applying:return
	if mode in [Mode.Types,Mode.Materials] and phase in [Phase.Ready,Phase.Reading]:
		_retire();materials=[];mode=Mode.Amount if resume_amount else Mode.Main
		if not resume_amount:selected=-1
		resume_amount=false;choice_first=0;phase=Phase.Ready;changed.emit()
	else:close()
func begin_add() -> void:
	if phase!=Phase.Ready or mode not in [Mode.Main,Mode.Amount]:return
	resume_amount=mode==Mode.Amount;mode=Mode.Types;choice_first=0;changed.emit()
func begin_material(index: int) -> void:
	if phase!=Phase.Ready or mode not in [Mode.Main,Mode.Amount] or index<0 or index>=specs.size():return
	resume_amount=false;selected=index;mode=Mode.Materials;choice_first=0;materials=[];phase=Phase.Reading
	_submit({"action":C.ManagementAction.HunterAmmunitionCandidates,"item_type":specs[index].item_type,"item_subtype":specs[index].item_subtype})
func begin_amount(index: int) -> void:
	if phase!=Phase.Ready or mode not in [Mode.Main,Mode.Amount] or index<0 or index>=specs.size():return
	if mode==Mode.Amount and selected==index:mode=Mode.Main;selected=-1
	else:mode=Mode.Amount;selected=index
	amount_text="";changed.emit()
func set_amount_text(value: String) -> void:
	if phase!=Phase.Ready or mode!=Mode.Amount:return
	var digits:=""
	for character in value:
		if character>="0" and character<="9" and digits.length()<18:digits+=character
	amount_text=digits;changed.emit()
func commit_amount() -> void:
	if phase!=Phase.Ready or mode!=Mode.Amount:return
	_apply(C.HunterAmmunitionOperation.Amount,{"index":selected,"amount":clampi(amount_text.to_int(),0,5000)})
func choose(index: int) -> void:
	if phase!=Phase.Ready or index<0:return
	if mode==Mode.Types and index<types.size():
		_apply(C.HunterAmmunitionOperation.Add,{"item_type":types[index].item_type,"item_subtype":types[index].item_subtype})
	elif mode==Mode.Materials and index<materials.size():
		var row: Dictionary=materials[index]
		_apply(C.HunterAmmunitionOperation.Material,{"index":selected,"material_class":row.material_class,"mattype":row.mattype,"matindex":row.matindex})
func delete_rule(index: int) -> void:
	if phase==Phase.Ready and mode==Mode.Main and index>=0 and index<specs.size():_apply(C.HunterAmmunitionOperation.Delete,{"index":index})
func remove_stack(index: int,id: int) -> void:
	if phase==Phase.Ready and mode==Mode.Main and index>=0 and index<specs.size() and id in specs[index].assigned:
		_apply(C.HunterAmmunitionOperation.Remove,{"index":index,"item_id":id})
func _apply(operation: int,fields: Dictionary) -> void:
	var intent: Dictionary={"action":C.ManagementAction.HunterAmmunitionApply,"operation":operation,"index":-1,"item_id":-1,"amount":-1,"item_type":-1,"item_subtype":-1,"material_class":-1,"mattype":-1,"matindex":-1,"expected":specs.duplicate(true)}
	intent.merge(fields,true);phase=Phase.Applying;_submit(intent)
func _fail(result: Dictionary,uncertain: bool=false) -> void:
	_clear();last_result=result.duplicate(true)
	phase=Phase.Unknown if uncertain or result.get("outcome","")=="unknown" or result.get("hunter_ammunition",{}).get("outcome",-1)==C.HunterAmmunitionOutcome.Unknown else Phase.Rejected
	changed.emit()
func _valid_specs(rows: Array) -> bool:
	for value in rows:
		if not value is Dictionary:return false
		for key in ["item_type","item_subtype","material_class","mattype","matindex","amount","flags"]:
			if typeof(value.get(key))!=TYPE_INT:return false
		if value.item_type!=39 or value.item_subtype<0 or value.amount<0 or value.flags<0 or value.flags>3 or typeof(value.get("assigned"))!=TYPE_PACKED_INT32_ARRAY:return false
		if value.material_class<-1 or value.mattype<-1 or value.matindex<-1:return false
		var previous:=-1
		for id in value.assigned:
			if id<=previous:return false
			previous=id
	return true
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("hunter_ammunition",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var snapshot: Dictionary=result.get("hunter_ammunition",{})
		var apply: bool=intent.action==C.ManagementAction.HunterAmmunitionApply
		var expected:=C.HunterAmmunitionOutcome.Applied if apply else C.HunterAmmunitionOutcome.None
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action or snapshot.get("outcome",-1)!=expected:
			_fail(result,apply and result.get("status",-1)==C.ManagementStatus.Ok);return
		if intent.action==C.ManagementAction.HunterAmmunitionCandidates:
			if mode!=Mode.Materials or snapshot.get("item_type",-1)!=intent.item_type or snapshot.get("item_subtype",-1)!=intent.item_subtype or not snapshot.get("materials") is Array:_fail(result);return
			for row in snapshot.materials:
				if not row is Dictionary or typeof(row.get("caption"))!=TYPE_STRING:_fail(result);return
				for key in ["material_class","mattype","matindex"]:
					if typeof(row.get(key))!=TYPE_INT or row[key]<-1:_fail(result);return
			materials=snapshot.materials.duplicate(true);phase=Phase.Ready;changed.emit();return
		if not snapshot.get("specs") is Array or not _valid_specs(snapshot.specs):_fail(result,apply);return
		if apply:
			specs=snapshot.specs.duplicate(true);rules=[];materials=[];selected=-1;amount_text="";mode=Mode.Main;_read();return
		if not snapshot.get("rules") is Array or snapshot.rules.size()!=snapshot.specs.size() or not snapshot.get("types") is Array:_fail(result);return
		for index in snapshot.rules.size():
			if not snapshot.rules[index] is Dictionary:_fail(result);return
			var row: Dictionary=snapshot.rules[index]
			if typeof(row.get("caption"))!=TYPE_STRING or typeof(row.get("quantity"))!=TYPE_INT or not row.get("items") is Array:_fail(result);return
			var quantity:=0;var previous:=-1
			for item in row.items:
				if not item is Dictionary or typeof(item.get("id"))!=TYPE_INT or item.id<=previous or item.id not in snapshot.specs[index].assigned or typeof(item.get("caption"))!=TYPE_STRING or typeof(item.get("quantity"))!=TYPE_INT or item.quantity<0:_fail(result);return
				previous=item.id;quantity+=item.quantity
			if quantity!=row.quantity:_fail(result);return
		for row in snapshot.types:
			if not row is Dictionary or row.get("item_type",-1)!=39 or typeof(row.get("item_subtype"))!=TYPE_INT or row.item_subtype<0 or typeof(row.get("foreign"))!=TYPE_BOOL or typeof(row.get("caption"))!=TYPE_STRING:_fail(result);return
		specs=snapshot.specs.duplicate(true);rules=snapshot.rules.duplicate(true);types=snapshot.types.duplicate(true)
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
