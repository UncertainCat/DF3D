extends SceneTree
const Removal = preload("res://scripts/building_removal.gd")
class Service:
	extends RefCounted
	var requests := []
	var callbacks := []
	var detached := []
	func submit(_domain,request,observer):
		requests.append(request);callbacks.append(observer);return requests.size()
	func detach(ticket): detached.append(ticket)
	func reply(ticket,result): callbacks[ticket-1].call(ticket,result,requests[ticket-1])
var failures := 0
func check(ok:bool,label:String):
	if not ok: failures+=1;push_error(label)
func receipt(id:int,removing:bool=false)->Dictionary:
	return {"status":2,"building_id":id,"removing":removing,"construction":{"building_key":"Bed"}}
func _initialize():
	var service:=Service.new();var state:=Removal.new();state.service=service
	state.select(10);check(not state.available(),"Read before mutation")
	state.select(11);service.reply(1,receipt(10));check(state.state.is_empty(),"Late selection receipt ignored")
	service.reply(2,receipt(11));check(state.available(),"Matching selection ready")
	state.act();state.act();check(service.requests.size()==3,"One pending mutation")
	check(service.requests[2].building_id==11 and not service.requests[2].cancel_removal,"Remove exact selected identity")
	service.reply(3,receipt(11,true));state.act()
	check(service.requests[3].cancel_removal,"Cancellation is explicit")
	service.reply(4,{"status":3,"outcome":"unknown"});state.act();state.refresh()
	check(service.requests.size()==4 and not state.available(),"Unknown mutation never replayed")
	state.select(12);state.select(-1);service.reply(5,receipt(12));check(state.building_id==-1 and state.state.is_empty(),"Closed selection ignores receipt")
	check(service.detached==[1,5],"Detach outstanding views")
	state.select(13);var forbidden:=receipt(13);forbidden.construction.building_key="Stockpile";service.reply(6,forbidden)
	check(not state.available(),"Area removal stays in native area workflow")
	state.select(-1)
	service.callbacks.clear()
	print("BUILDING_REMOVAL_TEST ","PASS" if failures==0 else "FAIL");quit(failures)
