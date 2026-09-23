-- Owned test lane only. Sample ticks against wall time without per-tick I/O.
local action,path,name,duration=...
local json=require('json')
if action=='start' then
    assert(dfhack.isMapLoaded())
    local start=dfhack.getTickCount()
    local state={name=name,rows={},start_ms=start,start_tick=df.global.world.frame_counter,
        target_ms=tonumber(duration)*1000,done=false}
    df3d_stream_probe=state
    local function sample()
        if df3d_stream_probe~=state then return end
        local now=dfhack.getTickCount()
        if not state.last_ms or now-state.last_ms>=500 then
            state.rows[#state.rows+1]={ms=now-start,tick=df.global.world.frame_counter,
                fps=df.global.enabler.calculated_fps,gfps=df.global.enabler.calculated_gfps,
                fps_cap=df.global.enabler.fps,gfps_cap=df.global.enabler.gfps,paused=df.global.pause_state}
            state.last_ms=now
        end
        if now-start>=state.target_ms then
            state.end_ms=now;state.end_tick=df.global.world.frame_counter;state.done=true
            state.sim_fps=(state.end_tick-state.start_tick)*1000/(now-start)
            local f=assert(io.open(path,'w'));f:write(json.encode(state));f:close()
        else dfhack.timeout(1,'frames',sample) end
    end
    sample()
    print('STREAM_NATIVE_STARTED '..name)
elseif action=='info' then
    local info={tick=df.global.world.frame_counter,units=#df.global.world.units.active,
        items=#df.global.world.items.all,fps_cap=df.global.enabler.fps,gfps_cap=df.global.enabler.gfps,
        paused=df.global.pause_state}
    local f=assert(io.open(path,'w'));f:write(json.encode(info));f:close()
end
