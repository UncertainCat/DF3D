-- Pure semantic staging geometry. Three terraces with supported native ramps.
local M={height=3}
function M.elevation(x,y)
    local r=math.max(math.abs(x),math.abs(y))
    return r<=6 and 3 or r<=10 and 2 or r<=14 and 1 or 0
end
function M.ramp(x,y)
    local r=math.max(math.abs(x),math.abs(y))
    return (r==7 or r==11 or r==15) and math.abs(x)~=math.abs(y)
end
function M.tile(x,y,z)
    local h=M.elevation(x,y)
    if z<h then return 'StoneWall' end
    if z==h then return M.ramp(x,y) and 'StoneRamp' or 'StoneFloorSmooth' end
    if z==h+1 and M.ramp(x,y) then return 'RampTop' end
    return 'OpenSpace'
end
function M.position(left,index)
    if left then
        local points={{-3,-3},{0,-3},{3,-3},{-3,0},{3,0},{-3,3},{0,3},{3,3}}
        local p=assert(points[index]);return p[1],p[2],3
    end
    -- Fifteen per side, evenly surrounding the hill and clear of all ramps.
    local side=(index-1)//15;local along=((index-1)%15-7)*2
    if side==0 then return along,-20,0 end
    if side==1 then return 20,along,0 end
    if side==2 then return -along,20,0 end
    return -20,-along,0
end
return M
