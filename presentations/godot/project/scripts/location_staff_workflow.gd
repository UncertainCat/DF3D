extends RefCounted
# Owns the local selector. Details owns any submitted mutation through its service.
signal changed
signal applied
const Details = preload("res://scripts/location_details_state.gd")
const Candidates = preload("res://scripts/location_staff_candidates_state.gd")
enum Mode { Closed, Choosing, Removing, Editing }
var mode := Mode.Closed
var details
var candidates = Candidates.new()
var target: Dictionary = {}
var details_revision := 0

func configure(model) -> void:
	dispose()
	details=model
	if details.service!=null:candidates.configure(details.service)
	details.changed.connect(_details_changed)
	candidates.changed.connect(_candidates_changed)

func dispose() -> void:
	close()
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if candidates.changed.is_connected(_candidates_changed):candidates.changed.disconnect(_candidates_changed)
	if candidates.service!=null and candidates.service.session_changed.is_connected(candidates._session_changed):
		candidates.service.session_changed.disconnect(candidates._session_changed)
	details=null

func close() -> void:
	mode=Mode.Closed;target={};details_revision=0
	candidates.close()
	changed.emit()

func open(occupation_id: int, remove := false) -> void:
	if mode!=Mode.Closed or details==null or details.service==null or details.phase!=Details.Phase.Ready:return
	var row: Dictionary={}
	for value in details.snapshot.get("staff",{}).get("rows",[]):
		if int(value.get("source",-1))==0 and int(value.get("occupation_id",-1))==occupation_id:row=value;break
	if row.is_empty() or int(row.get("role",-1)) not in [0,1,2,5,7,8,9,10]:return
	var occupied:=int(row.get("unit_id",-1))>=0 or int(row.get("histfig_id",-1))>=0
	if occupied!=remove:return
	target={"site_id":details.identity.site_id,"location_id":details.identity.id,"occupation_id":occupation_id,"role":row.role}
	details_revision=details.snapshot.revision
	mode=Mode.Removing if remove else Mode.Choosing
	candidates.open(target)

func choose(unit_id: int) -> void:
	if mode!=Mode.Choosing or candidates.phase!=Candidates.Phase.Ready:return
	for row in candidates.rows:
		if int(row.unit_id)==unit_id:_edit(unit_id);return

func _current() -> bool:
	return details!=null and details.phase==Details.Phase.Ready and not target.is_empty() and details.snapshot.get("revision")==details_revision \
		and details.identity.get("site_id")==target.site_id and details.identity.get("id")==target.location_id

func _edit(unit_id: int) -> void:
	if not _current():close();return
	var revision: int=candidates.revision
	mode=Mode.Editing
	candidates.close()
	details.set_staff(int(target.occupation_id),unit_id,revision)
	if details.phase!=Details.Phase.Editing:close()
	changed.emit()

func _candidates_changed() -> void:
	if mode in [Mode.Choosing,Mode.Removing]:
		if not _current() or candidates.phase in [Candidates.Phase.Rejected,Candidates.Phase.Unavailable]:close();return
		if mode==Mode.Removing and candidates.phase==Candidates.Phase.Ready:_edit(-1);return
	changed.emit()

func _details_changed() -> void:
	if mode==Mode.Closed:return
	if mode==Mode.Editing:
		if details.phase==Details.Phase.Editing:return
		var completed: bool=details.phase==Details.Phase.Ready
		close()
		if completed:applied.emit()
	elif not _current():close()
