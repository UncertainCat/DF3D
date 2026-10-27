extends RefCounted
# Local entry and ordered explicit intent only; native owns eligibility and raw units.
signal changed
const C = preload("res://scripts/management_contract.gd")
var details
var editing := -1
var text := ""
var pending := false
var queue: Array[Dictionary] = []
var generation := -1

func configure(model) -> void:
	dispose()
	details=model;generation=details.generation
	details.changed.connect(_details_changed)

func dispose() -> void:
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	details=null
	_clear()

func _clear() -> void:
	editing=-1;text="";pending=false;queue.clear()
	changed.emit()

func available() -> bool:
	return details!=null and generation==details.generation and (details.phase==details.Phase.Ready or (pending and details.phase==details.Phase.Editing))

func begin(quantity: int) -> void:
	if not available() or quantity<0 or quantity>10:return
	editing=quantity;text="";changed.emit()

func type_text(value: String) -> void:
	if editing<0 or not available():return
	var digits := ""
	for character in value:
		if character>="0" and character<="9" and digits.length()<3:digits+=character
	if digits==text:return
	text=digits
	_enqueue(editing,C.LocationQuantityMode.Set,int(digits))
	changed.emit()

func finish() -> void:
	# Ending local entry does not cancel explicit values already typed.
	editing=-1;text="";changed.emit()

func step(quantity: int, mode: int) -> void:
	if not available() or quantity<0 or quantity>10 or mode not in [C.LocationQuantityMode.Increase,C.LocationQuantityMode.Decrease]:return
	_enqueue(quantity,mode,0)

func _enqueue(quantity: int, mode: int, value: int) -> void:
	var intent := {"quantity":quantity,"mode":mode,"value":value}
	# Only replace consecutive unsent text values for the same field. Steps and
	# changes of field retain order and cannot be converted into rounded Sets.
	if not queue.is_empty() and mode==C.LocationQuantityMode.Set and queue[-1].mode==mode and queue[-1].quantity==quantity:
		queue[-1]=intent
	else:queue.append(intent)
	_send_next()

func _send_next() -> void:
	if pending or queue.is_empty() or not available() or details.phase!=details.Phase.Ready:return
	var intent: Dictionary=queue.pop_front()
	pending=true
	details.edit_quantity(intent.quantity,intent.mode,intent.value)
	if details.phase!=details.Phase.Editing:_clear()

func _details_changed() -> void:
	if generation!=details.generation:
		generation=details.generation;_clear();return
	if pending:
		if details.phase==details.Phase.Editing:return
		if details.phase!=details.Phase.Ready:_clear();return
		pending=false
		_send_next()
	elif details.phase!=details.Phase.Ready:
		_clear();return
	changed.emit()
