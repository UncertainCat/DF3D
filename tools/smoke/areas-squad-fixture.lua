-- Paused, owned, unsaved diagnostic sessions only. Detached racks exercise
-- semantic membership without changing map occupancy or construction jobs.
local M={}
local function copy(values)local result={};for _,v in ipairs(values)do result[#result+1]=v end;return result end
function M.start(zone,ids)
 assert(df.global.pause_state and not _G.df3d_squad_racks)
 local state={zone=zone,squads={},racks={}}
 for _,id in ipairs(ids)do
  local s=assert(df.squad.find(id))
  state.squads[#state.squads+1]={squad=s,combat=copy(s.rack_combat),training=copy(s.rack_training)}
 end
 for i=1,2 do
  local rack=df.building_weaponrackst:new()
  rack.id=df.global.building_next_id;df.global.building_next_id=rack.id+1
  if i==1 then rack.relations:insert('#',zone)end
  df.global.world.buildings.other.WEAPON_RACK:insert('#',rack)
  state.racks[#state.racks+1]=rack
 end
 -- The unrelated rack starts as stale membership in both vectors.
 for _,entry in ipairs(state.squads)do
  entry.squad.rack_combat:insert('#',state.racks[2].id)
  entry.squad.rack_training:insert('#',state.racks[2].id)
 end
 _G.df3d_squad_racks=state
 return {related=state.racks[1].id,unrelated=state.racks[2].id}
end
function M.prepare()
 assert(df.global.pause_state and _G.df3d_squad_racks)
 df.global.plotinfo.equipment.update.buildings=false
end
function M.verify(id,use)
 local state=assert(_G.df3d_squad_racks);local s=assert(df.squad.find(id))
 local function contains(values,id)for _,value in ipairs(values)do if value==id then return true end end;return false end
 assert(df.global.plotinfo.equipment.update.buildings,'native squad equipment refresh missing')
 assert(contains(s.rack_combat,state.racks[1].id)==((use&4)~=0),'combat rack membership')
 assert(contains(s.rack_training,state.racks[1].id)==((use&2)~=0),'training rack membership')
 assert(not contains(s.rack_combat,state.racks[2].id) and not contains(s.rack_training,state.racks[2].id),'stale rack membership')
 return {related=state.racks[1].id,unrelated=state.racks[2].id,combat=copy(s.rack_combat),training=copy(s.rack_training),equipment_update=true}
end
function M.finish()
 local state=_G.df3d_squad_racks;if not state then return end
 assert(df.global.pause_state)
 for _,entry in ipairs(state.squads)do
  entry.squad.rack_combat:resize(0);entry.squad.rack_training:resize(0)
  for _,id in ipairs(entry.combat)do entry.squad.rack_combat:insert('#',id)end
  for _,id in ipairs(entry.training)do entry.squad.rack_training:insert('#',id)end
 end
 local values=df.global.world.buildings.other.WEAPON_RACK
 for i=#values-1,0,-1 do for _,rack in ipairs(state.racks)do if values[i]==rack then values:erase(i);break end end end
 -- Retain allocations until the owned process exits, even after a failed run.
 _G.df3d_retired_squad_fixtures=_G.df3d_retired_squad_fixtures or {}
 table.insert(_G.df3d_retired_squad_fixtures,state)
 _G.df3d_squad_racks=nil
end
return M
