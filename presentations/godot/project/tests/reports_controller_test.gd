extends SceneTree
const Service=preload("res://scripts/semantic_action_service.gd")
const Status=preload("res://scripts/management_contract.gd").ManagementStatus
const Controller=preload("res://scripts/reports_controller.gd")
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
  calls.append({"domain":domain,"request":request.duplicate(true)})
  return calls.size()
func _initialize() -> void:
 var world:=FakeWorld.new();var service:=Service.new();service.configure(world)
 var owner:=Controller.new();owner.configure(service);owner.state.open()
 service.poll();assert(world.calls.size()==1 and world.calls[0].domain=="reports")
 var counts:Array=[];counts.resize(25);counts.fill(1)
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Ok,"action":34,"report":{"view":1,"list_revision":17,"tab":1,"reports":[{"id":10}],"tab_counts":counts}}
 service.poll();assert(owner.state.rows==[{"id":10}] and owner.ticket==0)
 # Restoring a cached tab cancels a queued read without issuing another read.
 owner.state.choose_tab(2);owner.state.choose_tab(1);service.poll()
 assert(world.calls.size()==1 and owner.ticket==0 and owner.state.rows==[{"id":10}])
 # A new selection detaches a queued request before it reaches the producer.
 owner.state.choose_tab(2);owner.state.choose_tab(3);service.poll()
 assert(world.calls.size()==2 and world.calls[1].request.tab==3)
 # Closing while sent detaches the observer; its late receipt cannot reopen rows.
 owner.state.close();world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Ok,"action":34,"report":{"view":1,"list_revision":17,"tab":3,"reports":[{"id":11}],"tab_counts":counts}}
 service.poll();assert(not owner.state.opened and owner.state.rows.is_empty())
 owner.state.open();service.poll();assert(world.calls.size()==3)
 # DF epoch transition invalidates the owner before any old callback can apply.
 world.snapshot={"world_epoch":6,"revision":1,"status":0};service.poll()
 assert(not owner.state.opened and owner.state.rows.is_empty() and owner.ticket==0)
 owner.state.open();service.poll();assert(world.calls.size()==4)
 world.snapshot={"world_epoch":6,"revision":2,"request_seq":4,"status":Status.Rejected,"action":34}
 service.poll();assert(owner.state.pending.is_empty() and owner.state.rows.is_empty())
 # Begin a separate metadata fixture after verifying the failed ordinary demand.
 assert(not owner.state.read_retry.is_empty());owner.state.read_retry={}
 # Metadata uses the raw unit-log length, independent of retained report count.
 owner.state.unit_id=2905;owner.state.unit_category=1;owner.state.unit_log_length=9891;owner.state.log_revision=71
 owner.state.pause_on_new=true
 var pauses:Array=[];owner.state.pause_requested.connect(func():pauses.append(true))
 var changes:Array=[];owner.log_changed.connect(func():changes.append(true))
 owner.poll_metadata(0.49);assert(owner.metadata_ticket==0)
 owner.poll_metadata(0.01);service.poll();assert(world.calls.size()==5)
 assert(world.calls[4].request=={"action":34,"view":2,"unit_id":2905,"unit_category":1})
 owner.poll_metadata(1.0);service.poll();assert(world.calls.size()==5)
 world.snapshot={"world_epoch":6,"revision":3,"request_seq":5,"status":Status.Ok,"action":34,"report":{"view":2,"unit_category":1,"units":[{"unit_id":2905,"category":1,"log_count":9892,"retained_count":697}]}}
 service.poll();assert(pauses==[true] and changes==[true] and owner.state.unit_log_length==9892)
 var metadata:Dictionary=world.snapshot.duplicate(true)
 service.poll();assert(world.calls.size()==6 and world.calls[5].request.view==3)
 world.snapshot={"world_epoch":6,"revision":4,"request_seq":6,"status":Status.Ok,"action":34,"report":{"view":3,"list_revision":71,"unit_id":2905,"unit_category":1,"reports":[{"id":42}],"total":1}}
 service.poll();assert(owner.state.rows==[{"id":42}] and owner.state.pending.is_empty())
 world.snapshot=metadata
 owner.poll_metadata(0.5);service.poll()
 world.snapshot.revision=5;world.snapshot.request_seq=7
 service.poll();assert(pauses.size()==1 and changes.size()==1)
 # Wrong row identity cannot masquerade as the currently observed log.
 owner.poll_metadata(0.5);service.poll()
 world.snapshot.revision=6;world.snapshot.request_seq=8
 world.snapshot.report.units[0].unit_id=999;world.snapshot.report.units[0].log_count=9893
 service.poll();assert(owner.state.unit_log_length==9892 and pauses.size()==1)
 # A sent observation is detached on close; its eventual reply has no effect.
 owner.poll_metadata(0.5);service.poll();owner.state.close()
 world.snapshot.revision=7;world.snapshot.request_seq=9;world.snapshot.report.units[0].unit_id=2905
 service.poll();assert(owner.metadata_ticket==0 and pauses.size()==1)
 owner.shutdown();owner.free();service.free()
 initial_recovery();recovery();recovery_lifecycle();bootstrap_claim();print("REPORTS_CONTROLLER_PASS");quit()

