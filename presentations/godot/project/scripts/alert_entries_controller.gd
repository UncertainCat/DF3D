extends Node
# Native popup102152 retains open unit-log text/rows until Back and reopen.
# No Reports-style metadata polling; see alert_entries.json.unit_log_open_lifetime.
const Contract=preload("res://scripts/management_contract.gd")
var state=preload("res://scripts/alert_entries_state.gd").new()
var service
var ticket:=0
var retry_elapsed:=0.0
func _process(delta:float) -> void:poll_recovery(delta)
func poll_recovery(delta:float) -> void:
 if service==null or not state.opened or ticket!=0 or not state.read_retry_needed:return
 retry_elapsed+=maxf(0.0,delta)
 if retry_elapsed<0.5:return
 retry_elapsed=0.0;state.retry_read()
func configure(source) -> void:
 service=source
 service.session_changed.connect(_session_changed)
 state.request_requested.connect(_request)
 state.request_cancelled.connect(_detach)
func _detach() -> void:
 retry_elapsed=0.0
 var previous:=ticket;ticket=0
 if service!=null and previous!=0:service.detach(previous)
func _session_changed() -> void:
 state.set_epoch(state.epoch+1)
func _request(data:Dictionary,token:int) -> void:
 _detach()
 if service==null:state.reject(token);return
 var session:int=state.epoch
 ticket=service.submit("reports",data,func(received,result,_sent):
  if received!=ticket or session!=state.epoch or token!=state.generation:return
  ticket=0
  if int(result.get("status",-1))!=Contract.ManagementStatus.Ok or int(result.get("action",-1))!=int(_sent.action) or result.get("outcome","")=="unknown":state.reject(token);return
  if not state.accept(token,session,result.get("report",{})):state.reject(token))
 if ticket==0:state.reject(token)
func shutdown() -> void:
 state.close()
 if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
 if state.request_requested.is_connected(_request):state.request_requested.disconnect(_request)
 if state.request_cancelled.is_connected(_detach):state.request_cancelled.disconnect(_detach)
 service=null
func _exit_tree() -> void:shutdown()
