-- Controlled paused material setup; native clicks remain the effect oracle.
local out,view,b,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local original={material_type=b.mat_type,material_index=b.mat_index,flags=b.cage_flags.whole}
local frame=df.global.world.frame_counter
local result={id=b.id,original=original,native={}}
local function click(x)
 g.precise_mouse_x=x;g.precise_mouse_y=406;g.mouse_x=x//8;g.mouse_y=33
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local ok,err=xpcall(function()
 b.mat_type=df.builtin_mats.GLASS_GREEN;b.mat_index=-1;b.cage_flags.whole=0
 view:render(dfhack.getTickCount());capture('cage-glass-terrarium')
 click(856);assert(b.cage_flags.whole==6,'Native aquarium effect differs')
 result.native[1]={aquarium=true,flags=b.cage_flags.whole};capture('cage-glass-aquarium')
 click(776);assert(b.cage_flags.whole==4,'Native terrarium effect differs')
 result.native[2]={aquarium=false,flags=b.cage_flags.whole}
 b.cage_flags.whole=0
 local f=assert(io.open(out..'/cage-wire-expected.json','w'));f:write(json.encode({id=b.id,glass=true}));f:close()
 local active=df.global.game.main_interface.view_sheets.active_id
 capture('cage-glass-wire')
 f=assert(io.open(out..'/cage-glass-wire-result.json'));result.wire=json.decode(f:read('*a'));f:close()
 assert(result.wire.success and b.cage_flags.whole==result.native[2].flags,'Glass provider differs from native')
 assert(df.global.game.main_interface.view_sheets.active_id==active and df.global.world.frame_counter==frame)
end,debug.traceback)
b.mat_type=original.material_type;b.mat_index=original.material_index;b.cage_flags.whole=original.flags
view:render(dfhack.getTickCount())
assert(ok,err)
result.success=true;result.restored=true
local f=assert(io.open(out..'/cage-glass-native.json','w'));f:write(json.encode(result));f:close()
