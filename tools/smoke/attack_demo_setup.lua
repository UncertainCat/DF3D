-- Development-only setup, invoked exclusively inside the owned no-save lane.
-- Trigger real DF combat AI; never inject fabricated unit attack actions.
local output = ...
assert(output and dfhack.isMapLoaded())
df.global.pause_state = true
local candidates = {}
for _,u in ipairs(df.global.world.units.active) do
    if dfhack.units.isCitizen(u) and u.pos.z == 128 and u.mood == df.mood_type.None then
        table.insert(candidates, u)
        if #candidates == 2 then break end
    end
end
assert(#candidates == 2, 'Need two citizens on showcase level 128')
local focus = {x=candidates[1].pos.x, y=candidates[1].pos.y, z=128}
local adjacent
for _,offset in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
    local p={x=focus.x+offset[1],y=focus.y+offset[2],z=focus.z}
    local tile=dfhack.maps.getTileType(p)
    if tile and df.tiletype.attrs[tile].shape == df.tiletype_shape.FLOOR then adjacent=p; break end
end
assert(adjacent, 'Need adjacent floor for directed combat test')
for i,u in ipairs(candidates) do
    if u.job.current_job then dfhack.job.removeJob(u.job.current_job) end
    assert(dfhack.units.teleport(u, i==1 and focus or adjacent), 'Cannot stage combatant')
    u.mood = df.mood_type.Berserk
end
local json = require('json')
local data = {focus=focus, units={candidates[1].id,candidates[2].id}, actions={}}
local function save()
    local f=assert(io.open(output, 'w')); f:write(json.encode(data)); f:close()
end
save()
local seen = {}
local remaining = 1500
-- Errors inside a timeout callback end the chain silently; record them in
-- the output the PowerShell collector reads (data.error).
local sample
local function step()
    if not dfhack.isMapLoaded() then return end
    for _,u in ipairs(df.global.world.units.active) do
        for _,a in ipairs(u.actions) do
            if a.type == df.unit_action_type.Attack then
                local key=tostring(u.id)..':'..tostring(a.id)
                if not seen[key] then
                    seen[key]=true
                    local attack=a.data.attack
                    table.insert(data.actions, {attacker=u.id, action=a.id, target=attack.target_unit_id,
                        timer1=attack.timer1,timer2=attack.timer2,tick=df.global.world.frame_counter})
                    save()
                end
            end
        end
    end
    remaining=remaining-1
    if remaining>0 then dfhack.timeout(1,'ticks',sample) end
end
sample=function()
    local ok,err=xpcall(step,debug.traceback)
    if not ok then
        data.error=err
        pcall(save)
        dfhack.printerr('ATTACK_DEMO_ERROR '..tostring(err))
    end
end
dfhack.timeout(1,'ticks',sample)
print('ATTACK_DEMO_SETUP '..json.encode({units=data.units, focus=focus}))
