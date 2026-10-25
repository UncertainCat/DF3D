extends SceneTree
var world
var failures=[]
func _initialize():call_deferred('run')
func check(ok,message):
 if not ok:failures.append(message);push_error(message)
func settle(seconds):
 world.set_replay_elapsed(seconds)
 for frame in 6000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0:return
  await process_frame
 check(false,'roller page scene failed to settle')
func inspect(mode,phase):
 var state={'pages':{},'slots':{},'meshes':{}}
 var level=world.get_building_root().get_node_or_null('level_0')
 check(level!=null,'missing roller level')
 if level==null:return state
 var count=0
 for cell in 300:
  var id=(3000 if mode==3 else 2000 if mode==2 and cell%2==0 else 1000)+cell
  var node=level.get_node_or_null('building_'+str(id))
  if mode==1 and cell%2==0:
   check(node==null,'removed roller remains');continue
  check(node!=null,'missing roller '+str(id));if node==null:continue
  count+=1;check(node.layers==0,'roller not in batch')
  var mesh=node.mesh;state.meshes[id]=mesh.get_instance_id()
  var material=mesh.surface_get_material(0)
  var texture=material.get_shader_parameter('machine_positions')
  check(texture!=null,'missing position texture');if texture==null:continue
  var page=texture.get_instance_id();state.pages[page]=true
  var payload=mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM2]
  var slot=int(payload[2]*256);var key=str(page)+':'+str(slot)
  check(not state.slots.has(key),'two rollers share one animation slot');state.slots[key]=id
  var expected_phase=1 if mode==2 and cell%2==1 else phase
  check(roundi(texture.get_image().get_pixel(slot,0).r)==(cell+expected_phase)%256-128,'wrong per-building phase '+str(id))
 check(count==(150 if mode==1 else 300),'wrong roller count')
 check(state.pages.size()==2,'position storage failed page boundary/reuse')
 return state
func shot():
 for frame in 3:await process_frame;await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func keys(d):
 var result=d.keys();result.sort();return result
func run():
 root.size=Vector2i(640,480)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(''),'assets')
 var fixture=ProjectSettings.globalize_path('res://../../../build/roller-pages.df3dfix')
 check(world.load_fixture(fixture),'fixture');world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(12,40,9.5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
 await settle(0);var initial=inspect(0,0);var first=await shot()
 await settle(1);var changed=inspect(0,1);var second=await shot()
 check(initial.meshes==changed.meshes,'phase updates rebuilt geometry')
 check(initial.slots==changed.slots,'phase updates reallocated slots')
 check(first!=second,'page-backed animation not visible')
 await settle(2);var half=inspect(1,1)
 for id in half.meshes:check(half.meshes[id]==changed.meshes[id],'removal rebuilt another roller')
 await settle(3);var reused=inspect(2,2)
 check(keys(initial.slots)==keys(reused.slots),'new rollers did not reuse released slots')
 for id in half.meshes:check(reused.meshes[id]==half.meshes[id],'reuse rebuilt surviving roller')
 await settle(4)
 var level=world.get_building_root().get_node_or_null('level_0')
 if level!=null:
  for node in level.get_children():check(not node.name.begins_with('building_'),'all-removed retained a roller')
 await settle(5);var restored=inspect(3,3)
 check(keys(initial.slots)==keys(restored.slots),'complete churn grew page storage')
 await settle(6);var final=inspect(3,4)
 check(restored.meshes==final.meshes,'reused pages rebuilt for phase')
 var epoch=world.session_generation()
 check(world.load_fixture(fixture),'reload');await settle(0);var reloaded=inspect(0,0)
 check(world.session_generation()!=epoch,'reload retained session')
 for page in reloaded.pages:check(not initial.pages.has(page),'reload reused stale page texture')
 check(await shot()==first,'reload retained old phases')
 world.free();camera.free();await process_frame
 print('ROLLER_PAGES_PASS' if failures.is_empty() else 'ROLLER_PAGES_FAIL');quit(0 if failures.is_empty() else 1)
