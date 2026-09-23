extends SceneTree
var world
var directory: String
func _initialize():
 call_deferred("run")
func run():
 directory=OS.get_environment("DF3D_DESIGNATION_ACCEPTANCE")
 var cases=JSON.parse_string(FileAccess.get_file_as_string(directory+"/cases.json"))
 world=Df3dWorld.new()
 root.add_child(world)
 if not world.attach():
  push_error("Bridge attach failed")
  quit(1)
  return
 var initial_deadline=Time.get_ticks_msec()+30000
 while not world.terrain_loaded() and Time.get_ticks_msec()<initial_deadline:
  world.poll()
  await create_timer(0.01).timeout
 if not world.terrain_loaded():
  push_error("Presented world epoch not ready")
  quit(1)
  return
 for index in range(cases.size()):
  var c=cases[index]
  var p=c.tile
  var rect=Rect2i(int(p.x),int(p.y),int(c.get("width",1)),1)
  if c.get("check_track_job",false):
   var track_deadline=Time.get_ticks_msec()+20000
   var track_found=false
   while Time.get_ticks_msec()<track_deadline:
    world.poll()
    for entry in world.designation_tiles(int(p.z)):
     if entry.tile==Vector3i(int(p.x),int(p.y),int(p.z)) and int(entry.get("track",0))==12 and int(entry.kind)==0:
      track_found=true
    if track_found: break
    await create_timer(0.02).timeout
   if not track_found:
    push_error("Pending track job was not published as track12 without smooth")
    quit(1)
    return
   print("TRACK_JOB_PUBLICATION PASS track12 kind0")
  var seq:int=0
  match c.method:
   "dig": seq=world.designate_dig(rect,int(p.z),int(c.kind),int(c.priority),bool(c.marker),int(c.get("mining_mode",0)),int(c.get("max_z",-1)))
   "smooth": seq=world.designate_smooth(rect,int(p.z),int(c.kind),int(c.priority),bool(c.marker),int(c.get("max_z",-1)))
   "track": seq=world.designate_track(rect,int(p.z),false,false,int(c.priority),bool(c.marker))
   "stairs": seq=world.designate_stairs(rect,int(p.z),int(c.z2),int(c.priority),bool(c.marker))
   "chop": seq=world.designate_chop(rect,int(p.z),true,int(c.priority),bool(c.marker))
   "gather": seq=world.designate_gather(rect,int(p.z),true,int(c.priority),bool(c.marker))
  if seq==0 and int(c.get("status",0))==0:
   push_error("Command send failed: "+c.name)
   quit(1)
   return
  var deadline=Time.get_ticks_msec()+15000
  var accepted=seq==0 and int(c.get("status",0))!=0
  while not accepted and Time.get_ticks_msec()<deadline:
   world.poll()
   for result in world.drain_command_results():
    if int(result.seq)==seq:
     print("ACCEPTANCE ",c.name," ",result)
     if int(result.status)!=int(c.get("status",0)):
      quit(1)
      return
     accepted=true
   if accepted: break
   await create_timer(0.01).timeout
  if not accepted:
   push_error("Command timed out: "+c.name)
   quit(1)
   return
  var f=FileAccess.open(directory+"/verify.txt",FileAccess.WRITE)
  f.store_string(str(index+1))
  f.close()
  deadline=Time.get_ticks_msec()+15000
  while not FileAccess.file_exists(directory+"/ack-"+str(index+1)) and Time.get_ticks_msec()<deadline:
   world.poll()
   await create_timer(0.02).timeout
  if not FileAccess.file_exists(directory+"/ack-"+str(index+1)):
   push_error("Native verification timed out")
   quit(1)
   return
 print("DESIGNATION ACCEPTANCE PASS ",cases.size())
 quit(0)
