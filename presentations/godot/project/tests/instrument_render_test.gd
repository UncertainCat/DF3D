extends SceneTree
const SourceMesh=preload('res://tests/source_mesh.gd')
var failures=[]
var world
var hashes=[]
func _initialize():call_deferred('run')
func check(ok,message):
 if not ok:failures.append(message);push_error(message)
func settle(seconds):
 world.set_replay_elapsed(seconds)
 for frame in 4000:
  world.poll()
  if world.pending_block_count()==0 and world.building_pending_count()==0:return
  await process_frame
 check(false,'instrument scene failed to settle')
func inspect(family,placed,complete):
 var node=world.get_building_root().get_node_or_null('level_0/building_100')
 check(node!=null,'missing instrument')
 if node==null:return
 var icon=world.selection_icon(3,100,false)
 var expected_icon=world.ui_texture('BUILDING_ICON_INSTRUMENT',-1)
 check(icon!=null and expected_icon!=null,'missing instrument header')
 if icon!=null and expected_icon!=null:check(icon.get_image().get_data()==expected_icon.get_image().get_data(),'incorrect native instrument header')
 check(SourceMesh.count(node.mesh)==1,'surface count')
 var arrays=SourceMesh.arrays(node.mesh,0)
 var lo=Vector2(100,100);var hi=Vector2(-100,-100)
 for uv in arrays[Mesh.ARRAY_TEX_UV]:lo=lo.min(uv);hi=hi.max(uv)
 var column=[0,2,3,1][family] if complete and family>=0 else 0
 var row=1 if complete and family>=0 and placed==0 else 0
 var texture=SourceMesh.material(node.mesh,0).get_shader_parameter('sprite_tex')
 check(texture!=null,'missing instrument texture')
 if texture==null:return
 var image=texture.get_image()
 check(absf(lo.x*image.get_width()-column*32)<0.01 and absf(lo.y*image.get_height()-row*32)<0.01,'wrong native sprite origin')
 check(absf((hi.x-lo.x)*image.get_width()-32)<0.01 and absf((hi.y-lo.y)*image.get_height()-32)<0.01,'wrong sprite extent')
 var actual=image.get_region(Rect2i(column*32,row*32,32,32));actual.convert(Image.FORMAT_RGBA8);actual.clear_mipmaps()
 var expected_index=0 if family<0 else 1+family*4+placed*2+(1 if complete else 0)
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(actual.get_data())
 check(digest.finish().hex_encode()==hashes[expected_index],'wrong native artwork/palette')
 for color in arrays[Mesh.ARRAY_COLOR]:check(color==Color.WHITE,'wrong planned tint')
func shot():
 for frame in 3:await process_frame;await RenderingServer.frame_post_draw
 return root.get_texture().get_image().get_data()
func run():
 var evidence=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path('res://../../../fixtures/construction/instrument_rendering.json')))
 hashes=evidence.uploaded_rgba_sha256.values
 root.size=Vector2i(320,240)
 world=Df3dWorld.new();root.add_child(world);world.set_replay_speed(0)
 check(world.load_assets(''),'assets')
 var path=ProjectSettings.globalize_path('res://../../../build/instrument.df3dfix')
 check(world.load_fixture(path),'fixture');world.set_top_z(0);world.set_window_depth(1)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(8.5,20,8.5);camera.rotation=Vector3(-PI/2,0,0);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3;camera.current=true
 await settle(0);inspect(-1,-1,true);var empty=await shot()
 var images=[];var step=1
 for family in 4:for placed in 2:for complete in [false,true]:
  await settle(step);inspect(family,placed,complete);images.append(await shot());step+=1
 for i in range(2,16,2):check(images[0]==images[i],'planned placeholder changed')
 for i in [1,5,9,13]:check(images[i]!=images[i+2],'portable and placed artwork identical')
 await settle(17);inspect(-1,-1,true);check(await shot()==empty,'empty instrument retained prior artwork')
 await settle(18);check(world.get_building_root().get_node_or_null('level_0/building_100')==null,'removed instrument still present')
 await settle(19);inspect(-1,-1,true);check(await shot()==empty,'reused ID retained old artwork')
 check(world.load_fixture(path),'reload');await settle(2);inspect(0,0,true)
 check(await shot()==images[1],'reload retained stale appearance')
 world.free();camera.free();await process_frame
 print('INSTRUMENT_RENDER_PASS' if failures.is_empty() else 'INSTRUMENT_RENDER_FAIL');quit(0 if failures.is_empty() else 1)
