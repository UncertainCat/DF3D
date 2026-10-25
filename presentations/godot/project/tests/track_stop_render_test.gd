extends SceneTree
const SourceMesh=preload("res://tests/source_mesh.gd")
var world
var failures=[]
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
 if not ok:failures.append(message);push_error(message)
func settle(seconds:float):
 world.set_replay_elapsed(seconds)
 for frame in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0:return
  await process_frame
 check(false,"track stop scene failed to settle")
func shot():
 for frame in 3:await process_frame;await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func inspect(column:int,alpha:float,row:int=0):
 var node=world.get_building_root().get_node_or_null("level_0/building_100")
 check(node!=null,"missing track stop")
 if node==null:return 0
 var icon=world.selection_icon(3,100,false)
 var expected=world.ui_texture("BUILDING_ICON_TRACK_STOP",-1)
 check(icon!=null and expected!=null,"missing native track stop header icon")
 if icon!=null and expected!=null:
  check(icon.get_image().get_data()==expected.get_image().get_data(),"track stop header substituted world artwork")
 # Planned ghosts retain their separately sorted transparent draw.
 check(node.layers==(1 if alpha<1 else 0),"wrong track stop render ownership")
 check(SourceMesh.count(node.mesh)==1,"unexpected stop surfaces")
 var arrays=SourceMesh.arrays(node.mesh,0)
 var uv=arrays[Mesh.ARRAY_TEX_UV]
 var center=Vector2.ZERO
 for p in uv:center+=p
 center/=uv.size()
 check(absf(center.x*15-(column+0.5))<0.001,"wrong native sprite column "+str(column))
 check(absf(center.y*2-(row+0.5))<0.001,"wrong native wood/stone sprite row")
 for c in arrays[Mesh.ARRAY_COLOR]:
  check(c==Color.WHITE,"wrong track stop tint")
 if alpha<1:check(preload("res://tests/native_planned_pixels.gd").matches(node,"TrackStop"),"native planned Track Stop pixels")
 return node.mesh.get_instance_id()
func run():
 root.size=Vector2i(320,240)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(""),"assets load")
 check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/track-stop.df3dfix")),"fixture loads")
 world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(8.5,20,8.5)
 camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3;camera.current=true
 var columns=[10,0,0,0,1,4,2,7,1,5,3,6,1,9,8,10]
 var images={}
 var bare_floor_image
 var last_mesh=0
 for mask in 16:
  await settle(mask)
  last_mesh=inspect(columns[mask],1.0)
  var pixels=await shot()
  # Track remains visible through transparent parts of the stop sprite.
  if mask==0:bare_floor_image=pixels
  images[columns[mask]]=pixels
 check(images[0]!=images[1],"NS and WE images identical")
 await settle(16)
 check(inspect(10,1.0)==last_mesh,"unrelated track change rebuilt stop")
 await settle(17)
 inspect(10,0.5)
 check(await shot()!=images[10],"planned opacity not visible")
 await settle(18)
 inspect(10,1.0)
 check(await shot()==bare_floor_image,"cleared track did not restore crossing")
 await settle(19)
 inspect(10,1.0,1)
 var log_image=await shot()
 await settle(20)
 inspect(10,1.0)
 var wood_block_image=await shot()
 check(log_image!=wood_block_image,"wood block incorrectly uses log artwork")
 await settle(21)
 inspect(10,1.0)
 var stone_block_image=await shot()
 check(stone_block_image!=wood_block_image,"actual item material did not recolor sprite")
 await settle(22)
 inspect(10,1.0)
 check(await shot()==bare_floor_image,"unknown item retained previous palette")
 world.free();camera.free();await process_frame
 print("TRACK_STOP_RENDER_PASS" if failures.is_empty() else "TRACK_STOP_RENDER_FAIL")
 quit(0 if failures.is_empty() else 1)
