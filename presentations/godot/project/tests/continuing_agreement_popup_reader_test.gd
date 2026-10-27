extends SceneTree
const PopupReader=preload("res://scripts/continuing_agreement_popup_reader.gd")
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	var calls: Array=[]
	var detached: Array=[]
	var refuse:=false
	func submit(domain,request,callback):
		if refuse:return 0
		calls.append({"domain":domain,"request":request,"callback":callback});return calls.size()
	func detach(id):detached.append(id)
	func reply(id,row,details={},status=C.ManagementStatus.Ok):
		calls[id-1].callback.call(id,{"action":C.ManagementAction.AgreementInspect,"status":status,"agreement":{"tracker":true,"tracker_rows":[row],"tracker_details":details}},calls[id-1].request)
class Source:
	extends RefCounted
	signal changed
	var service=Service.new()
	var ready:=true
	var active:=true
	var rows: Array=[]
	func snapshot():return rows.duplicate(true)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var source=Source.new();var popup=PopupReader.new();popup.configure(source);var service=source.service
	var a: Dictionary={"agreement_id":7,"entity_id":8};var b: Dictionary={"agreement_id":9,"entity_id":10}
	source.rows=[a,b]
	popup.display({"agreement_id":88});assert(service.calls.is_empty())
	popup.display(a);assert(popup.ticket==1 and service.calls[0].request.id==7)
	for frame in 20:popup.display(a);popup.refresh()
	assert(service.calls.size()==1,"one outstanding observation")
	popup.display(b);assert(1 in service.detached and popup.ticket==2)
	service.reply(1,a,{"location_id":1});assert(popup.ticket==2 and not popup.ready,"old hover cannot publish")
	service.reply(2,b,{"location_id":2});assert(popup.ready and popup.snapshot().details.location_id==2)
	var copy:=popup.snapshot();copy.details.location_id=99;assert(popup.snapshot().details.location_id==2)
	popup.poll(0.99);assert(service.calls.size()==2);popup.poll(0.02);assert(popup.ticket==3)
	service.reply(3,a);assert(not popup.ready and popup.snapshot().is_empty(),"foreign identity rejected")
	popup.refresh();source.rows=[a];source.changed.emit();service.reply(4,b)
	assert(popup.target.is_empty() and popup.snapshot().is_empty(),"removed row retires held reply")
	popup.display(a);source.ready=false;source.active=false;source.changed.emit();service.reply(5,a)
	popup.poll(10);assert(popup.target.is_empty() and service.calls.size()==5,"lost session does not replay")
	source.ready=true;source.active=true;source.changed.emit();assert(service.calls.size()==5)
	popup.display(a);service.reply(6,a,{},C.ManagementStatus.Rejected);assert(not popup.ready)
	for frame in 20:popup.display(a)
	assert(service.calls.size()==6,"redraw does not retry rejected read")
	popup.refresh();service.reply(7,a,[]);assert(not popup.ready,"missing typed details rejected")
	service.refuse=true;popup.refresh();assert(popup.ticket==0 and not popup.ready)
	popup.poll(0.1);assert(service.calls.size()==7)
	service.refuse=false;popup.refresh()
	var close: Callable=func():popup.clear(false)
	popup.changed.connect(close);service.reply(8,a);popup.changed.disconnect(close)
	assert(popup.target.is_empty() and not popup.ready and popup.ticket==0,"synchronous close survives callback")
	popup.display(a);popup.dispose();service.reply(9,a)
	assert(popup.snapshot().is_empty() and not source.changed.is_connected(popup._source_changed))
	print("CONTINUING_AGREEMENT_POPUP_READER_PASS");quit(0)
