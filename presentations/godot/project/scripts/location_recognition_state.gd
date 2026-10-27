extends RefCounted
# Recognition owns a separate native revision; no optimistic effects or replay.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var phase:=Phase.Closed
var service
var identity: Dictionary={}
var snapshot: Dictionary={}
var ticket:=0
var generation:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	generation+=1
	var previous:=ticket
	ticket=0;identity={};snapshot={};phase=Phase.Closed
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(target: Dictionary) -> void:
	close()
	for key in ["site_id","id"]:
		if typeof(target.get(key))!=TYPE_INT or target[key]<0 or target[key]>2147483647:
			_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	identity={"site_id":target.site_id,"id":target.id};phase=Phase.Reading
	_send(_intent(false))

func refresh() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	phase=Phase.Reading;_send(_intent(false))

func recognize() -> void:
	if phase!=Phase.Ready or ticket!=0 or int(snapshot.get("state",-1)) not in [C.LocationRecognitionState.RecognizePriesthood,C.LocationRecognitionState.RecognizeHighPriest]:return
	var intent:=_intent(true);intent.expected_revision=snapshot.revision
	phase=Phase.Applying;_send(intent)

func _intent(apply: bool) -> Dictionary:
	return {"action":C.ManagementAction.AreaUpdate if apply else C.ManagementAction.AreaInspect,
		"operation":C.AreaOperation.LocationRecognize if apply else C.AreaOperation.LocationRecognitionRead,
		"kind":C.AreaKind.Zone,"location_site_id":identity.site_id,"location_id":identity.id}

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var area: Dictionary=result.get("area",{})
	var apply: bool=sent.operation==C.AreaOperation.LocationRecognize
	var outcome:=int(area.get("location_edit_outcome",C.LocationEditOutcome.None))
	if result.get("outcome","")=="unknown" or outcome==C.LocationEditOutcome.Unknown:
		_fail(Phase.Unknown);return
	if int(result.get("status",C.ManagementStatus.Rejected))!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if apply and outcome==C.LocationEditOutcome.Stale else Phase.Rejected);return
	var observed: Dictionary=area.get("location_recognition",{})
	if (int(result.get("action",-1))!=sent.action or int(area.get("operation",-1))!=sent.operation
		or int(observed.get("site_id",-1))!=identity.site_id or int(observed.get("location_id",-1))!=identity.id
		or typeof(observed.get("revision"))!=TYPE_INT or observed.revision<=0
		or typeof(observed.get("state"))!=TYPE_INT or observed.state<0 or observed.state>5
		or (apply and outcome!=C.LocationEditOutcome.Completed)):
		_fail(Phase.Unknown if apply else Phase.Rejected);return
	snapshot=observed.duplicate(true);phase=Phase.Ready
	changed.emit()
	if apply:applied.emit()
