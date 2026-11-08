extends RefCounted
# Staged category owner. Values, visibility and editability come from DF.
signal changed
const C=preload("res://scripts/management_contract.gd")
const COUNTS={0:11,1:6,2:10,3:10,4:6,6:7}
func max_value(id: int) -> int:return 2 if category in [3,4] or (category==0 and id==0) else 3 if category==6 and id==0 else 1
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var category:=0
var settings: Array=[]
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
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	settings=[];last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();category=0;phase=Phase.Reading
	_submit({"action":C.ManagementAction.StandingOrdersRead,"category":category})
func select_category(value: int) -> void:
	if not COUNTS.has(value) or value==category or phase in [Phase.Closed,Phase.Applying,Phase.Unavailable]:return
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	settings=[];last_result={};category=value;phase=Phase.Reading
	_submit({"action":C.ManagementAction.StandingOrdersRead,"category":category})
func set_value(id: int,value: int) -> void:
	if phase!=Phase.Ready or id<0 or id>=settings.size():return
	var row: Dictionary=settings[id]
	if not row.editable or value<0 or value>max_value(id) or value==int(row.value):return
	phase=Phase.Applying
	_submit({"action":C.ManagementAction.StandingOrdersSet,"category":category,"setting_id":id,"expected_value":int(row.value),"value":value})
func _reject(result: Dictionary) -> void:
	settings=[];last_result=result.duplicate(true)
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or result.get("standing_orders",{}).get("outcome",-1)==C.StandingOrdersOutcome.Unknown else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:settings=[];phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("standing_orders",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var snapshot: Dictionary=result.get("standing_orders",{})
		var expected:=C.StandingOrdersOutcome.Applied if intent.action==C.ManagementAction.StandingOrdersSet else C.StandingOrdersOutcome.None
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action or snapshot.get("category",-1)!=category or snapshot.get("outcome",-1)!=expected:
			_reject(result);return
		var rows: Array=snapshot.get("settings",[])
		if rows.size()!=COUNTS[category]:_reject(result);return
		for id in rows.size():
			var row: Dictionary=rows[id]
			if row.get("id",-1)!=id or typeof(row.get("value"))!=TYPE_INT or row.value<0 or row.value>max_value(id) or typeof(row.get("visible"))!=TYPE_BOOL or typeof(row.get("editable"))!=TYPE_BOOL or (row.editable and not row.visible) or (category==0 and (row.visible!=row.editable or (id<6 and not row.visible))) or (category not in [0,2] and (not row.visible or not row.editable)):
				_reject(result);return
		settings=rows.duplicate(true);last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:settings=[];phase=Phase.Unavailable
	changed.emit()
