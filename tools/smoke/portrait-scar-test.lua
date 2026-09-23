-- Paused, unsaved test lane only. Restore the temporary wound before returning.
local unit_id=tonumber(({...})[1]) or 86
local u=df.unit.find(unit_id)
assert(u and df.global.pause_state, 'portrait scar test requires a paused loaded unit')
local head=-1
for i,bp in ipairs(u.body.body_plan.body_parts) do
    if bp.token=='HD' then head=i break end
end
assert(head>=0, 'unit has no head')
local function has_head_scar()
    local output=dfhack.run_command_silent('df3d','appearance',tostring(unit_id))
    return output:find('EYE_SCAR_',1,true)~=nil
end
assert(not has_head_scar(), 'use an unscarred subject for the negative control')
local wound=df.unit_wound:new()
local part=df.unit_wound_layerst:new()
part.body_part_id=head
wound.parts:insert('#',part)
u.body.wounds:insert('#',wound)
local ok,err=pcall(function()
    assert(not has_head_scar(), 'ordinary wound must not add a scar')
    for _,flag in ipairs({'scar_cut','scar_smashed','scar_edged_shake1',
                          'scar_broken','scar_blunt_shake1','scar_joint_bend1'}) do
        part.flags1[flag]=true
        assert(has_head_scar(), 'missing scar for '..flag)
        part.flags1[flag]=false
    end
    part.body_part_id=-1
    part.flags1.scar_cut=true
    assert(not has_head_scar(), 'scar on a different part must not mark the head')
end)
u.body.wounds:erase(#u.body.wounds-1)
wound.parts:resize(0)
part:delete()
wound:delete()
assert(ok,err)
assert(not has_head_scar(), 'test failed to restore scar-free appearance')
print('PORTRAIT_SCAR_TEST_PASS')
