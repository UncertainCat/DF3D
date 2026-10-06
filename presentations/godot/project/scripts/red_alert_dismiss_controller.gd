extends Node
# One explicit right-click intent. Never retry a mutation or hide the source locally.
const Contract=preload("res://scripts/management_contract.gd")
signal finished(result:Dictionary)
var world
var service
var ticket:=0
var generation:=0
var last_result:Dictionary={}
func configure(source,actions) -> void:
 world=source;service=actions
 service.session_changed.connect(cancel)
func current(epoch:int,producer:int) -> bool:
 if world==null or not world.is_live() or int(world.session_generation())!=producer:return false
 var session:Dictionary=world.poll_session()
 return bool(session.get("fortress_valid",false)) and int(session.get("fortress_epoch",0))==epoch
func dismiss(epoch:int) -> bool:
 if ticket!=0 or service==null or epoch<=0:return false
 var producer:int=world.session_generation()
 if not current(epoch,producer):return false
 if int(world.poll_session().get("alert_button_report_count",0))<=0:return false
 generation+=1;var token:=generation
 last_result={}
 ticket=service.submit("reports",{"action":Contract.ManagementAction.PrepareAlertDismissal},func(received,result,sent):
  if token!=generation or received!=ticket:return
  ticket=0
  if not accepted(result,sent) or not current(epoch,producer):complete(result);return
  var report:Dictionary=result.get("report",{})
  var receipt=report.get("list_revision",0)
  if typeof(receipt)!=TYPE_INT or receipt<=0 or int(report.get("total",0))<=0:complete(result);return
  ticket=service.submit("reports",{"action":Contract.ManagementAction.DismissAlert,"expected_list_revision":receipt},func(done,outcome,_request):
   if token!=generation or done!=ticket:return
   ticket=0;complete(outcome))
  if ticket==0:complete({}))
 return ticket!=0
func accepted(result:Dictionary,sent:Dictionary) -> bool:
 return int(result.get("status",-1))==Contract.ManagementStatus.Ok and int(result.get("action",-1))==int(sent.action) and result.get("outcome","")!="unknown"
func complete(result:Dictionary) -> void:
 last_result=result.duplicate(true);finished.emit(last_result)
func cancel() -> void:
 generation+=1
 var previous:=ticket;ticket=0
 if service!=null and previous!=0:service.detach(previous)
func _exit_tree() -> void:
 cancel()
 if service!=null and service.session_changed.is_connected(cancel):service.session_changed.disconnect(cancel)
