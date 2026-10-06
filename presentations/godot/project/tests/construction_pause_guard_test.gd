extends SceneTree
const Guard=preload("res://scripts/construction_pause_guard.gd")
class Source:
 extends Node
 var paused:=false
 var live:=true
 var epoch:=5
 var generation:=1
 var calls:Array=[]
 var notice:=0
 func is_live():return live
 func session_generation():return generation
 func poll_session():return {"paused":paused,"fortress_valid":true,"fortress_epoch":epoch,"interruption":{"kind":notice}}
 func send_set_pause(value):calls.append(value);return calls.size()
class CompletionService:
 extends Node
 signal completed(ticket:int,result:Dictionary)
var failures:=0
func check(ok:bool,label:String):
 if not ok:failures+=1;push_error(label)
func ack(g,w):
 w.paused=w.calls.back();g.receive([{"seq":w.calls.size(),"status":0}])
func _initialize():call_deferred("run")
func run():
 var w:=Source.new();var g:=Guard.new();g.world=w
 var service:=CompletionService.new();g._service=service
 check(not service.completed.has_connections(),"Idle guard does not request copies of read payloads")
 g.mutation_ticket=7
 check(service.completed.has_connections(),"Submitted mutation retains a completion observer")
 service.completed.emit(7,{"outcome":"unknown"})
 check(service.completed.has_connections(),"Unknown mutation keeps draining its receipt")
 service.completed.emit(7,{"status":2})
 check(not service.completed.has_connections(),"Confirmed mutation disconnects its observer")
 var observed:Array=[]
 var done:=func(ok):observed.append(ok)
 g.acquire(done)
 check(observed.is_empty() and w.calls==[true],"No material query before pause receipt")
 g.receive([{"seq":1,"status":0}])
 check(observed.is_empty(),"Receipt without matching session readback cannot start lookup")
 w.paused=true;g._process(0.01)
 check(observed==[true] and g.held,"Confirmed acquisition")
 g.mutation_ticket=9;g.release()
 check(w.calls==[true],"Cancel cannot resume during submitted Place")
 g._completed(9,{"outcome":"unknown"});check(w.calls==[true],"Unknown placement is not replayed/resumed")
 g._completed(9,{"status":2});check(w.calls==[true,false],"Late confirmed placement releases hold once")
 ack(g,w)
 g.acquire(done);g.release();check(w.calls==[true,false,true],"Cancel while pause in flight defers restoration")
 ack(g,w);check(w.calls==[true,false,true,false],"Cancelled late pause receipt restores running")
 g.acquire(done);check(w.calls.size()==4,"Reopen waits for old resume receipt")
 ack(g,w);check(w.calls==[true,false,true,false,true],"Reopen reacquires after restoration")
 ack(g,w);g.explicit_pause(true);g.release()
 check(w.calls.size()==5 and w.paused,"Explicit pause preserves player intent")
 g.acquire(done);g.release();check(w.calls.size()==5,"Already paused fortress remains paused")
 w.paused=false;g.acquire(done);w.epoch=6;ack(g,w)
 check(w.calls.size()==6 and not g.held,"Epoch change never resumes replacement fortress")
 w.paused=false;g.acquire(done);g._process(16)
 check(observed.back()==false,"Acquisition timeout fails closed")
 ack(g,w);check(w.calls.back()==false,"Late pause receipt reconciles without retry")
 ack(g,w);g.acquire(done);ack(g,w);w.notice=2;g.release()
 check(w.calls.back()==true,"Native interruption retains pause authority")
 g.free();w.free();service.free()
 if failures==0:print("CONSTRUCTION_PAUSE_GUARD_PASS")
 quit(0 if failures==0 else 1)
