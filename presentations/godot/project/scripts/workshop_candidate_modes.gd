extends RefCounted
# Visible candidate receipts use the existing native CitizenInspect/WorkScope path.
# A sent edit outlives this observer; retirement never replays it.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
var service
var ids: Array=[]
var receipts: Dictionary={}
var cursor:=0
var ticket:=0
var generation:=0
var applying:=false
func configure(source) -> void:
 service=source;service.session_changed.connect(clear)
func dispose() -> void:
 clear()
 if service!=null and service.session_changed.is_connected(clear):service.session_changed.disconnect(clear)
 service=null
func clear() -> void:
 generation+=1
 if ticket!=0 and service!=null:service.detach(ticket)
 ticket=0;ids=[];receipts={};cursor=0;applying=false;changed.emit()
func display(rows: Array) -> void:
 var next: Array=[]
 for row in rows:next.append(int(row.unit_id))
 if next==ids or applying:return
 clear();ids=next;_next()
func _next() -> void:
 if cursor>=ids.size() or service==null:return
 _send({"action":C.ManagementAction.CitizenInspect,"unit_id":ids[cursor]},false)
func _send(intent: Dictionary,editing: bool) -> void:
 var guard:=generation
 ticket=service.submit("citizens",intent,func(received,result,_sent):
  if guard!=generation or received!=ticket:return
  ticket=0
  var valid: bool=result.get("status")==C.ManagementStatus.Ok and result.get("outcome","")!="unknown" and result.get("action")==intent.action
  if editing:
   applying=false;receipts.erase(intent.unit_id)
   # No automatic replay after rejection or unknown completion.
   if valid:applied.emit()
   changed.emit();return
  var citizens: Array=result.get("citizen",{}).get("citizens",[])
  if valid and citizens.size()==1 and citizens[0].get("id",-1)==intent.unit_id and citizens[0].get("revision",0)>0:
   receipts[intent.unit_id]=citizens[0].duplicate(true)
  cursor+=1;changed.emit()
  if guard==generation:_next())
 if ticket==0:applying=false;cursor=ids.size();changed.emit()
func toggle(id: int) -> void:
 if applying or not receipts.has(id):return
 var value: Dictionary=receipts[id]
 if not value.get("eligible",false):return
 # Retire any pending display read; the edit has its own receipt and generation.
 generation+=1
 if ticket!=0:service.detach(ticket)
 ticket=0;applying=true;changed.emit()
 _send({"action":C.ManagementAction.CitizenWorkScope,"unit_id":id,"only_assigned":0 if value.only_assigned_jobs else 1,"expected_revision":value.revision},true)
