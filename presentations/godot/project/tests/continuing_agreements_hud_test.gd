extends SceneTree
const C=preload("res://scripts/management_contract.gd")
class Service:
	extends RefCounted
	signal session_changed
	var calls: Array=[]
	var detached: Array=[]
	func submit(domain,request,callback):
		calls.append({"domain":domain,"request":request,"callback":callback});return calls.size()
	func detach(id):detached.append(id)
	func reply(id,rows):
		var call=calls[id-1]
		call.callback.call(id,{"action":call.request.action,"status":C.ManagementStatus.Ok,
			"agreement":{"tracker":true,"tracker_rows":rows,"tracker_details":{}}},call.request)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var owner=preload("res://scripts/continuing_agreements_hud.gd").new()
	owner.list_view=preload("res://scripts/continuing_agreements_view.gd").new()
	owner.popup_view=preload("res://scripts/continuing_agreement_popup_view.gd").new()
	# No installed art is needed for the actual geometry/reader composition.
	var service=Service.new();owner.bind(service)
	var row={"agreement_id":7,"entity_id":8,"entity_type":0,"tier":0,"heading":"","applicant":"","date":""}
	owner.sync_session(true,[1,4294967297]);service.reply(1,[row])
	owner.update_hover(0,Vector2(1200,800),Vector2.ONE,Vector2(1000,235),true,true)
	assert(owner.hover_claimed and owner.popup_reader.ticket==2 and not owner.popup_view.visible,"pending popup owns hover immediately")
	owner.update_hover(0,Vector2(1200,800),Vector2.ONE,Vector2(1000,274),true,true)
	assert(not owner.hover_claimed and 2 in service.detached,"separator retires pending hover")
	service.reply(2,[row]);assert(not owner.popup_view.visible,"late details cannot reappear")
	owner.update_hover(0,Vector2(2400,1600),Vector2(2,2),Vector2(2000,470),true,true)
	assert(owner.hover_claimed and owner.popup_reader.ticket==3,"scaled pointer uses logical grid")
	service.reply(3,[row]);assert(owner.popup_view.visible)
	owner.update_hover(0,Vector2(1200,800),Vector2.ONE,Vector2(1000,235),true,false)
	assert(owner.list_view.visible and not owner.popup_view.visible and not owner.hover_claimed,"Info suppresses popup independently of list")
	owner.update_hover(0,Vector2(1200,800),Vector2.ONE,Vector2(1000,235),false,true)
	assert(not owner.list_view.visible and not owner.hover_claimed,"hidden list cannot target")
	owner.update_hover(0,Vector2(1200,800),Vector2.ONE,Vector2(1000,235),true,true)
	assert(owner.popup_reader.ticket==4)
	owner.pointer_position=Vector2(1000,235)
	service.session_changed.emit();service.reply(4,[row])
	assert(owner.pointer_position==Vector2(-1,-1),"session loss requires new pointer intent")
	owner.sync_session(true,[1,4294967297])
	for frame in 10:owner.update_hover(1,Vector2(1200,800),Vector2.ONE,Vector2(1000,235),true,true)
	assert(service.calls.size()==4 and not owner.hover_claimed and not owner.list_view.visible and not owner.popup_view.visible,"retired HUD cannot replay on redraw")
	owner.sync_session(true,[1,8589934593]);assert(service.calls.size()==5,"full 64-bit epoch identifies fresh sessions")
	owner.retire();service.reply(5,[row]);assert(not owner.list_view.visible)
	owner.popup_reader.dispose();owner.reader.dispose()
	owner.list_view.free();owner.popup_view.free();owner.free()
	print("CONTINUING_AGREEMENTS_HUD_PASS");quit(0)
