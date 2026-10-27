extends RefCounted
# A displayed tracker row owns the observation. It never grants edit authority.
signal changed
const C=preload("res://scripts/management_contract.gd")
const REFRESH_SECONDS:=1.0
var source
var service
var target: Dictionary={}
var ready:=false
var ticket:=0
var generation:=0
var elapsed:=0.0
var _snapshot: Dictionary={}

func configure(list_reader) -> void:
	dispose();source=list_reader;service=source.service
	source.changed.connect(_source_changed)

func dispose() -> void:
	clear()
	if source!=null and source.changed.is_connected(_source_changed):source.changed.disconnect(_source_changed)
	source=null;service=null

func clear(notify:=true) -> void:
	generation+=1;var old:=ticket
	ticket=0;target={};ready=false;elapsed=0.0;_snapshot={}
	if service!=null and old!=0:service.detach(old)
	if notify:changed.emit()

func _member(row: Dictionary) -> bool:
	return source!=null and source.active and source.ready and not row.is_empty() and row in source.snapshot()

func _source_changed() -> void:
	if not target.is_empty() and not _member(target):clear()

func display(row: Dictionary) -> void:
	if not _member(row):
		if not target.is_empty():clear()
		return
	if target==row:return
	clear(false);target=row.duplicate(true);refresh();changed.emit()

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func poll(delta: float) -> void:
	if target.is_empty():return
	if not _member(target):clear();return
	elapsed+=maxf(0.0,delta)
	if ticket==0 and elapsed>=REFRESH_SECONDS:refresh()

func refresh() -> void:
	if target.is_empty() or service==null or ticket!=0:return
	if not _member(target):clear();return
	elapsed=0.0;var guard:=generation
	ticket=service.submit("agreements",{"action":C.ManagementAction.AgreementInspect,"tracker":true,"id":target.agreement_id},func(received,result,_sent):
		if guard==generation and ticket==received:_receive(result))
	if ticket==0:ready=false;_snapshot={};changed.emit()

func _receive(result: Dictionary) -> void:
	ticket=0
	if not _member(target):clear();return
	var facts: Dictionary=result.get("agreement",{})
	var rows=facts.get("tracker_rows")
	ready=(result.get("status")==C.ManagementStatus.Ok and result.get("outcome","")!="unknown"
		and result.get("action")==C.ManagementAction.AgreementInspect and facts.get("tracker",false)==true
		and rows is Array and rows.size()==1 and rows[0]==target and facts.get("tracker_details") is Dictionary)
	_snapshot={"row":rows[0].duplicate(true),"details":facts.tracker_details.duplicate(true)} if ready else {}
	changed.emit()
