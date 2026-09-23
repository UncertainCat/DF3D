from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
local stdipairs=ipairs
function vec(values)
 local t={};for i,v in stdipairs(values)do t[i-1]=v end
 return setmetatable(t,{__len=function()return #values end})
end
function report(id,text)
 return {id=id,text=text or 'Report '..id,type=0,year=105,time=0,repeat_count=2,flags={continuation=id%2==1},zoom_type=0,zoom_type2=1,pos={x=2,y=3,z=4},pos2={x=2,y=3,z=4}}
end
rows={};for i=0,1099 do rows[#rows+1]=report(i)end
df={announcement_type={[0]='Native category'},report_zoom_type={Generic=0},global={world={status={reports=vec(rows),announcements=vec(rows)}}}}
df.report={find=function(id)for _,r in stdipairs(rows)do if r.id==id then return r end end end}
dfhack={df2utf=function(s)return s end,maps={isValidTilePos=function(p)return p.x>=0 end,getTileFlags=function(p)return {hidden=p.y==99}end}}
function request(seq,id,before,query,only)
 return {seq=seq,action=id>=0 and 35 or 34,report={id=id,before_id=before,query=query or '',announcements_only=only~=false}}
end
''')
helper=lua.execute(Path('bridge/plugin/reports.lua').read_text())
def call(seq=1,id=-1,before=-1,query=''):
    return helper(lua.globals().request(seq,id,before,query,True))
page=call()
assert len(page['reports'])==16 and page['reports'][1]['id']==1099
assert page['next_before_id']==1084
second=call(seq=2,before=page['next_before_id'])
assert second['reports'][1]['id']==1083
zero=call(seq=3,id=0)['reports'][1]
assert zero['id']==0 and zero['repeat_count']==2 and zero['position_visible']
assert not zero['position2_visible'] and zero['x2']==-1
assert call(seq=4,id=1)['reports'][1]['continuation']
lua.execute('rows[1].pos.y=99')
assert not call(seq=5,id=0)['reports'][1]['position_visible']
pending=call(seq=6,query='Report 0')
assert pending['pending']
# Expire old native rows between bounded continuation calls.
lua.execute("table.remove(rows,1);df.global.world.status.announcements=vec(rows)")
pending=call(seq=6,query='Report 0')
while pending['pending']:
    pending=call(seq=6,query='Report 0')
assert len(pending['reports'])==0
lua.execute("rows={};for i=0,19 do rows[#rows+1]=report(i,string.rep('x',20000))end;df.global.world.status.announcements=vec(rows)")
large=call(seq=7)
assert len(large['reports'])==8
assert sum(len(large['reports'][i]['text']) for i in range(1,9))==131072
assert not large['reports'][1]['text_complete']
assert not call(seq=8,id=999999)['ok']
lua.execute("dfhack.df2utf=function(s)return s:gsub('x',utf8.char(0x263a))end")
unicode=call(seq=9,id=0)['reports'][1]
assert len(unicode['text'].encode('utf-8'))==16383
assert unicode['text'].endswith('\u263a') and not unicode['text_complete']
print('NOTIFICATIONS_ADAPTER_PASS')
