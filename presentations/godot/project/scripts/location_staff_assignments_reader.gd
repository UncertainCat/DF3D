extends RefCounted
# One serial pass over the visible rows. Display receipts never authorize edits.
signal changed
const C=preload("res://scripts/management_contract.gd")
const Gesture=preload("res://scripts/location_specialization_workflow.gd")
var details
var service
var owner: Dictionary={}
var rows: Array=[]
var receipts: Array=[]
var cursor:=0
var ticket:=0
var generation:=0

func configure(model) -> void:
	dispose();details=model;service=model.service
	details.changed.connect(_details_changed)
	if service!=null:service.session_changed.connect(clear)

func dispose() -> void:
	clear()
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if service!=null and service.session_changed.is_connected(clear):service.session_changed.disconnect(clear)
	details=null;service=null

func _key() -> Dictionary:
	return {"generation":details.generation,"identity":details.identity.duplicate(true),"revision":details.snapshot.get("revision",0)}

func clear(notify:=true) -> void:
	generation+=1;var previous:=ticket
	ticket=0;owner={};rows=[];receipts=[];cursor=0
	if service!=null and previous!=0:service.detach(previous)
	if notify:changed.emit()

func _details_changed() -> void:
	if owner.is_empty():return
	if details.phase!=details.Phase.Ready or _key()!=owner:clear()

func display(visible_rows: Array) -> void:
	if details==null or service==null or details.phase!=details.Phase.Ready:return
	var selected: Array=[]
	var members: Array=details.snapshot.get("staff",{}).get("rows",[])
	for row in visible_rows:
		if row is Dictionary and row in members and not Gesture.row_target(row).is_empty() and row not in selected:
			selected.append(row.duplicate(true))
	if owner==_key() and rows==selected:return
	clear(false);owner=_key();rows=selected
	receipts.resize(rows.size());receipts.fill({})
	_next()

func receipt(row: Dictionary) -> Dictionary:
	var index:=rows.find(row)
	return receipts[index].duplicate(true) if index>=0 else {}

func _next() -> void:
	if owner.is_empty() or details==null or details.phase!=details.Phase.Ready or _key()!=owner:return
	if cursor>=rows.size():return
	var target:=Gesture.row_target(rows[cursor])
	var intent: Dictionary={"action":C.ManagementAction.AreaInspect,"operation":C.AreaOperation.LocationStaffAssignmentsRead,
		"kind":C.AreaKind.Zone,"location_site_id":owner.identity.site_id,"location_id":owner.identity.id,
		"occupation_id":target.occupation_id,"religious_entity_id":target.entity_id,
		"religious_assignment_id":target.assignment_id,"unit_id":target.unit_id}
	var guard:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if guard==generation and ticket==received:_receive(result,sent,target))
	# A refused submission ends this pass; repeated redraws must not retry it.
	if ticket==0:cursor=rows.size()

func _receive(result: Dictionary,sent: Dictionary,target: Dictionary) -> void:
	ticket=0
	if details==null or details.phase!=details.Phase.Ready or _key()!=owner:clear();return
	var area: Dictionary=result.get("area",{})
	var facts: Dictionary=area.get("location_staff_assignments",{})
	var valid: bool=(result.get("status")==C.ManagementStatus.Ok and result.get("outcome","")!="unknown"
		and result.get("action")==sent.action and area.get("operation")==sent.operation
		and facts.get("site_id")==owner.identity.site_id and facts.get("location_id")==owner.identity.id
		and typeof(facts.get("revision"))==TYPE_INT and facts.revision>0
		and _valid_entries(facts.get("entries")))
	for key in target:
		if facts.get(key)!=target[key]:valid=false
	if valid:receipts[cursor]=facts.duplicate(true)
	cursor+=1
	var guard:=generation
	changed.emit()
	# A subscriber can close or replace Details synchronously.
	if guard==generation:_next()

func _valid_entries(entries) -> bool:
	if not entries is Array:return false
	var previous: int=C.LocationStaffAssignmentKind.Occupation
	for entry in entries:
		if not entry is Dictionary:return false
		for key in ["kind","id","type","subtype","custom"]:
			if typeof(entry.get(key))!=TYPE_INT:return false
		if entry.kind<previous or entry.kind>C.LocationStaffAssignmentKind.WorkDetail or entry.id<0:return false
		if entry.type< -1 or entry.subtype< -1 or entry.custom< -1 or typeof(entry.get("name"))!=TYPE_STRING:return false
		if entry.name.to_utf8_buffer().size()>4096:return false
		if entry.kind not in [C.LocationStaffAssignmentKind.Workshop,C.LocationStaffAssignmentKind.Furnace] and (entry.subtype!= -1 or entry.custom!= -1):return false
		if entry.kind!=C.LocationStaffAssignmentKind.WorkDetail and not entry.name.is_empty():return false
		previous=entry.kind
	return true
