extends SceneTree
var world
var camera: Camera3D
var failures=[]
var views=[]
var references=[]
func _initialize():call_deferred("run")
func check(ok,message):
 if not ok:failures.append(message);push_error(message)
func settle():
 for frame in 5000:
  world.poll()
  if world.pending_block_count()==0 and world.mesh_batch_stats().terrain.pending==0:return
  await process_frame
 check(false,"terrain preparation settles")
func shot(view):
 world.set_top_z(view.x);world.set_window_depth(view.y)
 var size=world.map_size()
 var target=Vector3(size.x*.5,world.get_top_z(),size.z*.5)
 camera.position=target+Vector3(0,45,65);camera.look_at(target)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image();img.convert(Image.FORMAT_RGBA8)
 return img
func run():
 root.size=Vector2i(640,480);root.msaa_3d=Viewport.MSAA_DISABLED
 camera=Camera3D.new();root.add_child(camera);camera.current=true
 camera.far=1000
 world=Df3dWorld.new();root.add_child(world)
 check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"assets load")
 world.set_fixed_render_tick(preload("res://tests/recorded_fixture.gd").tick())
 check(world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")),"fixture loads")
 world.set_replay_speed(0);world.poll();await settle()
 for top in [0,14,15,16,17,30,31,32,preload("res://tests/recorded_fixture.gd").top_z()]:
  views.append(Vector2i(top,0))
 views.append(Vector2i(17,1));views.append(Vector2i(32,3))
 var before=world.mesh_batch_stats().terrain
 for view in views:references.append(await shot(view))
 var after=world.mesh_batch_stats().terrain
 check(before.builds==after.builds and before.invalidations==after.invalidations,"slice movement never rebuilds batches")
 world.set_mesh_batching_enabled(false)
 for i in views.size():
  var img=await shot(views[i]);var a=references[i].get_data();var b=img.get_data()
  var changed=0;var total_error=0
  for pixel in a.size()/4:
   var delta=maxi(absi(a[pixel*4]-b[pixel*4]),maxi(absi(a[pixel*4+1]-b[pixel*4+1]),absi(a[pixel*4+2]-b[pixel*4+2])))
   total_error+=delta
   if delta>8:changed+=1
  var ratio=float(changed)/(a.size()/4)
  print("SLAB_PIXELS ",views[i]," changed=",ratio," mean_error=",float(total_error)/(a.size()/4))
  check(ratio<0.002,"batch pixels match per-level source rendering at %s: %s" % [views[i],ratio])
  var out=OS.get_environment("DF3D_SLAB_CAPTURE")
  if not out.is_empty():
   references[i].save_png(out+"/batched_"+str(i)+".png");img.save_png(out+"/source_"+str(i)+".png")
 world.queue_free()
 for frame in 5:await process_frame
 print("TERRAIN_SLABS_PASS" if failures.is_empty() else "TERRAIN_SLABS_FAIL")
 quit(0 if failures.is_empty() else 1)