func recovery() -> void:
 var world:=FakeWorld.new();var service:=Service.new();service.configure(world);service.poll()
 var owner:=Controller.new();owner.configure(service)
 owner.state.opened=true;owner.state.unit_id=71;owner.state.unit_category=1
 owner.state.unit_log_length=100;owner.state.log_revision=71;owner.state.pause_on_new=true;owner.state.rows=[{"id":99}];owner.state.total=1
 var pauses:Array=[];owner.state.pause_requested.connect(func():pauses.append(true))
 owner.poll_metadata(0.5);service.poll()
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Ok,"action":34,"report":{"view":2,"unit_category":1,"units":[{"unit_id":71,"category":1,"log_count":101}]}}
 service.poll();service.poll();assert(world.calls.size()==2 and pauses.size()==1)
 world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Rejected,"action":34}
 service.poll();assert(owner.state.log_refresh_needed and owner.ticket==0)
 owner.poll_metadata(0.49);assert(owner.ticket==0)
 owner.poll_metadata(0.01);service.poll()
 assert(world.calls.size()==3 and world.calls[2].request==world.calls[1].request and pauses.size()==1)
 world.snapshot={"world_epoch":5,"revision":4,"request_seq":3,"status":Status.Ok,"action":34,"report":{"view":3,"list_revision":71,"unit_id":71,"unit_category":1,"reports":[{"id":100}],"total":2}}
 service.poll();assert(not owner.state.log_refresh_needed and owner.state.rows.size()==2 and pauses.size()==1)
 owner.state.refresh_new_reports();owner.state.close();service.poll()
 assert(world.calls.size()==3 and not owner.state.log_refresh_needed)
 owner.shutdown();owner.free();service.free()

func initial_recovery() -> void:
 var world:=FakeWorld.new();var service:=Service.new();service.configure(world);service.poll()
 var owner:=Controller.new();owner.configure(service)
 owner.state.opened=true;owner.state.rows=[{"unit_id":71,"category":1,"log_count":100}]
 var pauses:Array=[];owner.state.pause_requested.connect(func():pauses.append(true))
 owner.state.pause_on_new=true
 assert(owner.state.open_unit(71,1));service.poll()
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Rejected,"action":34}
 service.poll();assert(owner.state.log_initial_needed and owner.state.log_revision==0 and owner.ticket==0)
 owner.poll_metadata(0.49);service.poll();assert(world.calls.size()==1)
 owner.poll_metadata(0.01);service.poll()
 assert(world.calls.size()==2 and world.calls[1].request.view==3 and world.calls[1].request.from_end and world.calls[1].request.expected_list_revision==0)
 assert(not world.calls[1].request.get("refresh",false) and pauses.is_empty())
 world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Ok,"action":34,"report":{"view":3,"unit_id":71,"unit_category":1,"list_revision":17,"reports":[],"total":0}}
 service.poll();assert(not owner.state.log_initial_needed and owner.state.log_revision==17 and owner.state.rows.is_empty())
 # A queued initial retry is detached on close and cannot reopen the screen.
 owner.state.rows=[{"unit_id":71,"category":1}];owner.state.open_unit(71,1);service.poll()
 world.snapshot={"world_epoch":5,"revision":4,"request_seq":3,"status":Status.Rejected,"action":34}
 service.poll();owner.poll_metadata(0.5);owner.state.close();service.poll()
 assert(world.calls.size()==3 and not owner.state.log_initial_needed and owner.ticket==0)
 owner.shutdown();owner.free();service.free()

