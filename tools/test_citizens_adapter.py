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
    df.unit_labor.attrs=setmetatable({[0]={caption='Mining'},[1]={caption='Stone Hauling'}},{__index=function()return {}end})
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
    assert assignment['index']==0 and assignment['icon']==9 and assignment['name']==''

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
    assert edit(33,mode=2)['ok']  # mode edits also work while unpaused
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
    assert observed(1)['editable'] and observed(1)['mode_editable']
    assert observed(1)['reason']==''
    assert edit(index=1,unit_id=0,member=1)['ok']
    lua.execute("wd:erase(3); fail_next=true")
    original_mode=observed(1)['mode']
    refused(edit(33,index=1,mode=2), 'Native recalculation failed; mode restored')
    assert observed(1)['mode']==original_mode
    lua.execute("for i=1,255 do citizens:insert('#',unit(16+i))end")
    assert edit(33,index=1,mode=2)['ok']  # no 256-adult limit
    assert observed(1)['mode']==2
    lua.execute("citizens:resize(5);wd:resize(0);for n=1,8 do local ids={};for i=1,1024 do ids[i]=i*10 end;wd:insert('#',detail('large'..n,ids))end;wd:insert('#',detail('empty',{}))")
    assert edit(index=8,unit_id=0,member=1)['ok']  # no aggregate membership cap
    assert len(observed(8)['assigned_units'])==1
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
    second=call(30,query='Page',cursor=first['next_cursor'],expected_list_revision=first['detail_list_revision'])
    assert len(second['details'])==2 and second['next_cursor']==0
    assert len(call(30,query='Page 17')['details'])==1
    assert list(first['details'][1]['labors'].values())==[0,1]
    assert list(first['details'][1]['labor_names'].values())==['Mining','Stone Hauling']
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
    extended_work_details(lua)
    print('CITIZENS_ADAPTER_PASS')


