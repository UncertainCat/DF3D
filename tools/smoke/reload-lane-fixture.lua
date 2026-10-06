-- Only used on the reload lane's owned, disposable, never-saved clone.
local out,mode,id=...
local json=require('json')
df.global.pause_state=true
if mode=='restore' then
    if df3d_reload_prefs then
        df.global.d_init.feature.autosave=df3d_reload_prefs.autosave
        for k,v in pairs(df3d_reload_prefs.flags) do df.global.d_init.announcements.flags[k].whole=v end
    end
    print('RELOAD_FIXTURE_RESTORED');return
end
if not df3d_reload_prefs then
    df3d_reload_prefs={autosave=df.global.d_init.feature.autosave,flags={}}
    for k,v in pairs(df.global.d_init.announcements.flags) do df3d_reload_prefs.flags[k]=v.whole end
end
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
for _,v in ipairs(df.global.d_init.announcements.flags) do v.PAUSE=false;v.DO_MEGA=false end
local unit=id and df.unit.find(tonumber(id))
if not id then
    for _,u in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(u) and dfhack.units.isActive(u) and not dfhack.units.isDead(u) then unit=u;break end
    end
end
assert(unit,'reload marker citizen is absent')
if mode=='mark' then
    assert(unit.name.nickname~='df3d-reload-marker','marker already present in source')
    unit.name.nickname='df3d-reload-marker'
elseif mode=='verify' then
    assert(unit.name.nickname~='df3d-reload-marker','unsaved marker survived restart')
else error('unknown reload fixture mode') end
local f=assert(io.open(out..'/marker.json','w'));f:write(json.encode({id=unit.id,mode=mode}));f:close()
assert(df.global.pause_state and df.global.d_init.feature.autosave==df.d_init_autosave.NONE)
print('FIXTURE_READY reload '..mode..' '..unit.id)
