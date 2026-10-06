extends SceneTree
const Model=preload("res://scripts/alert_entries_state.gd")
const Controller=preload("res://scripts/alert_entries_controller.gd")
const Service=preload("res://scripts/semantic_action_service.gd")
const Status=preload("res://scripts/management_contract.gd").ManagementStatus
class FakeWorld:
 extends RefCounted
 var snapshot:={"world_epoch":5,"revision":1,"status":0}
 var generation:=1
 var calls:Array=[]
 func reconnect_management():pass
 func poll_management():return snapshot.duplicate(true)
 func session_generation():return generation
 func is_live():return true
 func last_error():return ""
 func management_request(domain,request):
  calls.append({"domain":domain,"request":request.duplicate(true)});return calls.size()

func reply(model,reports:Array=[],units:Array=[]) -> bool:
 return model.accept(model.generation,model.epoch,{"view":4,"reports":reports,"units":units})
func _initialize():
 var model=Model.new();model.set_epoch(7)
 var ids:Array=[]
 for i in 70:ids.append(i)
 ids.append(4)
 var refs:Array=[{"unit_id":17,"category":1},{"unit_id":999,"category":0},{"unit_id":17,"category":1}]
 model.open({"report_ids":ids,"unit_reports":refs,"complete":true})
 assert(model.pending.request.ids.size()==64)
 var rows:Array=[]
 for id in 64:
  if id!=9:rows.append({"id":id,"text":"bulk","text_complete":id!=4})
 assert(reply(model,rows));assert(model.rows.is_empty() and not model.loaded)
 assert(model.pending.request.ids==[64,65,66,67,68,69,4])
 rows=[]
 for id in model.pending.request.ids:rows.append({"id":id,"text":"bulk","text_complete":id!=4})
 assert(reply(model,rows));assert(model.pending.request.units==refs)
 assert(reply(model,[],[{"unit_id":17,"category":1},{"unit_id":17,"category":1}]))
 assert(model.pending.mode=="resolve" and model.pending.request.ids==[4])
 assert(reply(model,[{"id":4,"text":"Full native text","text_complete":true}]))
 assert(model.complete and model.loaded and model.rows.size()==72 and model.pending.is_empty())
 assert(model.rows[4].data.text=="Full native text" and model.rows[69].data.text=="Full native text")
 assert(model.rows[70].kind=="unit" and model.rows[71].data.unit_id==17)
 # A receipt must preserve requested order and cannot introduce foreign rows.
 model.open({"report_ids":[2,1],"complete":true})
 assert(not reply(model,[{"id":1},{"id":2}]))
 assert(not reply(model,[{"id":999}]))
 var late:int=model.generation;model.close()
 assert(not model.accept(late,7,{"view":4,"reports":[{"id":2}]}))
 # Missing references are omitted; missing during full-text resolution also
 # removes duplicates. Unresolvable long text never loops or claims completeness.
 model.open({"report_ids":[1,1],"complete":true})
 reply(model,[{"id":1,"text_complete":false},{"id":1,"text_complete":false}]);reply(model)
 assert(model.complete and model.rows.is_empty())
 model.open({"report_ids":[1],"complete":true})
 reply(model,[{"id":1,"text_complete":false}]);reply(model,[{"id":1,"text_complete":false}])
 assert(not model.loaded and model.pending.request.view==5)
 text_paging(model)
 model.open({"report_ids":[1],"report_count":300,"complete":false})
 reply(model,[{"id":1,"text_complete":true}]);assert(model.loaded and not model.complete)
 model.open({"report_ids":[1],"complete":true});model.reject(model.generation)
 assert(model.failed and not model.complete and model.pending.is_empty())
 model.set_epoch(8);assert(not model.opened and model.rows.is_empty())
 model.open({"unit_reports":[{"unit_id":17,"category":1}],"complete":true})
 reply(model,[],[{"unit_id":17,"category":1,"log_count":65}])
 var parent:Array=model.rows.duplicate(true)
 assert(not model.open_unit(18,1));assert(model.open_unit(17,1))
 assert(model.pending.request=={"action":34,"view":3,"unit_id":17,"unit_category":1,"after_id":-1,"expected_list_revision":0})
 rows=[]
 for id in 64:rows.append({"id":id,"text_complete":true})
 assert(model.accept(model.generation,8,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":rows,"next_after_id":63}))
 assert(model.pending.request.after_id==63 and model.pending.request.expected_list_revision==71 and not model.loaded)
 assert(not model.accept(model.generation,8,{"view":3,"list_revision":72,"unit_id":17,"unit_category":1,"reports":[{"id":64,"text_complete":true}]}))
 assert(not model.accept(model.generation,8,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":[],"next_after_id":63}))
 assert(model.accept(model.generation,8,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":[{"id":64,"text_complete":true}]}))
 assert(model.complete and model.rows.size()==65 and model.rows[0].data.id==0)
 model.back();assert(model.opened and model.unit_id==-1 and model.rows==parent and model.pending.is_empty())
 model.open_unit(17,1);late=model.generation;model.back()
 assert(not model.accept(late,8,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":[]}))
 model.back();assert(not model.opened)
 group_snapshot()
 recovery_controller()
 recovery_lifecycle()
 controller_lifecycle()
 print("ALERT_ENTRIES_PASS");quit()

func controller_lifecycle():
 var world=FakeWorld.new();var service=Service.new();service.configure(world);service.poll()
 var owner=Controller.new();owner.configure(service)
 owner.state.open({"report_ids":[41],"complete":true});owner.state.close();service.poll()
 assert(world.calls.is_empty() and owner.ticket==0)
 owner.state.open({"report_ids":[41],"complete":true});service.poll()
 assert(world.calls.size()==1 and world.calls[0].domain=="reports")
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Ok,"action":35,"report":{"view":4,"reports":[{"id":41,"text_complete":false}]}}
 service.poll();service.poll();assert(world.calls.size()==2)
 owner.state.close()
 world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Ok,"action":35,"report":{"view":4,"reports":[{"id":41,"text_complete":true}]}}
 service.poll();assert(owner.state.rows.is_empty() and not owner.state.opened)
 owner.state.open({"report_ids":[42],"complete":true});service.poll()
 world.snapshot={"world_epoch":6,"revision":1,"status":0};service.poll()
 assert(not owner.state.opened and owner.ticket==0)
 owner.shutdown();owner.free();service.free()

func text_paging(model) -> void:
 var initial_epoch:int=model.epoch
 var start:int=model.generation
 var page:Dictionary={"view":5,"cursor":0,"next_cursor":16383,"total":16391,"list_revision":99,"reports":[{"id":1,"text":"a".repeat(16383),"text_complete":false,"color":3}]}
 assert(model.accept(start,model.epoch,page))
 assert(not model.loaded and model.rows.is_empty())
 model.reject(model.generation);assert(model.retry_read())
 assert(model.pending.request.cursor==0 and model.pending.request.expected_list_revision==99)
 assert(model.accept(model.generation,model.epoch,page))
 assert(model.pending.request.cursor==16383 and model.pending.request.expected_list_revision==99)
 var last:Dictionary={"view":5,"cursor":16383,"next_cursor":0,"total":16391,"list_revision":99,"reports":[{"id":1,"text":"☺ TAIL","text_complete":false,"color":3}]}
 for key in ["cursor","total","list_revision"]:
  var bad:Dictionary=last.duplicate(true);bad[key]=int(bad[key])+1
  assert(not model.accept(model.generation,model.epoch,bad))
 var bad:Dictionary=last.duplicate(true);bad.reports[0].color=4
 assert(not model.accept(model.generation,model.epoch,bad))
 assert(model.accept(model.generation,model.epoch,last))
 assert(model.complete and model.rows[0].data.text=="a".repeat(16383)+"☺ TAIL")
 model.open({"report_ids":[1,1],"complete":true})
 reply(model,[{"id":1,"text_complete":false},{"id":1,"text_complete":false}]);reply(model,[{"id":1,"text_complete":false}])
 assert(model.accept(model.generation,model.epoch,page))
 var late:int=model.generation;model.close()
 assert(model._text_bytes.is_empty() and model._text.is_empty())
 assert(not model.accept(late,model.epoch,last))
 model.open({"report_ids":[1,1],"complete":true})
 reply(model,[{"id":1,"text_complete":false},{"id":1,"text_complete":false}]);reply(model,[{"id":1,"text_complete":false}])
 assert(model.accept(model.generation,model.epoch,page))
 assert(model.accept(model.generation,model.epoch,last))
 assert(model.complete and model.rows.size()==2 and model.rows[0].data==model.rows[1].data)

 # Returning from a unit log abandons partial text and restores the parent.
 model.open({"unit_reports":[{"unit_id":17,"category":1}],"complete":true})
 reply(model,[],[{"unit_id":17,"category":1}]);var parent:Array=model.rows.duplicate(true)
 assert(model.open_unit(17,1))
 assert(model.accept(model.generation,model.epoch,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":[{"id":1,"text":"a","color":3,"text_complete":false}]}))
 assert(model.pending.mode=="unit_text" and model.pending.request.expected_list_revision==71)
 var unit_page:Dictionary=page.duplicate(true)
 unit_page.tab=0;unit_page.unit_id=17;unit_page.unit_category=1;unit_page.list_revision=71
 assert(model.accept(model.generation,model.epoch,unit_page))
 late=model.generation;model.back()
 assert(model.rows==parent and model.complete and model._text_bytes.is_empty() and model._unit_text==null)
 assert(not model.accept(late,model.epoch,last))
 # Unit-owned pages cannot be replaced by an independent text snapshot, even
 # when report identity and bytes match. Completion publishes the retained row.
 assert(model.open_unit(17,1))
 assert(model.accept(model.generation,model.epoch,{"view":3,"list_revision":71,"unit_id":17,"unit_category":1,"reports":[{"id":1,"text":"a","color":3,"text_complete":false}]}))
 assert(not model.accept(model.generation,model.epoch,page))
 assert(model.accept(model.generation,model.epoch,unit_page))
 var unit_last:Dictionary=last.duplicate(true)
 unit_last.tab=0;unit_last.unit_id=17;unit_last.unit_category=1;unit_last.list_revision=71
 assert(model.accept(model.generation,model.epoch,unit_last))
 assert(model.complete and model.rows[0].data.text=="a".repeat(16383)+"☺ TAIL")
 model.back()
 # Session replacement and rejection also retire partial buffers.
 for reset_kind in ["epoch","reject"]:
  model.open({"report_ids":[1],"complete":true})
  reply(model,[{"id":1,"text_complete":false}]);reply(model,[{"id":1,"text_complete":false}])
  assert(model.accept(model.generation,model.epoch,page))
  late=model.generation
  if reset_kind=="epoch":model.set_epoch(model.epoch+1)
  else:model.reject(late)
  assert(model._text_bytes.is_empty() and model._text.is_empty() and not model.complete)
  assert(not model.accept(late,model.epoch,last))
 model.set_epoch(initial_epoch)

func group_reply(cursor:int,reports:Array,units:Array=[],total:int=303) -> Dictionary:
 return {"view":6,"notification_category":20,"alert_button":false,"list_revision":91,"cursor":cursor,"next_cursor":cursor+reports.size()+units.size() if cursor+reports.size()+units.size()<total else 0,"total":total,"reports":reports,"units":units}
func group_snapshot() -> void:
 var model=Model.new();model.open({"category":20,"report_ids":[999],"report_count":303,"complete":false})
 assert(model.pending.request.view==6 and model.pending.request.notification_category==20 and model.pending.request.expected_list_revision==0)
 var cursor:=0
 while cursor<301:
  var rows:Array=[]
  for i in range(cursor,mini(cursor+64,301)):
   var id:int=75 if i==300 else i
   rows.append({"id":id,"text":"a" if id==75 else "Fixture %d"%id,"color":3,"text_complete":id!=75})
  var units:Array=[{"unit_id":17,"category":1},{"unit_id":17,"category":1}] if cursor+rows.size()==301 else []
  var page:Dictionary=group_reply(cursor,rows,units)
  if cursor==64:
   var requested:Dictionary=model.pending.request.duplicate(true)
   model.reject(model.generation);assert(model.read_retry_needed and model._staged.size()==64)
   assert(model.retry_read() and model.pending.request==requested and not model.read_retry_needed)
  for key in ["notification_category","cursor","next_cursor"]:
   var bad:Dictionary=page.duplicate(true);bad[key]=int(bad[key])+1
   assert(not model.accept(model.generation,model.epoch,bad))
  if cursor>0:
   var bad:Dictionary=page.duplicate(true);bad.list_revision=92
   assert(not model.accept(model.generation,model.epoch,bad))
   bad=page.duplicate(true);bad.total=304
   assert(not model.accept(model.generation,model.epoch,bad))
  assert(model.accept(model.generation,model.epoch,page));cursor+=rows.size()
  assert(not model.loaded and model.rows.is_empty())
 assert(model.pending.mode=="unit_text" and model.pending.request.notification_category==20 and model.pending.request.expected_list_revision==91)
 assert(not model.pending.request.has("unit_id"))
 var page:Dictionary={"view":5,"tab":0,"notification_category":20,"alert_button":false,"list_revision":91,"cursor":0,"next_cursor":16383,"total":16391,"reports":[{"id":75,"text":"a".repeat(16383),"color":3,"text_complete":false}]}
 var bad:Dictionary=page.duplicate(true);bad.erase("notification_category")
 assert(not model.accept(model.generation,model.epoch,bad))
 assert(model.accept(model.generation,model.epoch,page))
 model.reject(model.generation);assert(model.retry_read())
 assert(model.pending.request.cursor==0 and model.pending.request.expected_list_revision==91)
 assert(model.accept(model.generation,model.epoch,page))
 page.cursor=16383;page.next_cursor=0;page.reports[0].text="☺ TAIL"
 assert(model.accept(model.generation,model.epoch,page))
 assert(model.complete and model.rows.size()==303 and model.rows[75].data==model.rows[300].data)
 assert(model.rows[75].data.text=="a".repeat(16383)+"☺ TAIL")
 assert(is_same(model.rows[75].data,model.rows[300].data))
 var parent:Array=model.rows.duplicate(true)
 assert(model.open_unit(17,1))
 assert(model.accept(model.generation,model.epoch,{"view":3,"unit_id":17,"unit_category":1,"list_revision":18,"reports":[{"id":999,"text_complete":true}]}))
 model.back();assert(model.rows==parent and model._group_revision==91 and model.pending.is_empty())
 # Closing or changing epochs while pages are pending cannot publish late data.
 for reset_kind in ["close","epoch","reject"]:
  model.open({"category":20})
  assert(model.accept(model.generation,model.epoch,group_reply(0,[{"id":1,"text":"a","color":3,"text_complete":false}],[],1)))
  var late:int=model.generation;var session:int=model.epoch
  if reset_kind=="close":model.close()
  elif reset_kind=="epoch":model.set_epoch(model.epoch+1)
  else:model.reject(late)
  assert(model._unit_text==null and not model.complete)
  assert(not model.accept(late,session,page))
 # Once a units page starts, later report rows would violate native group order.
 model.open({"category":20})
 assert(model.accept(model.generation,model.epoch,group_reply(0,[],[{"unit_id":17,"category":1}],2)))
 assert(not model.accept(model.generation,model.epoch,group_reply(1,[{"id":1,"text_complete":true}],[],2)))
 model.open({"alert_button":true})
 assert(model.pending.request.alert_button and model.pending.request.notification_category==-1)
 var empty:Dictionary=group_reply(0,[],[],0);empty.notification_category=-1;empty.alert_button=true
 assert(model.accept(model.generation,model.epoch,empty));assert(model.complete and model.rows.is_empty())

func recovery_controller() -> void:
 var world=FakeWorld.new();var service=Service.new();service.configure(world);service.poll()
 var owner=Controller.new();owner.configure(service)
 owner.state.open({"category":20});service.poll()
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Rejected,"action":34}
 service.poll();assert(owner.state.read_retry_needed and owner.ticket==0)
 owner.poll_recovery(0.49);service.poll();assert(world.calls.size()==1)
 owner.poll_recovery(0.01);service.poll();assert(world.calls.size()==2 and world.calls[1].request==world.calls[0].request)
 world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Ok,"action":34,"report":group_reply(0,[],[],0)}
 service.poll();assert(owner.state.complete and not owner.state.read_retry_needed)
 owner.poll_recovery(60);service.poll();assert(world.calls.size()==2)
 owner.state.open({"category":20});service.poll()
 world.snapshot={"world_epoch":5,"revision":4,"request_seq":3,"status":Status.Rejected,"action":34}
 service.poll();owner.poll_recovery(0.5);owner.state.close();service.poll()
 assert(world.calls.size()==3 and owner.ticket==0 and not owner.state.read_retry_needed)
 owner.shutdown();owner.free();service.free()

func recovery_lifecycle() -> void:
 # A read timeout queues recovery but cannot overwrite the undrained receipt.
 var world=FakeWorld.new();var service=Service.new();service.configure(world);service.poll()
 service.timeout_seconds=1.0
 var owner=Controller.new();owner.configure(service)
 owner.state.open({"category":20});service.poll();service.poll(1.1)
 assert(owner.state.read_retry_needed and owner.ticket==0 and world.calls.size()==1)
 owner.poll_recovery(0.5);service.poll()
 assert(owner.ticket!=0 and world.calls.size()==1)
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Ok,"action":34,"report":group_reply(0,[],[],0)}
 service.poll()
 assert(world.calls.size()==2 and owner.state.rows.is_empty() and not owner.state.pending.is_empty())
 world.snapshot.revision=3;world.snapshot.request_seq=2
 service.poll();assert(owner.state.complete)
 owner.shutdown();owner.free();service.free()
 # Every session invalidation cancels a retry queued behind an unknown read.
 for reset_kind in ["transport","epoch","generation"]:
  world=FakeWorld.new();service=Service.new();service.configure(world);service.poll()
  service.timeout_seconds=1.0;owner=Controller.new();owner.configure(service)
  owner.state.open({"category":20});service.poll();service.poll(1.1)
  owner.poll_recovery(0.5);service.poll();assert(world.calls.size()==1 and owner.ticket!=0)
  if reset_kind=="transport":world.snapshot={"transport_alive":false}
  elif reset_kind=="epoch":world.snapshot={"world_epoch":6,"revision":1,"status":0}
  else:world.generation+=1
  service.poll()
  assert(not owner.state.opened and owner.ticket==0 and not owner.state.read_retry_needed)
  # Even an old successful receipt after invalidation cannot publish rows.
  world.snapshot={"world_epoch":6,"revision":3,"request_seq":1,"status":Status.Ok,"action":34,"report":group_reply(0,[],[],0)}
  service.poll();owner.poll_recovery(0.5);service.poll()
  assert(not owner.state.opened and owner.state.rows.is_empty())
  for call in world.calls.slice(1):assert(int(call.request.action)==0)
  owner.shutdown();owner.free();service.free()
