extends RefCounted
# Details lifetime and edit exclusion surround the independent recognition receipt.
signal changed
const Recognition=preload("res://scripts/location_recognition_state.gd")
var recognition=Recognition.new()
var details
var _owner: Dictionary={}
var _applying:=false

func configure(model) -> void:
	dispose();details=model;recognition.configure(details.service)
	recognition.changed.connect(_recognition_changed)
	details.changed.connect(_details_changed);_details_changed()

func dispose() -> void:
	_owner={};_applying=false
	if details!=null and details.changed.is_connected(_details_changed):details.changed.disconnect(_details_changed)
	if recognition.changed.is_connected(_recognition_changed):recognition.changed.disconnect(_recognition_changed)
	recognition.dispose();details=null

func _details_changed() -> void:
	if details==null:return
	var key: Dictionary={"generation":details.generation,"identity":details.identity.duplicate(true),"revision":details.snapshot.get("revision",0)}
	if _applying and key==_owner and details.phase==details.Phase.Editing:return
	if details.phase!=details.Phase.Ready or int(details.snapshot.get("kind",0))!=2:
		_owner={};_applying=false;recognition.close();return
	if key==_owner:return
	_owner=key;_applying=false;recognition.open(details.identity)

func recognize() -> void:
	if details==null or details.phase!=details.Phase.Ready or _owner.is_empty():return
	recognition.recognize()

func _recognition_changed() -> void:
	if details==null:return
	if recognition.phase==Recognition.Phase.Applying and not _applying:
		_applying=true;details.phase=details.Phase.Editing;details.changed.emit()
	elif _applying and recognition.phase!=Recognition.Phase.Applying:
		_applying=false;details.phase=details.Phase.Ready
		if recognition.phase==Recognition.Phase.Ready:details.refresh()
		else:details.changed.emit()
	changed.emit()
