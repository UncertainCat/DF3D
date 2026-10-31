extends Node
signal changed
signal applied
const Header=preload("res://scripts/creature_header_state.gd")
var state=Header.new()
var entry=preload("res://scripts/area_name_entry.gd").new()
var opened:=false
var requested:=false
var field: int=-1
var values: Array[String]=["",""]
var fallback: Array[String]=["",""]
var fallback_generation: int=-1
var fallback_valid:=false

func configure(service) -> void:
	add_child(entry);entry.byte_limit=30;entry.hide()
	entry.edited.connect(func(value):
		if field<0:return
		values[field]=value
		fallback_valid=false
		if not state.edit(field==1,value):close();return
		changed.emit())
	entry.submitted.connect(end_field)
	state.changed.connect(_state_changed)
	state.applied.connect(func():fallback_valid=false;applied.emit())
	state.configure(service)

func open(id: int) -> void:
	close();state.open(id);requested=true
	_state_changed()

func close() -> void:
	requested=false;opened=false;field=-1;entry.finish();values=["",""]
	state.close();changed.emit()

func _state_changed() -> void:
	if requested and state.phase==Header.Phase.Ready:
		requested=false;values=[state.snapshot.nickname,state.snapshot.profession]
		opened=true
		if not state.begin():opened=false
	elif state.phase not in [Header.Phase.Reading,Header.Phase.Editing,Header.Phase.Ready]:
		requested=false;opened=false;field=-1;entry.finish();values=["",""]
	changed.emit()

func focus(profession: bool) -> void:
	if not opened or state.phase!=Header.Phase.Editing:return
	# Approved2026-10-31: only the last field clicked receives typing.
	entry.finish();field=1 if profession else 0
	entry.begin(values[field]);entry.hide();changed.emit()

func end_field() -> void:
	field=-1;entry.finish();changed.emit()

func feed_key(event: InputEventKey) -> bool:
	if not opened or field<0:return false
	entry.feed_key(event);return true

func observe_captions(generation: int,captions: Dictionary) -> void:
	if generation==fallback_generation:return
	fallback_generation=generation
	fallback_valid=not captions.is_empty()
	fallback=[str(captions.get("name","")),str(captions.get("profession",""))]

func caption(index: int,milliseconds: int) -> String:
	var value:=values[index]
	if field==index:return value+("_" if milliseconds%1000<500 else "")
	return value if not value.is_empty() else fallback[index] if fallback_valid else ""

func _exit_tree() -> void:state.dispose()
