extends RefCounted
# Read-only global observations. Session loss requires the HUD to activate again.
signal changed
const C=preload("res://scripts/management_contract.gd")
const REFRESH_SECONDS:=1.0
var service
var active:=false
var ready:=false
var ticket:=0
var generation:=0
var elapsed:=0.0
var _rows: Array=[]

func configure(source) -> void:
	dispose();service=source
	service.session_changed.connect(clear)

func dispose() -> void:
	clear()
	if service!=null and service.session_changed.is_connected(clear):service.session_changed.disconnect(clear)
	service=null

func clear() -> void:
	generation+=1;var old:=ticket
	ticket=0;active=false;ready=false;elapsed=0.0;_rows=[]
	if service!=null and old!=0:service.detach(old)
	changed.emit()

func set_active(value: bool) -> void:
	if value==active:return
	if not value:clear();return
	active=true;refresh()

func snapshot() -> Array:
	return _rows.duplicate(true)

func poll(delta: float) -> void:
	if not active:return
	elapsed+=maxf(0.0,delta)
	if ticket==0 and elapsed>=REFRESH_SECONDS:refresh()

func refresh() -> void:
	if not active or service==null or ticket!=0:return
	elapsed=0.0;var guard:=generation
	ticket=service.submit("agreements",{"action":C.ManagementAction.AgreementList,"tracker":true},func(received,result,_sent):
		if guard==generation and ticket==received:_receive(result))
	if ticket==0:
		ready=false;_rows=[];changed.emit()

func _receive(result: Dictionary) -> void:
	ticket=0
	var facts: Dictionary=result.get("agreement",{})
	ready=(result.get("status")==C.ManagementStatus.Ok and result.get("outcome","")!="unknown"
		and result.get("action")==C.ManagementAction.AgreementList and facts.get("tracker",false)==true
		and facts.get("tracker_rows") is Array)
	_rows=facts.tracker_rows.duplicate(true) if ready else []
	changed.emit()
