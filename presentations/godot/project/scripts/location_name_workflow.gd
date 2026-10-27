extends RefCounted
# Details owns the target lifetime; the name editor owns its separate receipt.
signal changed
const Names=preload("res://scripts/location_name_state.gd")
var names=Names.new()
var details
var active:=false
var _generation:=-1
var _identity: Dictionary={}
var _dirty:=false

func configure(model) -> void:
	dispose();details=model
	names.configure(details.service)
	names.changed.connect(_names_changed);names.applied.connect(_applied)
	details.changed.connect(_details_changed)

func dispose() -> void:
	close(false)
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if names.changed.is_connected(_names_changed):names.changed.disconnect(_names_changed)
	if names.applied.is_connected(_applied):names.applied.disconnect(_applied)
	names.dispose();details=null

func open() -> void:
	if active or details==null or details.phase!=details.Phase.Ready:return
	active=true;_dirty=false;_generation=details.generation;_identity=details.identity.duplicate(true)
	names.open(_identity);changed.emit()

func close(refresh:=true) -> void:
	var should_refresh: bool=refresh and active and _dirty and _current()
	active=false;_dirty=false;_generation=-1;_identity={};names.close()
	if should_refresh:details.refresh()
	changed.emit()

func _current() -> bool:
	return details!=null and details.generation==_generation and details.identity==_identity and details.phase==details.Phase.Ready

func _details_changed() -> void:
	if active and not _current():close(false)

func _names_changed() -> void:
	# Closing a pending edit must also refresh Details: a sent mutation may
	# finish after this editor retires. The shared service orders the read after it.
	if active and names.phase==Names.Phase.Editing:_dirty=true
	changed.emit()

func _applied() -> void:
	if active:_dirty=true
