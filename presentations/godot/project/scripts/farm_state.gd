extends RefCounted
# Owns local selection and displayed order; DF supplies all choices and effects.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var season: int=-1
var snapshot: Dictionary={}
var row_order: Array[int]=[]
var ticket:=0
var generation:=0
var _initial_current:=false

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
	ticket=0;building_id=-1;season=-1;snapshot={};row_order.clear();_initial_current=false;phase=Phase.Closed
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(id: int, selected_season: int=-1) -> void:
	close()
	if id<0 or id>2147483647 or selected_season < -1 or selected_season>3:
		_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=id;season=maxi(selected_season,0);_initial_current=selected_season==-1
	_read()

func select_season(selected: int) -> void:
	if building_id<0 or selected<0 or selected>3 or selected==season:return
	open(building_id,selected)

func refresh() -> void:
	if building_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func _read() -> void:
	snapshot={};row_order.clear();phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_id":building_id,"season":season})

func choices() -> Array:
	var by_id: Dictionary={}
	for row in snapshot.get("choices",[]):by_id[row.id]=row
	var result: Array=[]
	for id in row_order:
		if by_id.has(id):result.append(by_id[id].duplicate(true))
	return result

func choose_crop(crop: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var present:=crop==-1
	for row in snapshot.choices:
		if row.id==crop:present=true
	if not present:return
	_edit(C.FarmOperation.Crop,{"crop_id":crop})

func toggle_fertilization() -> void:
	_edit(C.FarmOperation.FertilizationToggle,{})

func set_seasonal_fertilization(enabled: bool) -> void:
	_edit(C.FarmOperation.SeasonalFertilization,{"seasonal_fertilization":int(enabled)})

func rename(name: String) -> void:
	# Encoding eligibility and the native byte limit are revalidated by DF's
	# bridge adapter. This controller owns one explicit intent, not a text draft.
	var bytes:=name.to_utf8_buffer()
	if bytes.size()>90 or bytes.has(0):return
	_edit(C.FarmOperation.Rename,{"farm_name":name})

func _edit(operation: int, fields: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.get("removing",true):return
	var intent: Dictionary={"action":C.ManagementAction.FarmEdit,"building_id":building_id,
		"season":season,"expected_revision":snapshot.revision,"farm_operation":operation}
	intent.merge(fields);phase=Phase.Applying;_send(intent)

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};row_order.clear();changed.emit()

func _valid(farm: Dictionary) -> bool:
	for key in ["building_id","selected_season","current_season","revision","current_fertilization","max_fertilization","pending_fertilization"]:
		if typeof(farm.get(key))!=TYPE_INT:return false
	if farm.building_id!=building_id or farm.selected_season!=season or farm.revision<=0 or farm.current_season<0 or farm.current_season>3:return false
	for key in ["custom_name","header_name"]:
		if typeof(farm.get(key))!=TYPE_STRING or farm[key].to_utf8_buffer().size()>1536:return false
	if farm.header_name.is_empty():return false
	for key in ["removing","removal_suspended","removal_has_worker"]:
		if typeof(farm.get(key))!=TYPE_BOOL:return false
	if not farm.removing and (farm.removal_suspended or farm.removal_has_worker):return false
	if farm.current_fertilization<0 or farm.max_fertilization<0 or farm.pending_fertilization<0:return false
	if typeof(farm.get("seasonal_fertilization"))!=TYPE_BOOL or typeof(farm.get("seasonal_crops"))!=TYPE_ARRAY or farm.seasonal_crops.size()!=4:return false
	for crop in farm.seasonal_crops:
		if typeof(crop)!=TYPE_INT or crop < -1 or crop>32767:return false
	if typeof(farm.get("choices"))!=TYPE_ARRAY or farm.choices.size()>256:return false
	var ids: Dictionary={}
	for row in farm.choices:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("id"))!=TYPE_INT or row.id<0 or row.id>32767 or ids.has(row.id):return false
		if typeof(row.get("name"))!=TYPE_STRING or row.name.is_empty():return false
		if typeof(row.get("raw_id"))!=TYPE_STRING or row.raw_id.is_empty() or row.raw_id.to_utf8_buffer().size()>128:return false
		if typeof(row.get("seeds_available"))!=TYPE_BOOL or typeof(row.get("current_season_warning"))!=TYPE_BOOL:return false
		ids[row.id]=true
	return true

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var production: Dictionary=result.get("production",{})
	var outcome:=int(production.get("farm_edit_outcome",C.FarmEditOutcome.None))
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:
		_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	var observed: Dictionary=production.get("farm",{})
	if result.get("action",-1)!=sent.action or not _valid(observed) or (editing and outcome!=C.FarmEditOutcome.Completed):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing and sent.get("farm_operation",C.FarmOperation.Crop)==C.FarmOperation.Rename and observed.custom_name!=sent.farm_name:
		_fail(Phase.Unknown);return
	if _initial_current:
		_initial_current=false
		if observed.current_season!=season:
			season=observed.current_season;_read();return
	# A successful edit may return a freshly sorted provider list. Native keeps
	# existing entry positions until the tab rebuilds, so presentation order is
	# separate from the untouched snapshot/revision used by the next edit.
	var present: Dictionary={}
	for row in observed.choices:present[row.id]=true
	var retained: Array[int]=[]
	for id in row_order:
		if present.has(id):retained.append(id)
	for row in observed.choices:
		if row.id not in retained:retained.append(row.id)
	row_order=retained;snapshot=observed.duplicate(true);phase=Phase.Ready
	changed.emit()
	if editing:applied.emit()