def extended_work_details(lua):
    """Inline native inputs; progress is counted in steps, never wall time."""
    lua.globals().encode_cp437 = lambda s: s.encode('cp437', errors='replace').decode('latin1')
    lua.globals().cp437_chars = lua.table_from({i:bytes([i]).decode('cp437') for i in range(256)})
    lua.execute(r'''
    dfhack.utf2df=function(s)
      local out={};for _,code in utf8.codes(encode_cp437(s))do out[#out+1]=string.char(code)end
      return table.concat(out)
    end
    dfhack.df2utf=function(s)
      local out={};for i=1,#s do out[#out+1]=cp437_chars[s:byte(i)]end;return table.concat(out)
    end
    df.work_detail_icon_type=enum({'MINERS','WOODCUTTERS','HUNTERS','PLANTERS','FISHERMEN','PLANT_GATHERERS','STONECUTTERS','ENGRAVERS','HAULERS','ORDERLIES','CUSTOM_1','CUSTOM_2','CUSTOM_3','CUSTOM_4','CUSTOM_5','CUSTOM_6','CUSTOM_7','CUSTOM_8','SIEGE_OPERATORS'})
    df.work_detail={new=function()local d=detail('',{},1);d.allowed_labors={};return d end}
    df.building_civzonest={is_instance=function(_,b)return b.office_zone end}
    df.job_skill={attrs={[1]={labor=0,caption_noun='Miner'},[2]={labor=0,caption_noun='Miner'}}}
    df.skill_rating={attrs={[15]={caption='Legendary'}}}
    -- Enum ordinals other than the three pinned picker exclusions are fixture-local.
    for i=0,93 do df.unit_labor.attrs[i]={caption='Fixture labor '..i}end
    df.unit_labor.attrs[0]={caption='Mining'};df.unit_labor.attrs[10]={caption='Wood Cutting'}
    df.unit_labor.attrs[44]={caption='Hunting'}
    df.unit_labor.CARPENTER=1;df.unit_labor.attrs[1]={caption='Carpentry'}
    for i=82,93 do df.unit_labor[i]='UNUSED_'..i;df.unit_labor.attrs[i]={}end
    for _,kind in ipairs{'Resident','Visitor','Merchant','Diplomat'}do
      local key=string.lower(kind);dfhack.units['is'..kind]=function(u)return not not u[key]end
    end
    local original_unit=unit
    function unit(id,adult,sane,alive)
      local u=original_unit(id,adult,sane,alive);u.profession=0;u.owned_buildings=vec{}
      u.status.labors=setmetatable({},{__newindex=function(t,k,v)
        labor_writes=labor_writes+1;rawset(t,k,v)
      end});return u
    end
    dfhack.units.getNoblePositions=function()return {}end
    dfhack.units.setAutomaticProfessions=function(u)
      calls[#calls+1]={id=u.id,only_assigned=u.flags4.only_do_assigned_jobs}
      if fail_next then fail_next=false;error('native failure')end
    end
    function reset_fixture(n,d)
      calls={};labor_writes=0;fail_next=false;citizens:resize(0);wd:resize(0)
      for i=0,n-1 do citizens:insert('#',unit(i))end
      for i=0,d-1 do wd:insert('#',detail('Custom',{}))end
      df.global.pause_state=false
    end
    ''')
    source = Path('bridge/plugin/citizens.lua').read_text()
    def reset(n=2, d=1):
        lua.globals().reset_fixture(n, d)
        return lua.execute(source)
    helper = reset()
    def call(action, **fields):
        budget = fields.pop('step_budget', 2048)
        capacity = fields.pop('retire_capacity', 256)
        req = lua.globals().request(action, lua.table_from(fields))
        req['step_budget'], req['retire_capacity'] = budget, capacity
        return helper(req)
    def ok(reply):
        assert reply['ok'], reply['message']
        return reply
    def observed(index=0):
        return ok(call(31, detail_index=index))['details'][1]
    def edit(action=66, index=0, **fields):
        return call(action, detail_index=index, expected_revision=observed(index)['revision'], **fields)
    def refused(reply, message):
        assert not reply['ok'] and reply['message'] == message, reply['message']
    def values(table):
        return list(table.values())
    # The shared mock must fail exactly as DFHack does, including empty vectors.
    lua.execute("""
    for _,v in ipairs{vec{},vec{42}}do
      for _,index in ipairs{-1,#v,#v+1}do
        local success,message=pcall(function()return v[index]end)
        assert(not success and message=='index out of bounds')
      end
    end
    assert(vec{42}[0]==42)
    """)
    for index in (-1, 1, 127):
        row = ok(call(28, detail_index=index))['citizens'][1]
        assert row['detail_member'] == -1 and row['detail_skill'] == -1
        for action in (31, 32, 33, 65, 66):
            refused(call(action, detail_index=index, expected_revision=1), 'Work detail no longer exists')
    stale = observed()['revision']
    ok(edit(65))
    refused(call(31, detail_index=0), 'Work detail no longer exists')
    refused(call(66, detail_index=0, expected_revision=stale, edit=1, name='Stale'), 'Work detail no longer exists')
    # Applied deletes/labor edits retain Ok and publish the recalc error separately.
    for action, selector in ((65, 0), (66, 2), (66, 3)):
        helper = reset()
        if selector == 2:
            lua.execute('wd[0].allowed_labors[1]=true')
        if selector == 3:
            lua.execute('wd[0].flags.no_modify=true;wd[0].icon=0;df.unit_labor.MINE=0;wd[0].allowed_labors={[1]=true}')
        lua.execute('fail_next=true')
        r = ok(edit(action, edit=selector))
        assert r['message'] == 'Native work-detail change applied'
        assert r['recalc_error'] == 'Native recalculation failed; labors may be stale' and r['active_kinds'] == 0
        if action == 65:
            assert len(r['retired']) == 1 and lua.eval('#wd') == 0
        else:
            assert values(observed()['labors']) == [0]
            assert not lua.globals().wd[0]['allowed_labors'][1]
    # Native recalculation may change membership before the post-write inspection.
    helper = reset()
    lua.execute("saved_recalc=dfhack.units.setAutomaticProfessions;dfhack.units.setAutomaticProfessions=function(u)saved_recalc(u);wd[0].assigned_units=vec{0,0}end")
    refused(edit(32, unit_id=0, member=1), 'Native work-detail membership is not sorted and unique')
    lua.execute('dfhack.units.setAutomaticProfessions=saved_recalc')
    # A last-step mode failure still restores every touched unit without reserve.
    for refresh_fails in (False, True):
        helper = reset(100)
        lua.globals().refresh_fails = refresh_fails
        lua.execute("""
        saved_recalc=dfhack.units.setAutomaticProfessions
        dfhack.units.setAutomaticProfessions=function(u)
          saved_recalc(u)
          if #calls==31 or (refresh_fails and #calls>31)then error('native failure')end
        end
        """)
        r = edit(33, mode=1, step_budget=64)
        refused(r, 'Native recalculation failed; mode restored' + (' but labor refresh failed' if refresh_fails else ''))
        assert r['steps'] == 64 and r['active_kinds'] == 0 and len(lua.globals().calls) == 62
        assert observed()['mode'] == 3
        lua.execute('dfhack.units.setAutomaticProfessions=saved_recalc')
    # Add uses the native custom count, wraps the icon, and does no recalculation.
    for count in (0, 1, 8, 127):
        helper = reset(d=count)
        before = ok(call(30))['detail_list_revision']
        r = ok(call(64, expected_revision=before));d = r['details'][1]
        assert d['name'] == f'Custom Detail {count}' and d['icon'] == 10 + count % 8
        assert d['mode'] == 1 and not len(d['labors']) and not len(d['assigned_units'])
        assert r['selected_detail'] == count and not len(lua.globals().calls)
        assert r['detail_list_revision'] != before and r['active_kinds'] == 0
        refused(call(64, expected_revision=before), 'Work-detail contents changed; refresh before editing')
    refused(call(64, expected_revision=r['detail_list_revision']), 'Work-detail vector exceeds 128 entries')
    helper = reset(5000)
    refused(edit(65, retire_capacity=0), 'Deleted-detail capacity reached; restart DF')
    assert lua.eval("#wd") == 1
    r = ok(edit(65))
    assert len(r['retired']) == 1 and lua.eval("#wd") == 0 and r['active_kinds'] == 16
    helper = reset()
    lua.execute('wd[0].flags.no_modify=true;wd[0].icon=0')
    refused(edit(65), 'Use Reset to default for built-in work details')
    ok(edit(edit=1, name='MinersX'))
    lua.execute('wd[0].allowed_labors[1]=true;wd[0].assigned_units=vec{0};df.unit_labor.MINE=0')
    r = ok(edit(edit=3))['details'][1]
    assert r['name'] == 'MinersX' and r['mode'] == 3 and r['icon'] == 0
    assert values(r['assigned_units']) == [0] and values(r['labors']) == [0]
    lua.execute('wd[0].icon=18')
    refused(edit(edit=3), 'No native default recorded for this work detail')
    lua.execute('wd[0].flags.no_modify=false')
    refused(edit(edit=3), 'Reset to default applies to built-in work details')
    for builtin in (False, True):
        lua.globals().wd[0]['flags']['no_modify'] = builtin
        for name in ('x' * 40, '\u2500' * 40, '\U0001f642', ''):
            ok(edit(edit=1, name=name))
            stored = lua.eval('function()return {string.byte(wd[0].name,1,-1)}end')()
            assert values(stored) == list(name.encode('cp437', errors='replace'))
        ok(edit(edit=1));assert lua.globals().wd[0]['name'] == ''
        refused(edit(edit=1, name='x' * 41), 'Work-detail names are limited to 40 characters')
        assert lua.globals().wd[0]['name'] == ''
    lua.execute('wd[0].allowed_labors={[0]=true,[10]=true,[44]=true,[1]=true}')
    for labor in (0, 10, 44, *range(82,94)):
        before = [bool(lua.globals().wd[0]['allowed_labors'][i]) for i in range(94)]
        refused(edit(edit=2, labors=lua.table_from([labor])),
                f'Labor {labor} is not in the native labor picker' if labor in (0,10,44) else f'Labor {labor} has no native caption')
        assert lua.globals().wd[0]['allowed_labors'][1]
        assert [bool(lua.globals().wd[0]['allowed_labors'][i]) for i in range(94)] == before
    ok(edit(edit=2));assert not lua.globals().wd[0]['allowed_labors'][1]
    for labor in (0, 10, 44): assert lua.globals().wd[0]['allowed_labors'][labor]
    ok(edit(edit=2, labors=lua.table_from([1])))
    assert lua.globals().wd[0]['allowed_labors'][1]
    helper = reset()
    for toggle in (1, 0):
        before = ok(call(29, unit_id=0))['citizens'][1]['revision']
        n = len(lua.globals().calls)
        r = ok(call(67, unit_id=0, only_assigned=toggle, expected_revision=before))
        assert r['steps'] == 4  # one header, two row hashes, one native recalculation
        assert lua.globals().wd[0]['icon'] == 9
        assert len(lua.globals().calls) == n+1 and lua.globals().labor_writes == 0
        assert lua.globals().calls[n+1]['id'] == 0
        assert lua.globals().calls[n+1]['only_assigned'] == bool(toggle)
        refused(call(67, unit_id=0, only_assigned=toggle, expected_revision=before), 'Citizen changed; inspect again')
    lua.execute('citizens[0].adult=false')
    refused(call(67, unit_id=0, only_assigned=1, expected_revision=1), 'Labor assignment requires an adult citizen')
    helper = reset()
    lua.execute('wd[0].assigned_units=vec{0};citizens[0].status.current_soul.skills=vec{{id=2,rating=15},{id=1,rating=15}}')
    for icon in (-1, 0, 18):
        lua.globals().wd[0]['icon'] = icon
        assert observed()['icon'] == icon
        r = ok(call(28, detail_index=0))['citizens'][1]
        assert r['assigned_details'][1]['icon'] == icon and r['detail_member'] == 1
        assert r['detail_skill'] == 1 and r['detail_skill_rating'] == 15 and r['detail_skill_name'] == 'Legendary Miner'
        assert ok(call(28, detail_index=0))['citizens'][2]['detail_member'] == 0
        assert r['top_skill'] is None
        for selector in (1,2):
            ok(edit(edit=selector))
            assert lua.globals().wd[0]['icon'] == icon
    r = ok(call(28))['citizens'][1]
    assert r['detail_member'] == -1 and r['detail_skill'] == -1 and r['detail_skill_name'] == ''
    assert values(observed()['labor_names']) == ['Mining']
    icon = lua.globals().wd[0]['icon']
    retired = ok(edit(65))['retired'][1]
    assert retired['icon'] == icon
    helper = reset()
    for kind in ('resident', 'visitor', 'merchant', 'diplomat'):
        lua.execute(f'citizens[1].citizen=false;citizens[1].{kind}=true')
        assert len(ok(call(28))['citizens']) == 1
        refused(call(29, unit_id=1), 'Citizen no longer available')
        refused(edit(32, unit_id=1, member=1), 'Not an active surviving citizen')
        refused(call(67, unit_id=1, only_assigned=1, expected_revision=1), 'Not an active surviving citizen')
    helper = reset(d=17)
    r = ok(call(30, expected_list_revision=0));assert len(r['details']) == 16
    rev = r['detail_list_revision'];assert ok(call(30))['detail_list_revision'] == rev
    assert len(ok(call(30, cursor=16, expected_list_revision=rev))['details']) == 1
    ok(edit(edit=1, name='Changed'))
    assert observed(1)['name'] == 'Custom' and ok(call(30))['detail_list_revision'] != rev
    refused(call(30, cursor=16, expected_list_revision=rev), 'List changed; refresh')
    for index in range(17):
        assert observed(index)['editable']
        ok(edit(index=index, edit=1, name=f'Detail {index}'))
    # Exercise the actual private finalizer, including unsigned-high-bit and zero cases.
    lua.globals().test_helper = helper
    lua.execute('''
    local seen={}
    local function find(f,name)
      if seen[f]then return end;seen[f]=true
      for i=1,100 do local key,value=debug.getupvalue(f,i);if not key then break end
        if key==name then return value end
        if type(value)=='function'then local found=find(value,name);if found then return found end end
      end
    end
    local finalize=assert(find(test_helper,'revision'))
    assert(finalize(0)==1 and finalize(0x8000000000000000)==1)
    assert(finalize(0xffffffffffffffff)==0x7fffffffffffffff)
    ''')
    helper = reset(d=17)
    rev = ok(call(30))['detail_list_revision']
    lua.execute("wd[0].name=string.rep('x',513)")
    r = ok(call(30));assert r['next_cursor'] == 16 and r['detail_list_revision'] != rev
    assert r['details'][1]['index'] == 0 and r['details'][1]['revision'] > 0
    assert r['details'][1]['row_error'] == 'Row exceeds name cap' and r['details'][2]['name'] == 'Custom'
    ok(edit(edit=1, name='Repaired'))
    lua.execute("wd[0].name=string.rep('x',512)")
    assert not observed()['row_error']
    lua.execute('local ids={};for i=1,1025 do ids[i]=i end;wd[0].assigned_units=vec(ids)')
    r = ok(call(30));assert r['details'][1]['row_error'] == 'Row exceeds assigned_units cap'
    assert len(r['details'][1]['assigned_units']) == 0 and r['details'][2]['name'] == 'Custom'
    ok(edit(edit=1, name='Still targetable'))
    # Lua job strings obey the same cap; social-activity replacement is MSVC-only.
    helper = reset(2)
    lua.execute("citizens[0].job.current_job={job_type=0};dfhack.job.getName=function()return string.rep('x',512)end")
    assert not ok(call(28))['citizens'][1]['row_error']
    lua.execute("dfhack.job.getName=function()return string.rep('x',513)end")
    r = ok(call(28))
    assert r['citizens'][1]['row_error'] == 'Row exceeds job cap' and r['citizens'][2]['name'] == 'Citizen 1'
    helper = reset(5000, 128)
    lua.execute('for _,d in ipairs(wd)do local ids={};for i=1,1024 do ids[i]=i end;d.assigned_units=vec(ids)end')
    r = ok(call(30));assert r['steps'] <= 768 and len(r['details']) == 16
    lua.execute("collectgarbage('collect')")
    print('CITIZENS_CAP_MEMORY_KIB', lua.eval("collectgarbage('count')"))
    assert ok(edit(edit=1, name='Bounded'))['steps'] <= 768
    for action, fields in ((33, {'mode':2}), (66, {'edit':2,'labors':lua.table_from([1])}),
                           (32, {'unit_id':0,'member':1}), (65, {})):
        helper = reset()
        before = ok(call(30))['detail_list_revision']
        assert ok(edit(action, **fields))['detail_list_revision'] != before
    # Filling the last membership slot succeeds; the next insertion is refused intact.
    helper = reset(2)
    lua.execute('local ids={};for i=2,1024 do ids[#ids+1]=i end;wd[0].assigned_units=vec(ids)')
    call_count = len(lua.globals().calls)
    ok(edit(32, unit_id=0, member=1))
    assert len(lua.globals().calls) == call_count+1
    assert len(observed()['assigned_units']) == 1024
    refused(edit(32, unit_id=1, member=1), 'Work-detail membership is full')
    # Captured default sets, with fixture-local enum assignments except the picker exclusions.
    defaults = [ ['MINE'], ['CUTWOOD'], ['HUNT'], ['PLANT'], ['FISH'], ['HERBALIST'],
                 ['STONECUTTER'], ['ENGRAVER'],
                 ['HAUL_STONE','HAUL_WOOD','HAUL_BODY','HAUL_FOOD','HAUL_REFUSE','HAUL_ITEM','HAUL_FURNITURE','HAUL_ANIMALS','HANDLE_VEHICLES','HAUL_TRADE','HAUL_WATER'],
                 ['SUTURING','DRESSING_WOUNDS','FEED_WATER_CIVILIANS','RECOVER_WOUNDED'] ]
    labor_ids = {'MINE':0, 'CUTWOOD':10, 'HUNT':44}
    available = iter(i for i in range(94) if i not in (0,10,44))
    for names in defaults:
        for name in names:
            if name not in labor_ids: labor_ids[name] = next(available)
            lua.globals().df['unit_labor'][name] = labor_ids[name]
            lua.globals().df['unit_labor']['attrs'][labor_ids[name]] = lua.table_from({'caption':name.title().replace('_',' ')})
    for icon, names in enumerate(defaults):
        helper = reset(5000)
        lua.globals().wd[0]['icon'] = icon
        lua.execute('wd[0].flags.no_modify=true;wd[0].assigned_units=vec{0}')
        r = ok(edit(edit=3))
        assert r['active_kinds'] == 16 and r['details'][1]['icon'] == icon
        assert values(r['details'][1]['labors']) == sorted(labor_ids[name] for name in names)
    # Read-only array limits accept the boundary and return an error row above it.
    helper = reset()
    for field, cap in (('roles',32), ('offices',64)):
        for size in (cap, cap+1):
            if field == 'roles':
                lua.execute(f"dfhack.units.getNoblePositions=function()local t={{}};for i=1,{size} do t[i]={{entity={{id=1}},position={{name={{[0]='Manager'}},required_office=250}}}}end;return t end")
            else:
                lua.execute(f'citizens[0].owned_buildings=vec{{}};for i=1,{size} do citizens[0].owned_buildings:insert("#",{{id=i,type=1,office_zone=true}})end')
            row = ok(call(29, unit_id=0))['citizens'][1]
            if size == cap: assert len(row[field]) == cap and not row['row_error']
            else: assert row['row_error'] == f'Row exceeds {field} cap'
        lua.execute('dfhack.units.getNoblePositions=function()return {}end;citizens[0].owned_buildings=vec{}')
    # Recalculation progress is visible in both roster and inspection. Later edits restart it.
    helper = reset(5000, 8)
    ok(edit(edit=2))
    helper(lua.table_from({'step':20, 'kind':4}))
    for action in (28,29):
        r = ok(call(action, unit_id=0));assert 0 < r['recalc_done'] < r['recalc_total'] == 5000
    lua.execute('calls={}')
    restarted = ok(edit(edit=2, labors=lua.table_from([1]), step_budget=64))
    assert lua.globals().calls[1]['id'] == 0 and restarted['recalc_done'] < r['recalc_done']
    lua.execute('calls={}')
    helper = lua.execute(source)
    r = helper(lua.table_from({'restart_recalc':True, 'step':2, 'kind':4}))
    assert lua.globals().calls[1]['id'] == 0 and r['recalc_done'] == 1
    lua.execute('fail_next=true')
    r = helper(lua.table_from({'step':2, 'kind':4}))
    assert r['recalc_error'] == 'Native recalculation failed; labors may be stale' and r['active_kinds'] == 0
    helper = reset(1)
    helper(lua.table_from({'restart_recalc':True, 'step':1, 'kind':4}))
    lua.execute("citizens:insert('#',unit(1))")
    r = helper(lua.table_from({'step':10, 'kind':4}))
    assert r['recalc_done'] == r['recalc_total'] == 1
    # Drive the Lua closure, not the MSVC scheduler. A competitor consumes its slice.
    scheduling_failures = []
    competitor = lua.eval('function(r) assert(r.step>0);return {steps=r.step}end')
    def drive(closure, slice_size):
        return closure(lua.table_from({'step':slice_size, 'kind':4})) if slice_size else None
    assert drive(lambda _: (_ for _ in ()).throw(AssertionError('zero slice called')), 0) is None
    for competing in (False, True):
        helper = reset(5000, 8)
        r = ok(edit(33, mode=1));inline = r['steps'] - 16
        updates = 1
        while r['active_kinds']:
            slice_size = 1024 if competing else 2048
            other_steps = competitor(lua.table_from({'step':1024}))['steps'] if competing else 0
            r = drive(helper, slice_size)
            assert r['steps'] + other_steps <= 2048
            updates += 1
            assert updates < 20
        assert len(lua.globals().calls) == 5000 and r['recalc_done'] == r['recalc_total'] == 5000
        print('CITIZENS_SCHEDULING', 'competing' if competing else 'alone', inline, updates)
        if inline != 2032 or (updates > 9 if competing else updates != 5):
            scheduling_failures.append((competing, inline, updates))
    assert not scheduling_failures, ('mode scheduling (competing, inline, updates)', scheduling_failures)


if __name__ == '__main__':
    main()
