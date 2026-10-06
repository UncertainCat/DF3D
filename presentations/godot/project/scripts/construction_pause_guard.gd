extends Node
# Native DF freezes simulation during material selection. Own a confirmed,
# temporary pause through the existing semantic pause command, never UI state.
# Unknown/lost outcomes must not resume a different session or replay a command.
var world
var sequence := 0
var epoch := 0
var generation := 0
var held := false
var restore_running := false
var wanted := false
var restoring := false
var elapsed := 0.0
var acknowledged := false
var observer := Callable()
var _service
var mutation_ticket := 0:
 set(value):
  mutation_ticket=value
  if not is_instance_valid(_service):return
  # Only mutations need a detached completion observer. Copying every large
  # material-list receipt for an idle guard wasted main-thread work.
  if value!=0 and not _service.completed.is_connected(_completed):_service.completed.connect(_completed)
  elif value==0 and _service.completed.is_connected(_completed):_service.completed.disconnect(_completed)

func configure(source, interaction, service) -> void:
 world=source
 interaction.command_results_received.connect(receive)
 interaction.pause_requested.connect(explicit_pause)
 _service=service

func same_session() -> bool:
 return world.is_live() and int(world.session_generation())==generation and int(world.poll_session().get("fortress_epoch",0))==epoch

func acquire(callback:Callable) -> void:
 wanted=true;observer=callback
 if held and same_session(): _notify(true);return
 if sequence!=0:return
 var state:Dictionary=world.poll_session()
 if not world.is_live() or not state.get("fortress_valid",false):_notify(false);return
 epoch=int(state.get("fortress_epoch",0));generation=int(world.session_generation())
 restore_running=not bool(state.get("paused",true))
 if not restore_running:held=true;_notify(true);return
 sequence=int(world.send_set_pause(true));elapsed=0.0;acknowledged=false
 if sequence==0:restore_running=false;_notify(false)

func _notify(ok:bool) -> void:
 var callback:=observer;observer=Callable()
 if callback.is_valid():callback.call(ok)

func release() -> void:
 wanted=false;observer=Callable()
 if sequence!=0 or mutation_ticket!=0:return
 if held and restore_running and same_session():
  # A native interruption has its own pause authority.
  var notice:Dictionary=world.poll_session().get("interruption",{})
  if int(notice.get("kind",0))<=1:
   sequence=int(world.send_set_pause(false));restoring=sequence!=0;elapsed=0.0;acknowledged=false
 held=false;restore_running=false

func abandon() -> void:
 wanted=false;held=false;restore_running=false;sequence=0;restoring=false;mutation_ticket=0
 _notify(false)

func explicit_pause(_paused:bool) -> void:
 # Player/Reports pause intent supersedes our saved running preference.
 restore_running=false

func _completed(ticket:int,result:Dictionary) -> void:
 if ticket!=mutation_ticket or result.get("outcome","")=="unknown":return
 mutation_ticket=0
 if not wanted:release()

func receive(results:Array) -> void:
 for result in results:
  if sequence==0 or int(result.get("seq",0))!=sequence:continue
  if not same_session():abandon();return
  if int(result.get("status",-1))!=0:
   sequence=0;restoring=false;restore_running=false;_notify(false);return
  acknowledged=true;_settle()

func _settle() -> void:
 if sequence==0 or not acknowledged:return
 # Command receipts and session snapshots are published separately. Require
 # the matching pause readback before querying items or reacquiring a hold.
 if bool(world.poll_session().get("paused",restoring))==restoring:return
 sequence=0;acknowledged=false
 if restoring:
  restoring=false
  if wanted:
   var callback:=observer;observer=Callable();acquire(callback)
 elif wanted:
  held=true;_notify(true)
 else:
  held=true;release()

func _process(delta:float) -> void:
 if not held and sequence==0:return
 if not same_session():abandon();return
 _settle()
 if sequence!=0:
  elapsed+=delta
  if elapsed>=15.0 and observer.is_valid():
   wanted=false;_notify(false) # Retain sequence; reconcile a late receipt once.
