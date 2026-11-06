extends RefCounted
# Shared job-backed Details state. Native owns choices, filtering and ordering.
# Edits are not routed until their native effects have been accepted.
signal changed
signal choice_requested(intent: Dictionary)
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Rejected, Unavailable }
var service
var phase:=Phase.Closed
var building_id:=-1
var job_id:=-1
var unit_id:=-1
var ticket:=0
var generation:=0
var snapshot: Dictionary={}
var rows: Array=[]
var query:=""
var first:=0
var visible_rows:=16
var selected:=-1
var pending: Array=[]
var receipt: Dictionary={}

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(close)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(close):service.session_changed.disconnect(close)
	service=null
func retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	retire();building_id=-1;job_id=-1;unit_id=-1;snapshot={};rows=[];pending=[];receipt={};query="";first=0;selected=-1;phase=Phase.Closed;changed.emit()
func open(building: int,job: int,unit: int=-1) -> void:
	close()
	if building<0 or job<0 or unit < -1:return
	building_id=building;job_id=job;unit_id=unit;read_root()
func has_art() -> bool:return false
func row_base() -> int:return 0
func read_root() -> void:
	if job_id<0:return
	selected=-1;query="";_restart()
func select_option(index: int) -> void:
	if phase!=Phase.Ready or index<0 or index>=snapshot.get("options",[]).size():return
	selected=index;query="";_restart()
func set_query(value: String) -> void:
	if phase not in [Phase.Reading,Phase.Ready] or selected<0 or value==query or value.to_utf8_buffer().size()>128:return
	query=value;_restart()
func _restart() -> void:
	retire();rows=[];pending=[];receipt={};first=0;phase=Phase.Reading;_read(0)
func _fail(value: Phase) -> void:
	phase=value;rows=[];pending=[];receipt={};snapshot={};changed.emit()
func _read(cursor: int) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsRead,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"option":selected,"query":query,"cursor":cursor}
	ticket=service.submit("job_settings",intent,func(received,result,_sent):
		if generation!=owner or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("job_settings",{})
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.JobSettingsRead or value.get("job_id")!=job_id or value.get("building_id")!=building_id or value.get("unit_id")!=unit_id:
			_fail(Phase.Rejected);return
		if value.get("revision",0)<=0 or not value.get("options") is Array or not value.get("choices") is Array or value.get("cursor",-1)!=cursor or cursor!=pending.size():
			_fail(Phase.Rejected);return
		var option: int=value.get("selected_option",-2)
		if option < -1 or option>=value.options.size() or (selected>=0 and option!=selected) or (option>=0 and value.get("choices_revision",0)<=0):
			_fail(Phase.Rejected);return
		if cursor>0 and (value.revision!=receipt.revision or value.choices_revision!=receipt.choices_revision or value.total!=receipt.total or option!=receipt.selected_option):
			_fail(Phase.Rejected);return
		pending.append_array(value.choices.duplicate(true));receipt=value.duplicate(true);selected=option
		var next: int=value.get("next_cursor",0)
		if next>0:
			if next!=pending.size() or value.choices.is_empty() or next>=int(value.get("total",-1)):_fail(Phase.Rejected);return
			_read(next);return
		if pending.size()!=int(value.get("total",-1)):_fail(Phase.Rejected);return
		snapshot=receipt;receipt={};rows=pending;pending=[];phase=Phase.Ready;changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func seek(value: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-1));changed.emit()
func fit_visible_rows(count: int) -> void:visible_rows=maxi(1,count)
func choose(id: int) -> void:
	if phase!=Phase.Ready or selected<0:return
	for row: Dictionary in rows:
		if row.id==id:
			choice_requested.emit({"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"expected_revision":snapshot.revision,"option":selected,"expected_choices_revision":snapshot.choices_revision,"choice":id})
			return
