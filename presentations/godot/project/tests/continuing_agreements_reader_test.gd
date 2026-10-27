extends SceneTree
const Reader=preload("res://scripts/continuing_agreements_reader.gd")
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	signal session_changed
	var calls: Array=[]
	var detached: Array=[]
	var reject:=false
	func submit(domain,request,callback):
		if reject:return 0
		calls.append({"domain":domain,"request":request,"callback":callback});return calls.size()
	func detach(id):detached.append(id)
	func reply(id,rows,valid:=true):
		var request: Dictionary=calls[id-1].request
		calls[id-1].callback.call(id,{"action":request.action,"status":C.ManagementStatus.Ok,"agreement":{"tracker":valid,"tracker_rows":rows}},request)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service=Service.new();var reader=Reader.new();reader.configure(service)
	reader.poll(10);assert(service.calls.is_empty(),"inactive does not request")
	reader.set_active(true);assert(reader.ticket==1 and not reader.ready)
	for frame in 20:reader.set_active(true);reader.refresh();reader.poll(0.01)
	assert(service.calls.size()==1,"one outstanding observation")
	service.reply(1,[{"agreement_id":7,"heading":"Synthetic heading"}])
	assert(reader.ready and reader.snapshot()[0].agreement_id==7)
	var copy:=reader.snapshot();copy[0].agreement_id=8
	assert(reader.snapshot()[0].agreement_id==7,"caller cannot alter retained data")
	reader.poll(0.79);assert(service.calls.size()==1)
	reader.poll(0.02);assert(service.calls.size()==2,"bounded periodic refresh")
	reader.set_active(false);assert(2 in service.detached and not reader.ready and reader.snapshot().is_empty())
	reader.set_active(true);assert(reader.ticket==3)
	service.reply(2,[{"agreement_id":99}]);assert(reader.ticket==3 and reader.snapshot().is_empty(),"old owner cannot populate new owner")
	service.reply(3,[]);assert(reader.ready and reader.snapshot().is_empty(),"empty success remains ready")
	reader.refresh();service.session_changed.emit();service.reply(4,[{"agreement_id":99}])
	reader.poll(10);assert(not reader.active and not reader.ready and reader.snapshot().is_empty() and service.calls.size()==4,"session loss retires and does not replay")
	reader.set_active(true);service.reply(5,[],false)
	assert(not reader.ready,"history reply cannot masquerade as tracker success")
	reader.refresh();service.reply(6,{})
	assert(not reader.ready,"missing typed rows cannot masquerade as empty")
	service.reject=true;reader.refresh();assert(reader.ticket==0 and not reader.ready)
	for frame in 10:reader.poll(0.01)
	assert(service.calls.size()==6,"refused submit does not loop every frame")
	service.reject=false;reader.refresh()
	var close_on_reply: Callable=func():reader.set_active(false)
	reader.changed.connect(close_on_reply);service.reply(7,[{"agreement_id":7}]);reader.changed.disconnect(close_on_reply)
	assert(not reader.active and reader.ticket==0 and reader.snapshot().is_empty(),"synchronous subscriber closure retires facts")
	reader.dispose();assert(not service.session_changed.is_connected(reader.clear))
	print("CONTINUING_AGREEMENTS_READER_PASS");quit(0)
