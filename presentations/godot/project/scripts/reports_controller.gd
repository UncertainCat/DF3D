extends Node
# Service owns transport and DF epochs; this owner uses a local session generation.
const Contract=preload("res://scripts/management_contract.gd")
var state=preload("res://scripts/reports_state.gd").new()
var service
var ticket:=0
var metadata_ticket:=0
var metadata_elapsed:=0.0
signal log_changed

func _process(delta:float) -> void:
 poll_metadata(delta)

func poll_metadata(delta:float) -> void:
 if service==null or not state.opened:return
 metadata_elapsed+=maxf(0.0,delta)
 if metadata_elapsed<0.5 or metadata_ticket!=0 or ticket!=0:return
 metadata_elapsed=0.0
 # Retry only the unsatisfied read demand. The pause intent was already emitted
 # for the observed length transition and must not be replayed on read failure.
 if state.retry_read():return
 if state.unit_id<0:return
 if state.log_initial_needed:
  state.retry_initial_log();return
 if state.log_refresh_needed:
  state.refresh_new_reports();return
 var session:int=state.epoch
 var generation:int=state.generation
 var unit:int=state.unit_id
 var category:int=state.unit_category
 metadata_ticket=service.submit("reports",{"action":34,"view":2,"unit_id":unit,"unit_category":category},func(received,result,_sent):
  if received!=metadata_ticket:return
  metadata_ticket=0
  if session!=state.epoch or generation!=state.generation or not state.opened or unit!=state.unit_id or category!=state.unit_category:return
  if int(result.get("status",-1))!=Contract.ManagementStatus.Ok or int(result.get("action",-1))!=34 or result.get("outcome","")=="unknown":return
  var report:Dictionary=result.get("report",{})
  if int(report.get("view",-1))!=2 or int(report.get("unit_category",-1))!=category:return
  for row in report.get("units",[]):
   if int(row.get("unit_id",-1))==unit and int(row.get("category",-1))==category and str(row.get("error","")).is_empty():
    if state.observe_log_length(unit,category,int(row.get("log_count",-1)),session):
     log_changed.emit()
     state.refresh_new_reports()
    return)

func configure(source) -> void:
 shutdown()
 service=source
 service.session_changed.connect(_session_changed)
 state.request_requested.connect(_request)
 state.dismissed.connect(_detach)
 state.request_cancelled.connect(_detach)

func _detach() -> void:
 var previous:=ticket;ticket=0
 if service!=null and previous!=0:service.detach(previous)
 previous=metadata_ticket;metadata_ticket=0;metadata_elapsed=0.0
 if service!=null and previous!=0:service.detach(previous)

func _session_changed() -> void:
 _detach();state.close();state.set_epoch(state.epoch+1)

func shutdown() -> void:
 _detach();state.close()
 if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
 if state.request_requested.is_connected(_request):state.request_requested.disconnect(_request)
 if state.dismissed.is_connected(_detach):state.dismissed.disconnect(_detach)
 if state.request_cancelled.is_connected(_detach):state.request_cancelled.disconnect(_detach)
 service=null

func _exit_tree() -> void:shutdown()

func _request(data: Dictionary,token: int) -> void:
 _detach()
 if service==null:state.reject(token);return
 var session:int=state.epoch
 ticket=service.submit("reports",data,func(received,result,sent):
  if received!=ticket or session!=state.epoch or token!=state.generation:return
  ticket=0
  if int(result.get("status",-1))!=Contract.ManagementStatus.Ok or int(result.get("action",-1))!=int(sent.action) or result.get("outcome","")=="unknown":
   state.reject(token);return
  if not state.accept(token,session,result.get("report",{})):state.reject(token))
 if ticket==0:state.reject(token)
