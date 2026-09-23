-- Before/after guard probe state fingerprint. No save operation is issued.
local mode=...
local p=df3d_designation_acceptance[1].tile
local world=df.global.world;local width,height=world.map.x_count-2,world.map.y_count-2
local layers=math.floor(65536/(width*height))+1
local hash=2166136261
for z=p.z,p.z+layers-1 do for x=1,width do for y=1,height do
 local b=dfhack.maps.getTileBlock(x,y,z)
 if b then
  hash=((hash ~ b.designation[x%16][y%16].whole)*16777619)&0xffffffff
  hash=((hash ~ b.occupancy[x%16][y%16].whole)*16777619)&0xffffffff
 end
end end end
if mode=='before' then df3d_guard_before={hash=hash,paused=df.global.pause_state,frame=world.frame_counter};print('GUARD_BASELINE '..hash)
else
 assert(hash==df3d_guard_before.hash,'rejected commands mutated designation/occupancy region')
 assert(df.global.pause_state and df3d_guard_before.paused,'pause state changed')
 assert(world.frame_counter==df3d_guard_before.frame,'simulation advanced')
 print('GUARD_NATIVE_UNCHANGED hash='..hash..' paused=true frame='..world.frame_counter)
end
