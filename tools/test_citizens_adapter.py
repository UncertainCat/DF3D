"""Asset-free citizen adapter regression with zero-index native vector semantics."""
from pathlib import Path
from lupa import LuaRuntime


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((Path(__file__).resolve().parent / "qa/lua_test_prelude.lua").read_text(encoding="utf-8"))
    lua.execute(r'''
    function flags(mode,no_modify,cannot)
     local v={mode=mode,no_modify=no_modify,cannot_be_everybody=cannot}
     return setmetatable(v,{__index=function(s,k)if k=='whole'then return s.mode*4+(s.no_modify and 1 or 0)+(s.cannot_be_everybody and 2 or 0)end end})
    end
    function detail(name,ids,mode,no_modify,cannot)
     return {name=name,assigned_units=vec(ids),flags=flags(mode or 3,no_modify or false,cannot or false),allowed_labors={[0]=true},icon=9}
    end
    function unit(id,adult,sane,alive)
     return {flags4={only_do_assigned_jobs=id==4},id=id,adult=adult~=false,sane=sane~=false,alive=alive~=false,citizen=true,dead=false,active=true,status={labors={},current_soul={personality={stress=10}}},job={}}
    end
    citizens=vec{unit(0),unit(4),unit(8,false),unit(12,true,false),unit(16,true,true,false)}
    wd=vec{detail('Custom',{4}),detail('Builtin',{},3,true),detail('Protected everybody',{},3,false,true)}
    df={global={world={units={all=citizens,active=citizens},buildings={other={ACTIVITY_ZONE=vec{}}}},plotinfo={group_id=1,labor_info={work_details=wd}},game={external_flag={automatic_professions_disabled=false}},pause_state=true,unitst_set_automatic_professions=true},unit={},unit_labor={[0]='MINE',[1]='HAUL_STONE',_last_item=93},civzone_type={Office=1}}
    df.unit.find=function(id)for _,u in ipairs(citizens)do if u.id==id then return u end end end
    calls={}
    dfhack={df2utf=function(s)return s end,job={getName=function()return 'Work' end},maps={isValidTilePos=function(p)assert(type(p)=='table');return true end,getTileFlags=function()return {hidden=false}end},units={}}
    local U=dfhack.units
    U.isCitizen=function(u,allow)return u.citizen and (allow or u.sane)end
    U.isActive=function(u)return u.active end;U.isAlive=function(u)return u.alive end;U.isDead=function(u)return u.dead end;U.isAdult=function(u)return u.adult end
    U.getProfessionColor=function()return 14 end;U.getAge=function()return 42.7 end;U.getPosition=function()return 1,2,3 end
    U.getReadableName=function(u,skip_english)assert(skip_english==true);return 'Citizen '..u.id end;U.getProfessionName=function()return 'Carpenter' end;U.getNoblePositions=function()return {}end
    U.setAutomaticProfessions=function(u)
     calls[#calls+1]=u.id
     if fail_next then fail_next=false;error('native failure')end
     local enabled=false
     for _,d in ipairs(wd)do if d.flags.mode==1 then enabled=true elseif d.flags.mode==3 then for _,id in ipairs(d.assigned_units)do if id==u.id then enabled=true end end end end
     u.status.labors[0]=enabled
    end
    function request(action,extra)
     local c={unit_id=-1,detail_index=-1,expected_revision=0,cursor=0,query='',member=-1,mode=-1}
     for k,v in pairs(extra or {})do c[k]=v end
     return {action=action,citizen=c}
    end
    ''')
    helper=lua.execute(Path('bridge/plugin/citizens.lua').read_text())
    def call(action, **fields):
        return helper(lua.globals().request(action,lua.table_from(fields)))
    def observed(index=0):
        r=call(31,detail_index=index)
        assert r['ok'],r['message']
        return r['details'][1]
    def edit(action=32,index=0,**fields):
        return call(action,detail_index=index,expected_revision=observed(index)['revision'],**fields)
    def refused(reply, message):
        assert not reply['ok']
        assert reply['message']==message, reply['message']
    assert call(28)['citizens'][1]['profession_color']==14
    assert call(28)['citizens'][1]['job_type']==-1
    roster=call(28)['citizens']
    assert not roster[1]['only_assigned_jobs'] and roster[2]['only_assigned_jobs']
    assert len(roster[1]['assigned_details'])==0
    assignment=roster[2]['assigned_details'][1]
    assert assignment['index']==0 and assignment['icon']==9 and assignment['name']=='Custom'

    assert len(call(28)['citizens'])==5  # insane, child and surviving nonliving remain visible
    assert call(29,unit_id=0)['citizens'][1]['x']==1
    assert call(28,query='#0')['citizens'][1]['id']==0
    assert len(call(28,cursor=4)['citizens'])==4
    before=observed()['revision']
    assert edit(unit_id=0,member=1)['ok']
    assert list(observed()['assigned_units'].values())==[0,4]
    assert call(29,unit_id=0)['citizens'][1]['labors'][1]==0
    refused(call(32,detail_index=0,expected_revision=before,unit_id=4,member=0), 'Work-detail contents changed; refresh before editing')
    count=len(lua.globals().calls)
    assert edit(unit_id=0,member=1)['ok'] and len(lua.globals().calls)==count
    assert edit(unit_id=0,member=0)['ok']
    count=len(lua.globals().calls)
    assert edit(unit_id=0,member=0)['ok'] and len(lua.globals().calls)==count
    assert list(observed()['assigned_units'].values())==[4]
    for id, message in [(8,'Labor assignment requires an adult citizen'),
                        (12,'Citizen is not eligible for ordinary labor'),
                        (16,'Citizen is outside the supported living labor-assignment scope'),
                        (99,'Not an active surviving citizen')]:
        refused(edit(unit_id=id,member=1), message)
    assert observed(1)['editable'] and observed(1)['mode_editable']
    assert edit(index=1,unit_id=0,member=1)['ok']
    assert observed(1)['no_modify']
    assert edit(33,index=1,mode=1)['ok']
    assert observed(1)['no_modify'] and observed(1)['mode']==1
    refused(edit(33,index=2,mode=1), 'This work detail cannot be assigned to everybody')
    lua.execute('df.global.pause_state=false')
    refused(edit(33,mode=1), 'Pause before changing a work-detail mode')
    lua.execute('df.global.pause_state=true; calls={}')
    assert edit(33,mode=1)['ok']
    assert list(lua.globals().calls.values())==[0,4]
    assert not lua.globals().citizens[2]["status"]["labors"][0]  # native mock would enable child labors if called
    assert not lua.globals().citizens[3]["status"]["labors"][0]
    assert not lua.globals().citizens[4]["status"]["labors"][0]
    for mode in (2,3,1):
        reply=edit(33,mode=mode)
        assert reply['ok'] and reply['details'][1]['mode']==mode
        assert observed()['mode']==mode
    lua.execute('df.global.game.external_flag.automatic_professions_disabled=true')
    assert call(30)['external_controller']
    assert not observed()['editable'] and not observed()['mode_editable']
    assert observed()['reason']=='An external labor controller owns assignments'
    refused(edit(33,mode=2), 'An external labor controller owns assignments')
    refused(edit(unit_id=0,member=1), 'An external labor controller owns assignments')
    lua.execute('df.global.game.external_flag.automatic_professions_disabled=false; df.global.unitst_set_automatic_professions=nil')
    refused(edit(unit_id=0,member=1), 'Native labor recalculation is unavailable')
    assert list(observed()['assigned_units'].values())==[4]
    lua.execute('df.global.unitst_set_automatic_professions=true; fail_next=true')
    refused(edit(unit_id=0,member=1), 'Native recalculation failed; membership restored')
    assert list(observed()['assigned_units'].values())==[4]
    lua.execute('fail_next=true')
    refused(edit(unit_id=4,member=0), 'Native recalculation failed; membership restored')
    assert list(observed()['assigned_units'].values())==[4]
    before=observed()['revision']
    lua.execute('local d=wd[0];wd._data[1]=wd[1];wd._data[2]=d')
    refused(call(32,detail_index=0,expected_revision=before,unit_id=0,member=1), 'Work-detail contents changed; refresh before editing')
    lua.execute("wd:insert('#',detail('Custom',{4},1))")
    assert not observed(1)['editable'] and not observed(1)['mode_editable']
    assert observed(1)['reason']=='Identical work-detail definitions have ambiguous identity'
    refused(edit(index=1,unit_id=0,member=1), 'Identical work-detail definitions have ambiguous identity')
    lua.execute("wd:erase(3); fail_next=true")
    original_mode=observed(1)['mode']
    refused(edit(33,index=1,mode=2), 'Native recalculation failed; mode restored')
    assert observed(1)['mode']==original_mode
    lua.execute("for i=1,255 do citizens:insert('#',unit(16+i))end")
    refused(edit(33,index=1,mode=2), 'Mode changes currently support at most 256 eligible living sane adults')  # 257 eligible adults: fail before any native mutation
    assert observed(1)['mode']==original_mode
    lua.execute("citizens:resize(5);wd:resize(0);for n=1,8 do local ids={};for i=1,1024 do ids[i]=i*10 end;wd:insert('#',detail('large'..n,ids))end;wd:insert('#',detail('empty',{}))")
    refused(edit(index=8,unit_id=0,member=1), 'Work-detail assignments exceed bounded inspector')  # aggregate cap checked before addition
    assert len(observed(8)['assigned_units'])==0
    lua.execute("wd:resize(1);wd[0].assigned_units=vec{};dfhack.units.getNoblePositions=function()local a={};for i=1,33 do a[i]={entity={id=1},position={name={[0]='Role'},required_office=0}}end;return a end")
    refused(edit(index=0,unit_id=0,member=1), 'Citizen has too many roles for this inspector')  # optional inspector cannot fail only after mutation
    assert len(observed(0)['assigned_units'])==0
    # Independent paging/inspection fixture after the mutation failure cases.
    lua.execute("""
    citizens:resize(0);for i=0,33 do citizens:insert('#',unit(i))end
    wd:resize(0);for i=0,17 do wd:insert('#',detail('Page '..i,{}))end
    wd[0].allowed_labors[1]=true
    citizens[0].status.labors[0]=true;citizens[0].status.labors[1]=true
    dfhack.units.getNoblePositions=function()return {{entity={id=1},position={name={[0]='Manager'},required_office=250}}}end
    """)
    first=call(30,query='Page',cursor=0)
    assert first['ok'] and len(first['details'])==16 and first['next_cursor']==16
    second=call(30,query='Page',cursor=first['next_cursor'])
    assert len(second['details'])==2 and second['next_cursor']==0
    assert len(call(30,query='Page 17')['details'])==1
    assert list(first['details'][1]['labors'].values())==[0,1]
    assert list(first['details'][1]['labor_names'].values())==['mine','haul stone']
    first=call(28,query='Citizen',cursor=0)
    assert len(first['citizens'])==32 and first['next_cursor']==32
    second=call(28,query='Citizen',cursor=first['next_cursor'])
    assert len(second['citizens'])==2 and second['next_cursor']==0
    inspected=call(31,detail_index=0,unit_id=0)
    assert len(inspected['details'])==1 and inspected['selected_detail']==0 and inspected['selected_unit']==0
    assert call(31,detail_index=0)['selected_unit']==-1
    person=call(29,unit_id=0)['citizens'][1]
    assert list(person['labors'].values())==[0,1]
    assert person['roles'][1]['name']=='Manager' and person['roles'][1]['required_office']==250
    print('CITIZENS_ADAPTER_PASS')


if __name__ == '__main__':
    main()
