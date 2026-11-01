extends RefCounted
# Owned read receipts; edits are never replayed after an uncertain outcome.
signal changed
signal workshop_changed(unit_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var unit_id: int=-1
var ticket:=0
var generation:=0
var rows: Array=[]
var citizen: Dictionary={}
var pending_rows: Array=[]
var list_revision:=0
func configure(source) -> void:
 dispose();service=source
 if is_instance_valid(service):service.session_changed.connect(_invalidated)
func dispose() -> void:
 close()
 if is_instance_valid(service) and service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
 service=null
func close() -> void:
 generation+=1
 if is_instance_valid(service) and ticket!=0:service.detach(ticket)
 ticket=0;unit_id=-1;rows=[];citizen={};pending_rows=[];phase=Phase.Closed
 changed.emit()
func open(id: int) -> void:
 close();unit_id=id
 if id<0:return
 refresh()
func refresh() -> void:
 pending_rows=[];list_revision=0;phase=Phase.Reading
 _page(0);changed.emit()
func _request(data: Dictionary,done: Callable,domain: String="citizens",payload: String="citizen") -> void:
 if not is_instance_valid(service):phase=Phase.Unavailable;changed.emit();return
 var owner:=generation
 ticket=service.submit(domain,data,func(received,result,_sent):
  if owner!=generation or received!=ticket:return
  ticket=0
  if result.get("outcome","")=="unknown" or result.get("status")!=C.ManagementStatus.Ok:
   phase=Phase.Unavailable if result.get("outcome","")=="unknown" else Phase.Rejected;changed.emit();return
  if result.get("action")!=data.action or not result.get(payload) is Dictionary:
   phase=Phase.Rejected;changed.emit();return
  done.call(result[payload]))
 if ticket==0:phase=Phase.Unavailable;changed.emit()
func _page(cursor: int) -> void:
 _request({"action":C.ManagementAction.WorkDetailList,"cursor":cursor,"expected_list_revision":list_revision},func(value):
  if cursor==0:list_revision=int(value.detail_list_revision)
  if int(value.detail_list_revision)!=list_revision or pending_rows.size()+value.details.size()>128:
   phase=Phase.Rejected;changed.emit();return
  pending_rows.append_array(value.details)
  if int(value.next_cursor)>cursor:_page(int(value.next_cursor));return
  if int(value.next_cursor)!=0:phase=Phase.Rejected;changed.emit();return
  _request({"action":C.ManagementAction.CitizenInspect,"unit_id":unit_id},func(info):
   if info.citizens.size()!=1 or int(info.citizens[0].id)!=unit_id or int(info.detail_list_revision)!=list_revision:
    phase=Phase.Rejected;changed.emit();return
   rows=pending_rows;pending_rows=[];citizen=info.citizens[0];phase=Phase.Ready;changed.emit()))
func set_member(index: int,member: bool) -> void:
 if phase!=Phase.Ready or not citizen.get("eligible",false):return
 var found:=rows.find_custom(func(row):return int(row.index)==index)
 if found<0 or not rows[found].get("editable",false):return
 phase=Phase.Applying
 _request({"action":C.ManagementAction.WorkDetailMembership,"unit_id":unit_id,"detail_index":index,"member":1 if member else 0,"expected_revision":rows[found].revision},func(_value):refresh())
 changed.emit()
func set_scope(assigned: bool) -> void:
 if phase!=Phase.Ready or not citizen.get("eligible",false):return
 phase=Phase.Applying
 _request({"action":C.ManagementAction.CitizenWorkScope,"unit_id":unit_id,"only_assigned":1 if assigned else 0,"expected_revision":citizen.revision},func(_value):refresh())
 changed.emit()
func remove_workshop(id: int,revision: int) -> void:
 if phase!=Phase.Ready or id<0 or revision<=0:return
 phase=Phase.Applying
 _request({"action":C.ManagementAction.CreatureWorkshopRemove,"unit_id":unit_id,"building_id":id,"expected_revision":revision},func(value):
  if int(value.get("unit_id",-1))!=unit_id or int(value.get("building_id",-1))!=id or value.get("outcome")!=C.CreatureWorkshopOutcome.Applied:
   phase=Phase.Rejected;changed.emit();return
  workshop_changed.emit(unit_id);refresh(),"creature_workshop","creature_workshop")
 changed.emit()
func _invalidated() -> void:
 var active:=phase!=Phase.Closed
 close()
 if active:phase=Phase.Unavailable;changed.emit()