func recovery_lifecycle() -> void:
 # A read timeout queues recovery but cannot overwrite the undrained receipt.
 var world=FakeWorld.new();var service=Service.new();service.configure(world);service.poll()
 service.timeout_seconds=1.0
 var owner=Controller.new();owner.configure(service)
 owner.state.open();service.poll();service.poll(1.1)
 assert(not owner.state.read_retry.is_empty() and owner.ticket==0 and world.calls.size()==1)
 owner.poll_metadata(0.5);service.poll()
 assert(owner.ticket!=0 and world.calls.size()==1)
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Ok,"action":34,"report":{"view":1,"tab":1,"list_revision":17,"reports":[{"id":10,"text_complete":true}],"total":1}}
 service.poll()
 assert(world.calls.size()==2 and owner.state.rows.is_empty() and not owner.state.pending.is_empty())
 world.snapshot.revision=3;world.snapshot.request_seq=2
 service.poll();assert(owner.state.rows==[{"id":10,"text_complete":true}])
 owner.shutdown();owner.free();service.free()
 # Every session invalidation cancels a retry queued behind an unknown read.
 for reset_kind in ["transport","epoch","generation"]:
  world=FakeWorld.new();service=Service.new();service.configure(world);service.poll()
  service.timeout_seconds=1.0;owner=Controller.new();owner.configure(service)
  owner.state.open();service.poll();service.poll(1.1)
  owner.poll_metadata(0.5);service.poll();assert(world.calls.size()==1 and owner.ticket!=0)
  if reset_kind=="transport":world.snapshot={"transport_alive":false}
  elif reset_kind=="epoch":world.snapshot={"world_epoch":6,"revision":1,"status":0}
  else:world.generation+=1
  service.poll()
  assert(not owner.state.opened and owner.ticket==0 and owner.state.read_retry.is_empty())
  # Even an old successful receipt after invalidation cannot publish rows.
  world.snapshot={"world_epoch":6,"revision":3,"request_seq":1,"status":Status.Ok,"action":34,"report":{"view":1,"tab":1,"list_revision":17,"reports":[{"id":10,"text_complete":true}],"total":1}}
  service.poll();owner.poll_metadata(0.5);service.poll()
  assert(not owner.state.opened and owner.state.rows.is_empty())
  for call in world.calls.slice(1):assert(int(call.request.action)==0)
  owner.shutdown();owner.free();service.free()

func bootstrap_claim() -> void:
 var world=FakeWorld.new();var service=Service.new();service.configure(world,true)
 var owner=Controller.new();owner.configure(service);owner.state.open()
 service.poll();assert(world.calls.size()==1 and world.calls[0].request.action==0)
 world.snapshot={"world_epoch":5,"revision":2,"request_seq":1,"status":Status.Rejected,"action":0}
 service.poll();service.poll(0.49);assert(world.calls.size()==1)
 service.poll(0.02);assert(world.calls.size()==2 and world.calls[1].request.action==0)
 world.snapshot={"world_epoch":5,"revision":3,"request_seq":2,"status":Status.Ok,"action":0}
 service.poll();assert(world.calls.size()==3 and world.calls[2].request.view==1)
 world.snapshot={"world_epoch":6,"revision":1,"status":0}
 service.poll();assert(not owner.state.opened and world.calls.size()==4 and world.calls[3].request.action==0)
 world.snapshot={"world_epoch":6,"revision":2,"request_seq":4,"status":Status.Ok,"action":0}
 service.poll();assert(world.calls.size()==4)
 owner.state.open();service.poll();assert(world.calls.size()==5 and world.calls[4].request.view==1)
 world.generation+=1;service.poll();assert(not owner.state.opened)
 service.poll();assert(world.calls.size()==6 and world.calls[5].request.action==0)
 owner.shutdown();owner.free();service.free()
