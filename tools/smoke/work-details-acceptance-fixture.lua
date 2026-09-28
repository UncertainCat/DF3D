-- Owned disposable clone only. Every native write is logged; never saves.
local out,op,index=...
local json=require('json')
local all=df.global.plotinfo.labor_info.work_details
if op=='rename' then
 assert(df.global.pause_state,'step 7 requires pause')
 assert(index and index>=0 and index<#all,'rename target missing')
 assert(not df3d_work_details_acceptance.renamed,'one out-of-band rename only')
 print('FIXTURE_WRITE detail['..index..'].name '..all[index].name..' -> DF3D stale probe')
 all[index].name=dfhack.utf2df('DF3D stale probe')
 df3d_work_details_acceptance.renamed=true
 print('FIXTURE_RENAMED');return
end
print('FIXTURE_WRITE pause_state=true');df.global.pause_state=true
-- Preserve original memory preferences even if setup fails or is retried.
if not _G.df3d_work_details_acceptance_prefs then
 local saved={autosave=df.global.d_init.feature.autosave,announcements={}}
 for id,flags in ipairs(df.global.d_init.announcements.flags) do saved.announcements[id]=flags.whole end
 _G.df3d_work_details_acceptance_prefs=saved
end
print('FIXTURE_WRITE d_init.feature.autosave=NONE')
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
for id,flags in ipairs(df.global.d_init.announcements.flags) do
 print('FIXTURE_WRITE d_init.announcements.flags['..id..'] PAUSE=false DO_MEGA=false')
 flags.PAUSE=false;flags.DO_MEGA=false
end
local f={member=-1,scope=-1,miners=-1,mode_detail=-1,custom_count=0,carpentry=df.unit_labor.CARPENTER,residents={},visitors={},missing={}}
local function missing(step,reason)
 f.missing[#f.missing+1]={step=step,reason=reason}
 print('FIXTURE_INCOMPLETE step '..step..': '..reason)
end
local assigned={}
for i,d in ipairs(all) do
 if not d.flags.no_modify then f.custom_count=f.custom_count+1 end
 if d.flags.no_modify and d.icon==df.work_detail_icon_type.MINERS then f.miners=i end
 if d.flags.no_modify and not d.flags.cannot_be_everybody and d.flags.mode==1 then f.mode_detail=i end
 for _,id in ipairs(d.assigned_units) do assigned[id]=true end
end
local U=dfhack.units
local anchor
for _,u in ipairs(df.global.world.units.active) do
 if U.isCitizen(u,true) and U.isActive(u) and not U.isDead(u) and dfhack.maps.isValidTilePos(u.pos) then anchor=anchor or u end
 if U.isCitizen(u) and U.isActive(u) and not U.isDead(u) and U.isAlive(u) and U.isAdult(u) then
  if not assigned[u.id] and not u.flags4.only_do_assigned_jobs then f.scope=u.id end
 end
 if not U.isCitizen(u,true) then
  if u.flags2.resident then f.residents[#f.residents+1]=u.id end
  if u.flags2.visitor or u.flags2.visitor_uninvited then f.visitors[#f.visitors+1]=u.id end
 end
end
for _,u in ipairs(df.global.world.units.active) do
 if u.id~=f.scope and U.isCitizen(u) and U.isActive(u) and not U.isDead(u) and U.isAlive(u) and U.isAdult(u) then f.member=u.id;break end
end
if f.member<0 then missing(2,'no adult citizen for membership') end
if f.scope<0 then missing(4,'no detail-less adult citizen with only-assigned clear') end
if f.miners<0 then missing(3,'no MINERS built-in') end
if f.mode_detail<0 then missing(6,'no built-in in Everybody mode allowing Everybody') end
if #f.residents==0 then missing(5,'no resident in save') end
if #f.visitors==0 then missing(5,'no visitor in save') end
-- The existing guard requires a tile anchor, not a designation fixture mutation.
if anchor then
 _G.df3d_designation_acceptance={{tile={x=anchor.pos.x,y=anchor.pos.y,z=anchor.pos.z}}}
else missing(7,'no citizen tile for command guard') end
f.guard_available=anchor~=nil
_G.df3d_work_details_acceptance=f
local file=assert(io.open(out..'/fixture.json','w'));file:write(json.encode(f));file:close()
print('FIXTURE_READY')
