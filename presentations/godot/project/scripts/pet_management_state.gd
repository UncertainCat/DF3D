extends RefCounted
# Pane ownership only. DF supplies trainer order/skills, training knowledge and
# edit eligibility; every candidate page carries the animal's observed revision.
signal changed
signal applied
signal dismissed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unavailable, Unknown }
enum Pane { Trainers, Knowledge }
var service
var phase:=Phase.Closed
var pane:=Pane.Trainers
var generation:=0
var ticket:=0
var animal_id:=-1
var revision:=0
var snapshot: Dictionary={}
var ids:=PackedInt32Array()
var rows: Dictionary={}
var total:=-1
var first:=0
var capacity:=12
var columns:=30

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	retire();animal_id=-1;revision=0;snapshot={};ids=PackedInt32Array();rows={};total=-1;first=0;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open_trainers(row: Dictionary) -> void:
	if phase==Phase.Applying:return
	close()
	var pet: Dictionary=row.get("pet",{})
	if int(row.get("kind",0))!=0 or int(row.get("id",-1))<0 or int(pet.get("revision",0))<=0:return
	if not pet.get("controls",[]).any(func(control):return int(control.action)==C.PetAction.Trainer):return
	pane=Pane.Trainers;animal_id=int(row.id);revision=int(pet.revision);_start()
func open_knowledge() -> void:
	if phase==Phase.Applying:return
	close();pane=Pane.Knowledge;_start()
func _start() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading;_fill();changed.emit()
func seek(offset: int,count: int) -> void:
	capacity=clampi(count,1,64)
	first=clampi(offset,0,maxi(0,total-capacity)) if total>=0 else 0
	_fill();changed.emit()
func row_at(index: int) -> Dictionary:
	if index<0 or index>=total:return {}
	if pane==Pane.Trainers:
		# The first three native choices precede the complete unit candidate order.
		if index<3:return {"mode":[C.PetTrainerMode.Any,C.PetTrainerMode.Unassigned,C.PetTrainerMode.None][index]}
		return rows.get(ids[index-3],{})
	return rows.get(index,{})
func set_columns(value: int) -> void:
	value=clampi(value,3,30)
	if value==columns or phase in [Phase.Applying,Phase.Unknown]:return
	columns=value
	if pane==Pane.Trainers and phase in [Phase.Reading,Phase.Ready]:
		retire();rows={};phase=Phase.Reading;_fill();changed.emit()
func _reject(unknown:=false) -> void:
	rows={};phase=Phase.Unknown if unknown else Phase.Rejected;changed.emit()
func _fill() -> void:
	if phase not in [Phase.Reading,Phase.Ready] or ticket!=0 or service==null:return
	if pane==Pane.Trainers:_fill_trainers()
	else:_fill_knowledge()
