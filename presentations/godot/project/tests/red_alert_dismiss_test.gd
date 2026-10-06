extends SceneTree
const Controller=preload("res://scripts/red_alert_dismiss_controller.gd")
const C=preload("res://scripts/management_contract.gd")
class World extends RefCounted:
 var epoch:=7
 var producer:=1
 var count:=4
 func is_live():return true
 func session_generation():return producer
 func poll_session():return {"fortress_valid":true,"fortress_epoch":epoch,"alert_button_report_count":count}
class Service extends RefCounted:
 signal session_changed
 var requests:Array=[]
 var detached:Array=[]
 func submit(domain,data,observer):
  requests.append({"domain":domain,"data":data,"observer":observer});return requests.size()
 func detach(ticket):detached.append(ticket)
 func reply(ticket,result):
  var r=requests[ticket-1];r.observer.call(ticket,result,r.data)
func prepared(receipt=9007199254740993) -> Dictionary:
 return {"status":C.ManagementStatus.Ok,"action":C.ManagementAction.PrepareAlertDismissal,"report":{"list_revision":receipt,"total":4}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=World.new();var service=Service.new();var controller=Controller.new()
 root.add_child(controller);controller.configure(world,service)
 assert(not controller.dismiss(6))
 assert(controller.dismiss(7));assert(not controller.dismiss(7))
 service.reply(1,prepared())
 assert(service.requests.size()==2)
 assert(service.requests[1].data=={"action":C.ManagementAction.DismissAlert,"expected_list_revision":9007199254740993})
 service.reply(2,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
 assert(controller.ticket==0 and controller.last_result.outcome=="unknown")
 assert(service.requests.size()==2) # No read or mutation retry follows unknown.
 assert(controller.dismiss(7));controller.cancel()
 assert(service.detached==[3]);service.reply(3,prepared())
 assert(service.requests.size()==3)
 assert(controller.dismiss(7));world.producer=2;service.reply(4,prepared())
 assert(service.requests.size()==4)
 assert(controller.dismiss(7));service.session_changed.emit();service.reply(5,prepared())
 assert(service.requests.size()==5 and service.detached==[3,5])
 for receipt in [0,-1,1.0,"1"]:
  assert(controller.dismiss(7));var request:int=controller.ticket
  service.reply(request,prepared(receipt));assert(service.requests.size()==request and controller.ticket==0)
 assert(controller.dismiss(7));var request:int=controller.ticket
 service.reply(request,{"status":C.ManagementStatus.Rejected,"action":C.ManagementAction.PrepareAlertDismissal})
 assert(service.requests.size()==request and controller.ticket==0)
 world.count=0;assert(not controller.dismiss(7))
 controller.free()
 print("RED_ALERT_DISMISS_PASS");quit()
