-- Pure native platform geometry and repeatable population scaling.
local M={height=3,max_scale=8}
function M.elevation(x,y)
    if math.abs(x)<=5 and math.abs(y)<=5 then return 3 end
    if x==0 and y>=6 and y<=8 then return 8-y end
    return 0
end
function M.ramp(x,y) return x==0 and y>=6 and y<=8 end
function M.tile(x,y,z)
    local h=M.elevation(x,y)
    if z<h then return 'StoneWall' end
    if z==h then return M.ramp(x,y) and 'StoneRamp' or 'StoneFloorSmooth' end
    if z==h+1 and M.ramp(x,y) then return 'RampTop' end
    return 'OpenSpace'
end

-- Preserve original positions; larger populations fill unused supported tiles.
local positions={{},{}}
local occupied={}
local function add(side,x,y,z)
    local key=x..','..y..','..z
    if occupied[key] or M.tile(x,y,z)~='StoneFloorSmooth' then return end
    occupied[key]=true;positions[side][#positions[side]+1]={x,y,z}
end
for _,p in ipairs({{-4,-4},{0,-4},{4,-4},{-4,0},{4,0},{-4,4},{0,4},{4,4}}) do add(1,p[1],p[2],3) end
for side=0,3 do for i=0,5 do
    local along=i*2-5
    if side==0 then add(2,along,-11,0)
    elseif side==1 then add(2,11,along,0)
    elseif side==2 then add(2,-along,11,0)
    else add(2,-11,-along,0) end
end end
add(2,0,13,0)
for y=-5,5 do for x=-5,5 do add(1,x,y,3) end end
for radius=10,14 do for along=-radius,radius-1 do
    add(2,along,-radius,0);add(2,radius,along,0)
    add(2,-along,radius,0);add(2,-radius,-along,0)
end end
function M.position(left,index)
    local p=assert(positions[left and 1 or 2][index],'Platform spawn capacity exceeded')
    return p[1],p[2],p[3]
end
function M.scale(config,multiplier)
    multiplier=tonumber(multiplier or 1)
    assert(multiplier and (multiplier==1 or multiplier==2 or multiplier==4 or multiplier==8),
        'Platform scale must be 1, 2, 4 or 8; the unchanged summit has 121 spawn tiles')
    config.population_scale=multiplier
    for _,team in ipairs({config.left,config.right}) do
        local count,roles=team.count,team.roles or {}
        team.roles={}
        for i=1,count*multiplier do team.roles[i]=roles[(i-1)%count+1] end
        team.count=count*multiplier
    end
    config.equipment_note=('%d mixed dwarf defenders against %d goblins and %d ogres; narrow ramp access'):format(8*multiplier,24*multiplier,multiplier)
    return config
end
return M
