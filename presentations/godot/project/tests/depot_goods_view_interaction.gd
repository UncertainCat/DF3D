extends "res://tests/depot_goods_view_capture.gd"
const C=preload("res://scripts/management_contract.gd")
class Service extends RefCounted:
	var ticket:=0
	var intent: Dictionary={}
	var observer: Callable
	func submit(_domain: String,value: Dictionary,callback: Callable) -> int:
		ticket+=1;intent=value.duplicate(true);observer=callback;return ticket
	func detach(_ticket: int) -> void:pass
var directory: String
var closed:=false
func snapshot(label: String) -> Dictionary:
	return integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/depot-goods-wire-"+label+"-result.json"))).snapshot
func click_at(point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func rendered(label: String) -> bool:
	await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.convert(Image.FORMAT_RGBA8)
	var native:=Image.load_from_file(directory+"/depot-goods-wire-"+label+".png");native.convert(Image.FORMAT_RGBA8)
	actual.save_png(directory+"/depot-goods-interaction-"+label+".png")
	for rect in [Rect2i(920,112,24,36),Rect2i(872,148,72,72),Rect2i(808,76,136,36)]:
		if actual.get_region(rect).get_data()!=native.get_region(rect).get_data():
			push_error("Depot draft pixels differ: "+label+" "+str(rect));return false
	return true
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	var world=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var service:=Service.new();var model=Model.new();model.service=service
	var value:=snapshot("anvils");model.depot_id=value.depot_id;model.category=value.category;model.revision=value.revision
	model.categories=value.categories;model.groups=value.groups
	for row in value.items:model.items[row.id]=row
	model.phase=Model.Phase.Ready
	var view=View.new();root.add_child(view);view.configure_goods(world,model);view.layout(Vector2(1200,800));view.cancelled.connect(func():closed=true)
	for i in 4:await process_frame
	for step in [[Vector2(932,166),"draft-individual-on"],[Vector2(932,130),"draft-mixed-group-on"],[Vector2(932,130),"draft-group-off"],[Vector2(928,94),"draft-select-all-on"],[Vector2(928,94),"draft-select-all-off"]]:
		await click_at(step[0])
		if model.phase!=Model.Phase.Reading or service.intent.action!=C.ManagementAction.DepotGoodsRead:
			push_error("Visible checkbox did not submit draft projection: "+step[1]);quit(1);return
		service.observer.call(service.ticket,{"status":C.ManagementStatus.Ok,"action":C.ManagementAction.DepotGoodsRead,"depot_goods":snapshot(step[1])},service.intent)
		if model.phase!=Model.Phase.Ready or not await rendered(step[1]):quit(1);return
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;Input.parse_input_event(escape);await process_frame
	if closed or model.phase!=Model.Phase.Applying or service.intent.action!=C.ManagementAction.DepotGoodsCommit:
		push_error("Escape did not await commit confirmation");quit(1);return
	var request: Dictionary=service.intent
	service.observer.call(service.ticket,{"status":C.ManagementStatus.Ok,"action":request.action,"depot_commit":{"depot_id":request.depot_id,"expected_revision":request.expected_revision,"observed_revision":request.expected_revision,"outcome":C.DepotGoodsCommitOutcome.Applied}},request)
	if not closed or model.phase!=Model.Phase.Closed:push_error("Confirmed commit did not retire view");quit(1);return
	view.queue_free();await process_frame;model.service=null;model.dispose();world.queue_free();await process_frame
	print("DEPOT_GOODS_VIEW_INTERACTION_PASS");quit()
