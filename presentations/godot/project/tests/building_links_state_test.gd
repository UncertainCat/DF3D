extends SceneTree
const Model=preload("res://scripts/building_links_state.gd")
const C=preload("res://scripts/management_contract.gd")
var failed:=false
class Service:
	extends RefCounted
	signal session_changed
	var next:=0
	var pending: Dictionary={}
	func submit(_domain,intent,callback):
		next+=1;pending[next]=[intent,callback];return next
	func detach(_ticket):pass # Deliberately deliver detached replies to test ownership.
	func reply(ticket,page):
		var entry: Array=pending[ticket]
		entry[1].call(ticket,{"action":entry[0].action,"status":2,"production":{"building_links":page}},entry[0])
func check(value: bool,message: String) -> void:
	if not value:failed=true;push_error(message)
func page(cursor: int,total: int,revision: int) -> Dictionary:
	var rows: Array=[]
	for index in range(cursor,mini(cursor+64,total)):
		rows.append({"id":40,"type":9,"item_id":100+index,"reference_type":33,"name":"native","x":97,"y":105,"z":164})
	return {"building_id":55,"revision":revision,"tabs":true,"cursor":cursor,"next_cursor":cursor+rows.size() if cursor+rows.size()<total else 0,"total":total,"rows":rows}
func _initialize() -> void:
	var service=Service.new();var model=Model.new();model.configure(service)
	model.open(55);service.reply(model.ticket,page(0,70,9007199254740993))
	check(model.phase==Model.Phase.Ready and model.rows().size()==64,"Duplicate target rows were lost")
	model.seek(64);service.reply(model.ticket,page(64,70,9007199254740993))
	model.poll_refresh(0.5);check(model.snapshot.cursor==64,"Refresh discarded displayed viewport")
	service.reply(model.ticket,page(0,1,9007199254740994))
	check(model.snapshot.cursor==0 and model.rows().size()==1,"Shrinking list did not clamp viewport")
	model.poll_refresh(0.5);var old: int=model.ticket;model.close();service.reply(old,page(0,1,9007199254740995))
	check(model.phase==Model.Phase.Closed and model.snapshot.is_empty(),"Late refresh reopened closed links")
	model.open(55);var wrong:=page(0,1,1);wrong.building_id=39;service.reply(model.ticket,wrong)
	check(model.phase==Model.Phase.Rejected and model.snapshot.is_empty(),"Wrong-target page retained authority")
	model.dispose();print("BUILDING_LINKS_STATE_PASS" if not failed else "BUILDING_LINKS_STATE_FAIL");quit(1 if failed else 0)