func _fill_trainers() -> void:
	var wanted:=PackedInt32Array()
	if total>=0:
		for index in range(maxi(3,first),mini(total,first+capacity)):
			if not rows.has(ids[index-3]):wanted.append(ids[index-3])
		if wanted.is_empty():phase=Phase.Ready;return
	var owner:=generation;var observed_revision:=revision;var target:=animal_id
	phase=Phase.Reading
	ticket=service.submit("pet_trainers",{"action":C.ManagementAction.PetTrainersRead,"animal_id":target,"expected_revision":observed_revision,"unit_ids":wanted,"columns":columns},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("pet_trainers",{})
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.PetTrainersRead or value.get("animal_id",-1)!=target or value.get("revision",0)!=observed_revision:
			_reject();return
		var order: PackedInt32Array=value.get("unit_ids",PackedInt32Array())
		var page: Array=value.get("rows",[])
		if page.size()!=wanted.size():_reject();return
		for index in page.size():
			if int(page[index].get("id",-1))!=wanted[index]:_reject();return
		if order!=ids:rows={}
		ids=order.duplicate();total=ids.size()+3;snapshot=value.duplicate(true);snapshot.erase("rows")
		first=clampi(first,0,maxi(0,total-capacity))
		var kept: Dictionary={}
		for index in range(maxi(3,first),mini(total,first+capacity)):
			if rows.has(ids[index-3]):kept[ids[index-3]]=rows[ids[index-3]]
		for row: Dictionary in page:
			if ids.has(int(row.id)):kept[int(row.id)]=row.duplicate(true)
		rows=kept;_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func _fill_knowledge() -> void:
	var offset:=first
	if total>=0:
		while offset<mini(total,first+capacity) and rows.has(offset):offset+=1
		if offset>=mini(total,first+capacity):phase=Phase.Ready;return
	var limit:=capacity if total<0 else mini(64,first+capacity-offset)
	var owner:=generation;var observed_revision:=revision;phase=Phase.Reading
	ticket=service.submit("pet_knowledge",{"action":C.ManagementAction.PetKnowledgeRead,"expected_revision":observed_revision,"offset":offset,"limit":limit},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("pet_knowledge",{})
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.PetKnowledgeRead or value.get("offset",-1)!=offset or int(value.get("revision",0))<=0 or (observed_revision!=0 and value.revision!=observed_revision):
			_reject();return
		var page: Array=value.get("rows",[]);var count:=int(value.get("total",-1))
		if count<offset or page.size()!=mini(limit,count-offset):_reject();return
		revision=int(value.revision);total=count;first=clampi(first,0,maxi(0,total-capacity))
		snapshot=value.duplicate(true);snapshot.erase("rows")
		var kept: Dictionary={}
		for index in range(first,mini(total,first+capacity)):
			if rows.has(index):kept[index]=rows[index]
		for index in page.size():kept[offset+index]=page[index].duplicate(true)
		rows=kept;_fill();changed.emit())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func select_trainer(mode: int,trainer_id: int=-1) -> void:
	if pane!=Pane.Trainers or phase!=Phase.Ready or ticket!=0 or service==null or revision<=0:return
	if mode<0 or mode>3 or (mode==C.PetTrainerMode.Individual and (not ids.has(trainer_id) or not rows.has(trainer_id))) or (mode!=C.PetTrainerMode.Individual and trainer_id!=-1):return
	var owner:=generation;var target:=animal_id;phase=Phase.Applying
	ticket=service.submit("pet_trainer",{"action":C.ManagementAction.PetTrainerApply,"animal_id":target,"expected_revision":revision,"mode":mode,"trainer_id":trainer_id},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("pet_edit",{})
		var uncertain: bool=result.get("outcome","")=="unknown" or value.get("outcome",-1)==C.PetOutcome.Unknown
		if uncertain:_reject(true);return
		# A native revision-checked no-op is rejected by the edit provider. The
		# already-observed choice can still dismiss the local picker; it is not
		# reported as an applied mutation and never retried.
		if result.get("status",-1)==C.ManagementStatus.Rejected and result.get("action",-1)==C.ManagementAction.PetTrainerApply and value.get("target",{})=={"kind":0,"id":target} and value.get("outcome",-1)==C.PetOutcome.Rejected and _same_assignment(mode,trainer_id):
			close();dismissed.emit();return
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.PetTrainerApply or value.get("target",{})!={"kind":0,"id":target} or value.get("outcome",-1)!=C.PetOutcome.Applied:
			_reject();return
		close();applied.emit())
	if ticket==0:_reject()
	else:changed.emit()
func _same_assignment(mode: int,trainer_id: int) -> bool:
	if mode==C.PetTrainerMode.None:return not snapshot.get("assigned",false)
	return snapshot.get("assigned",false) and snapshot.get("trainer_id",-1)==trainer_id and snapshot.get("any_trainer",false)==(mode==C.PetTrainerMode.Any) and snapshot.get("unassigned_only",false)==(mode==C.PetTrainerMode.Unassigned)
