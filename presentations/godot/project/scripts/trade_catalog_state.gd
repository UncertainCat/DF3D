extends RefCounted
# Read ownership for the staged merchant chooser. Choice tokens belong to this
# receipt only; the forthcoming session opener must consume them in the bridge.
signal changed
signal choice_requested(depot_id: int, token: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Choosing,Rejected,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var depot_id: int=-1
var title: String=""
var from_text: String=""
var choices: Array=[]
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
	if ticket!=0 and service!=null:service.detach(ticket)
	ticket=0;depot_id=-1;title="";from_text="";choices=[];phase=Phase.Closed;changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	depot_id=id
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.TradeCatalogRead,"depot_id":id}
	ticket=service.submit("trade_catalog",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_catalog")
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or not _valid(value,id):phase=Phase.Rejected
		else:
			title=value.title;from_text=value.from_text;choices=value.choices.duplicate(true);phase=Phase.Ready
		changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func choose(token: int) -> void:
	if phase!=Phase.Ready or not choices.any(func(row):return row.token==token):return
	# Disable duplicate clicks before handing the exact receipt token to its owner.
	phase=Phase.Choosing;changed.emit();choice_requested.emit(depot_id,token)
func _valid(value: Variant,id: int) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("depot_id"))!=TYPE_INT or value.depot_id!=id:return false
	if typeof(value.get("choices"))!=TYPE_ARRAY or value.choices.size()>4096:return false
	var bytes:=0
	for key in ["title","from_text"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>2048:return false
		bytes+=value[key].to_utf8_buffer().size()
	var seen: Dictionary={}
	for row in value.choices:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("token"))!=TYPE_INT or row.token<=0 or seen.has(row.token):return false
		if typeof(row.get("entity_id"))!=TYPE_INT or row.entity_id<0 or row.entity_id>2147483647:return false
		seen[row.token]=true
		for key in ["race","name"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>2048:return false
			bytes+=row[key].to_utf8_buffer().size()
	return bytes<=384*1024
