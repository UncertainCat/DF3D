"""Read-only Steam DF 53.16 creature Needs text/rule evidence. Never calls native code."""
import os
import argparse, hashlib, json, re, struct
from pathlib import Path
import capstone
import pefile
EXPECTED='205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7'
a=argparse.ArgumentParser();a.add_argument('--exe',default=os.path.join(os.environ.get('DF3D_DF_PATH', 'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'), 'Dwarf Fortress.exe'));a.add_argument('--output',default='build/native-creature-prose.json');args=a.parse_args()
raw=Path(args.exe).read_bytes();digest=hashlib.sha256(raw).hexdigest()
if digest!=EXPECTED:raise SystemExit('Unsupported executable: expected Steam DF 53.16')
p=pefile.PE(data=raw);c=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64);c.detail=True

def instructions(start,end):return list(c.disasm(p.get_data(start,end-start),start))
def text_at(rva):return p.get_data(rva,512).split(b'\0')[0].decode('ascii')
def literal(ins):
 for op in ins.operands:
  if op.type==capstone.x86.X86_OP_MEM and op.mem.base==capstone.x86.X86_REG_RIP:
   rva=ins.address+ins.size+op.mem.disp
   try:
    t=text_at(rva)
    if t and all(32<=ord(ch)<127 for ch in t):return {'text':t,'string_rva':hex(rva),'file_offset':p.get_offset_from_rva(rva),'instruction_rva':hex(ins.address)}
   except (UnicodeDecodeError,pefile.PEFormatError):pass
 return None

def at(address):return literal(instructions(address,address+15)[0])
entry=list(struct.unpack('<30I',p.get_data(0x481e14,120)));ends=sorted(set(entry))+[0x47fffd]
names=re.findall(r'^\s*(\w+), // \d+,',Path('external/dfhack/library/include/df/need_type.h').read_text(),re.M)
needs=[]
for n,start in enumerate(entry):
 end=ends[ends.index(start)+1]
 clauses=[v for ins in instructions(start,end) if (v:=literal(ins)) and v['text'].startswith('after ')]
 if n==2:
  needs.append(dict(id=n,key=names[n],case_rva=hex(start),positive_deity=clauses[0],positive_no_deity=clauses[1],negative=clauses[2],negative_deity_connector=at(0x47fc80)))
 else:
  assert len(clauses)==2,(n,clauses)
  needs.append(dict(id=n,key=names[n],case_rva=hex(start),positive=clauses[0],negative=clauses[1]))
tier_addresses=[0x47fb44,0x47fb52,0x47fb60,0x47fb6d,0x47fb7b,0x47fb89,0x47fb97]
tiers=[dict(tier=3-i,**at(address),color=col) for i,(address,col) in enumerate(zip(tier_addresses,[[2,0,1],[2,0,0],[7,0,1],[7,0,0],[6,0,0],[6,0,1],[4,0,1]]))]
result={'executable_sha256':digest,'native_sheet_formatter_rva':'0x47f680','warning':'Native function writes a viewsheet. Reuse the extracted rules, never call it in runtime adapters.',
 'needs':needs,'tiers':tiers,'tier_rules':[['>=',300,3],['>=',200,2],['>=',100,1],['<=',-100000,-3],['<=',-10000,-2],['<=',-1000,-1],['otherwise',0,0]],
 'positive_clause':'tier > 0','sentence_joiner':at(0x47fb2f),'sentence_suffix':at(0x480002),
 'overall_prefix':at(0x47f85e),'overall':[at(x) for x in [0x47f8c2,0x47f8d0,0x47f8f0,0x47f8fe,0x47f90c,0x47f91b,0x47f924]],
 'evidence':{name:[f'{i.address:08x} {i.mnemonic} {i.op_str}' for i in instructions(start,end)] for name,start,end in [('focus_thresholds',0x47f9f0,0x47fa41),('focus_colors',0x47fa94,0x47fafc),('need_switch',0x47fbb7,0x47fbd0),('overall_ratio',0x14d720,0x14d753)]}}
overview=[]
for category,count,positive_table,negative_table in [('physical',6,0x19ec70,0x19ec88),('mental',13,0x19eca0,0x19ecd4)]:
 positive=struct.unpack(f'<{count}I',p.get_data(positive_table,count*4))
 negative=struct.unpack(f'<{count}I',p.get_data(negative_table,count*4))
 for n,(pos,neg) in enumerate(zip(positive,negative)):
  plus,minus=at(pos),at(neg)
  assert plus and minus,(category,n)
  overview.append(dict(category=category,id=n,positive=plus,negative=minus))
result['overview_attribute_labels']=overview
summary=[]
for category,count,positive_table,negative_table in [('facet',50,0x19ed08,0x19edd0),('value',33,0x19ee98,0x19ef1c)]:
 positive=struct.unpack(f'<{count}I',p.get_data(positive_table,count*4))
 negative=struct.unpack(f'<{count}I',p.get_data(negative_table,count*4))
 for n,(pos,neg) in enumerate(zip(positive,negative)):
  plus,minus=at(pos),at(neg)
  assert plus and minus,(category,n)
  summary.append(dict(category=category,id=n,positive=plus,negative=minus))
result['overview_personality_labels']=summary
physical=[]
case_starts=list(struct.unpack('<6I',p.get_data(0x1381190,24)))
for n,start in enumerate(case_starts):
 end=case_starts[n+1] if n+1<len(case_starts) else 0x1380f9f
 bands=[];pending=None
 for ins in instructions(start,end):
  if ins.mnemonic=='cmp' and ins.op_str.startswith('edi, '):
   pending=int(ins.op_str.split(', ')[1],0)
  elif pending is not None and (value:=literal(ins)):
   bands.append(dict(threshold=pending,**value));pending=None
 assert [x['threshold'] for x in bands]==[100,75,50,25,-100,-75,-50,-25],(n,bands)
 physical.append(dict(id=n,bands=bands))
result['physical_long_attribute_labels']=physical
mental=[]
mental_starts=list(struct.unpack('<13I',p.get_data(0x1382300,52)))
for n,start in enumerate(mental_starts):
 end=mental_starts[n+1] if n+1<len(mental_starts) else 0x13820f8
 bands=[];pending=None
 for ins in instructions(start,end):
  if ins.mnemonic=='cmp' and ins.op_str.startswith('ebx, '):
   pending=int(ins.op_str.split(', ')[1],0)
  elif pending is not None and (value:=literal(ins)):
   band=dict(threshold=pending,**value)
   if n==10 and pending in (100,50,-100):
    band['append_possessive']=True;band['suffix']=at(0x1381f5a)
   bands.append(band);pending=None
 assert [x['threshold'] for x in bands]==[100,75,50,25,-100,-75,-50,-25],(n,bands)
 mental.append(dict(id=n,bands=bands))
result['mental_long_attribute_labels']=mental
result['mental_long_joiners']={name:at(address) for name,address in [
 ('positive_color',0x138211c),('negative_color',0x1382125),('has',0x1382156),
 ('sign_change_prefix',0x138217a),('but',0x13821a8),('comma',0x13821fe),
 ('and',0x138220b),('space',0x138222a),('suffix',0x138225e)]}
# Symbolically follow only the finite base-facet switch. This interprets its
# string concatenations, never executes native code, and stops before memory,
# cultural-conflict, and temporary-change narrative additions.
facet_code={i.address:i for i in instructions(0xe273d9,0xe299c3)}
facet_starts=struct.unpack('<50I',p.get_data(0xe2be84,200))
def facet_base(start,trait,code=facet_code,stop=0xe299c3,pronouns=None):
 regs={};locals_=dict(pronouns or {-8:[{'pronoun':'subject'}],0x118:[{'pronoun':'object'}],
  0x18:[{'pronoun':'possessive'}],0xf8:[{'pronoun':'reflexive'}]});out=[];comparison=None
 def resolve(value):
  if isinstance(value,tuple):return locals_[value[1]]
  return value
 pc=start
 for step in range(500):
  if pc==stop:return out
  ins=code[pc];pc+=ins.size;ops=ins.operands
  if ins.mnemonic=='cmp':
   assert ins.op_str.startswith(('ax, ','ebx, ')),(hex(ins.address),ins.op_str)
   comparison=trait-ops[1].imm
  elif ins.mnemonic in ('jle','jl','jge','jg','jmp'):
   take=ins.mnemonic=='jmp' or {'jle':comparison<=0,'jl':comparison<0,'jge':comparison>=0,'jg':comparison>0}.get(ins.mnemonic,False)
   if take:pc=ops[0].imm
  elif ins.mnemonic=='lea':
   dest=ins.reg_name(ops[0].reg);mem=ops[1].mem
   if mem.base==capstone.x86.X86_REG_RIP:
    value=literal(ins);assert value,(hex(ins.address),ins.op_str)
    regs[dest]=[value]
   elif mem.base==capstone.x86.X86_REG_RBP:regs[dest]=('local',mem.disp)
   else:raise AssertionError((hex(ins.address),ins.op_str))
  elif ins.mnemonic=='mov' and ops[0].type==ops[1].type==capstone.x86.X86_OP_REG:
   source=ins.reg_name(ops[1].reg)
   if source in regs:regs[ins.reg_name(ops[0].reg)]=regs[source]
  elif ins.mnemonic=='call':
   target=ops[0].imm
   if target in (0x14af80,0x14abf0,0xeb0b0):
    value=resolve(regs['rdx'])+resolve(regs['r8']);dest=regs['rcx']
    assert isinstance(dest,tuple)
    locals_[dest[1]]=value;regs['rax']=dest
   elif target in (0x6f560,0xb9d10,0x6fa10):out+=resolve(regs['rdx'])
   else:assert target in (0x67e30,0x6f850),(hex(ins.address),hex(target))
  else:assert ins.mnemonic in ('movzx','nop','mov'),(hex(ins.address),ins.mnemonic)
 raise AssertionError('Base facet path did not terminate')
result['facet_base_descriptions']=[dict(id=n,bands=[dict(tier=tier,parts=facet_base(start,trait))
 for tier,trait in [(3,95),(2,80),(1,65),(-1,30),(-2,15),(-3,5)]]) for n,start in enumerate(facet_starts)]
assert all(b['parts'] for f in result['facet_base_descriptions'] for b in f['bands'])
for n,start in enumerate(facet_starts):
 expected={b['tier']:b['parts'] for b in result['facet_base_descriptions'][n]['bands']}
 for trait in range(101):
  tier=3 if trait>90 else 2 if trait>75 else 1 if trait>60 else 0 if trait>=40 else -1 if trait>=25 else -2 if trait>=10 else -3
  if tier:assert facet_base(start,trait)==expected[tier],(n,trait)
result['facet_base_joiners']={'color':at(0xe26da4),'subject_separator':at(0xe26d79),'suffix':at(0xe2af08)}
value_code={i.address:i for i in instructions(0xe251d2,0xe2670b)}
value_starts=struct.unpack('<33I',p.get_data(0xe26be8,132))
def value_base(n,strength):
 pronouns={0x88:[{'pronoun':'subject'}],0x48:[{'pronoun':'object'}],8:[{'pronoun':'possessive'}],0x28:[{'pronoun':'reflexive'}],
  -0x38:[{'field':'craftsman_term'},at(0xe25e32)]}
 if n==20 and strength>40:return [at(0xe25ed0)]+pronouns[-0x38]+[at(0xe25f03)]
 start=0xe25fcf if n==20 else value_starts[n]
 return facet_base(start,strength,value_code,0xe2670b,pronouns)
result['value_base_descriptions']=[dict(id=n,bands=[dict(tier=tier,parts=value_base(n,strength))
 for tier,strength in [(3,45),(2,30),(1,15),(0,0),(-1,-15),(-2,-30),(-3,-45)]]) for n in range(33)]
result['craftsman_fallback']=at(0xe25e11)
result['value_base_joiners']={name:at(address) for name,address in [
 ('culture_color',0xe24ea4),('personal_color',0xe2511f),('culture_prefix',0xe24f39),
 ('culture_connector',0xe24f83),('personally',0xe2514e),('subject_separator',0xe25094),
 ('and',0xe2693f),('comma',0xe2694e),('suffix',0xe26928)]}
dreams=[]
for goal,start in enumerate(struct.unpack('<13I',p.get_data(0xe26c6c,52)),2):
 if goal==11:continue
 text=next(literal(i) for i in instructions(start,start+20) if literal(i))
 dreams.append(dict(id=goal,**text))
assert len(dreams)==12
result['dream_descriptions']=dreams
result['dream_joiners']={'color':at(0xe26a1c),'accomplished':at(0xe26b51),'suffix':at(0xe26b66)}
# Recent Thoughts tables. The index is emotion_type + 1 (slot 0 is neutral).
emotion_code={i.address:i for i in instructions(0x1a74d8,0x1a7c66)}
def emotion_word(start,past):
 pc=start
 for _ in range(30):
  if pc==0x1a7c66:return None
  i=emotion_code[pc];pc+=i.size
  if i.mnemonic=='lea' and (v:=literal(i)):return v
  if i.mnemonic=='je':
   if not past:pc=i.operands[0].imm
  elif i.mnemonic=='jmp':pc=i.operands[0].imm
 raise AssertionError(hex(start))
verbs={0x1a74d8:(0x1a74df,0x1a74d8),0x1a74fc:(0x1a7503,0x1a74fc),
 0x1a750c:(0x1a7513,0x1a750c),0x1a748b:(0x1a751c,0x1a749c)}
verb_starts=struct.unpack('<5I',p.get_data(0x1a81f8,20));verb_map=p.get_data(0x1a820c,170)
color_starts=struct.unpack('<9I',p.get_data(0x1a82b8,36));color_map=p.get_data(0x1a82dc,170)
word_starts=struct.unpack('<170I',p.get_data(0x1a8388,680))
recall_starts=struct.unpack('<4I',p.get_data(0x1a8630,16));recall_map=p.get_data(0x1a8640,169)
result['emotion_descriptions']=[]
for slot in range(170):
 v=verbs.get(verb_starts[verb_map[slot]])
 color_start=color_starts[color_map[slot]]
 result['emotion_descriptions'].append(dict(id=slot-1,
  present_verb=at(v[0]) if v else None,past_verb=at(v[1]) if v else None,
  color=at(color_start) if color_start!=0x1a7611 else None,
  present=emotion_word(word_starts[slot],False),past=emotion_word(word_starts[slot],True),
  recall=at(recall_starts[recall_map[slot-1]]) if slot else at(0x1a7cc3)))
result['emotion_joiners']={name:at(address) for name,address in [
 ('past_color',0x1a7390),('present_color',0x1a73ad),('space',0x1a7460),
 ('past_recall_color',0x1a7c7a),('present_recall_color',0x1a7c83),
 ('past_circumstance_color',0x1a7e87),('present_circumstance_color',0x1a7e90),('suffix',0x1a7ec5)]}
thought_code={i.address:i for i in instructions(0xe2c4d1,0xe32069)}
thought_starts=struct.unpack('<281I',p.get_data(0xe32098,1124))
def static_thought(start,prefix):
 pc=start;parts=[];text=None
 for _ in range(80):
  if pc==0xe32069:return parts
  i=thought_code.get(pc)
  if i is None:return None
  pc+=i.size
  if i.mnemonic=='cmp':
   if i.op_str!='byte ptr [rbp + 0xe8], 0':return None
  elif i.mnemonic=='je':
   if not prefix:pc=i.operands[0].imm
  elif i.mnemonic=='jmp':pc=i.operands[0].imm
  elif i.mnemonic=='lea':
   text=literal(i)
   if not text or not i.op_str.startswith('rdx,'):return None
  elif i.mnemonic=='call':
   if i.operands[0].imm not in (0x6f560,0x6fa10) or text is None:return None
   parts.append(text);text=None
  elif i.mnemonic=='mov':
   if not(i.op_str=='rcx, rbx' or i.op_str.startswith('r8d, ')):return None
  elif i.mnemonic!='nop':return None
 return None
result['thought_static_descriptions']=[]
for n,start in enumerate(thought_starts):
 normal=static_thought(start,True);recalled=static_thought(start,False)
 if normal and recalled:result['thought_static_descriptions'].append(dict(id=n,normal=normal,recalled=recalled))
result['thought_subthought_descriptions']=[]
for thought,table,count,base in [(180,0xe32a78,30,0),(271,0xe32808,17,1),(272,0xe3284c,17,1),(273,0xe32890,17,1)]:
 for sub,start in enumerate(struct.unpack(f'<{count}I',p.get_data(table,count*4)),base):
  normal=static_thought(start,True);recalled=static_thought(start,False)
  if normal and recalled:result['thought_subthought_descriptions'].append(dict(id=thought,subthought=sub,normal=normal,recalled=recalled))
for thought,table,count,index_table,index_count,base in [(112,0xe326dc,7,0xe326f8,228,11),(179,0xe32a18,11,0xe32a44,51,1)]:
 targets=struct.unpack(f'<{count}I',p.get_data(table,count*4));indexes=p.get_data(index_table,index_count)
 for sub,index in enumerate(indexes,base):
  normal=static_thought(targets[index],True);recalled=static_thought(targets[index],False)
  if normal and recalled:result['thought_subthought_descriptions'].append(dict(id=thought,subthought=sub,normal=normal,recalled=recalled))
skill_starts=struct.unpack('<137I',p.get_data(0x77450c,548))
result['thought_skill_labels']=[dict(id=n,**next(literal(i) for i in instructions(start,start+24) if literal(i)))for n,start in enumerate(skill_starts)]
result['thought_skill_descriptions']=[dict(id=n,normal=[at(prefix),at(verb)],recalled=[at(verb)])for n,prefix,verb in [
 (215,0xe2cad9,0xe2cae8),(11,0xe2cb3a,0xe2cb49),(199,0xe30159,0xe30168),(192,0xe3023d,0xe3024c)]]
result['thought_quality_descriptions']=[dict(id=216,severity=severity,
 normal=[at(0xe2ef20),at(0xe2ef2f)]+static_thought(start,True),
 recalled=[at(0xe2ef2f)]+static_thought(start,False))for severity,start in [(1,0xe2efe5),(2,0xe2efc2),(3,0xe2ef9f),(4,0xe2ef7f),(None,0xe2ef5f)]]
for thought,table,prefix,verb in [(148,0xe327dc,0xe2fe0e,0xe2fe1d),(106,0xe326b0,None,0xe2f272)]:
 for severity,start in enumerate(struct.unpack('<11I',p.get_data(table,44)),-5):
  parts=static_thought(start,False)
  if parts:result['thought_quality_descriptions'].append(dict(id=thought,severity=severity,
   normal=([at(prefix)]if prefix else[])+[at(verb)]+parts,recalled=[at(verb)]+parts))
for severity,start in [(1,0xe2f0a2),(2,0xe2f08e),(3,0xe2f07a),(4,0xe2f066),(5,0xe2f052)]:
 parts=static_thought(start,False)
 result['thought_quality_descriptions'].append(dict(id=97,severity=severity,normal=[at(0xe2f011),at(0xe2f020)]+parts,recalled=[at(0xe2f020)]+parts))
result['thought_romance']={'id':12,'normal_before_pronoun':[at(0xe2cbf7)],
 'normal_after_pronoun':[at(0xe2cc52),at(0xe2cc6b),at(0xe2cc7a)],'recalled':[at(0xe2cc7a)]}
result['thought_performance']=[{'id':188,'normal_prefix':[at(0xe2c997)],'ordinary':at(0xe2c9ef),'sermon':at(0xe2c9db)},
 {'id':189,'normal_prefix':[at(0xe2ca0c)],'ordinary':at(0xe2ca64),'sermon':at(0xe2ca50)}]
ghost_targets=struct.unpack('<11I',p.get_data(0xe325cc,44));ghost_indexes=p.get_data(0xe325f8,51)
def ghost_tail(start):
 return next(literal(i)for i in instructions(start,start+63)if literal(i)and literal(i)['text'].startswith(' by '))
result['thought_ghost']={'id':40,'normal':[at(0xe2def2),at(0xe2df01)],'recalled':[at(0xe2df01)],
 'verbs':[dict(severity=n,**at(a))for n,a in enumerate([0xe2daf8,0xe2daef,0xe2dae6,0xe2dadd])],
 'relations':[dict(subthought=n,**ghost_tail(ghost_targets[index]))for n,index in enumerate(ghost_indexes,1)
  if ghost_tail(ghost_targets[index])['text']!=' by '],
 'unresolved_relations':[n for n,index in enumerate(ghost_indexes,1)if ghost_tail(ghost_targets[index])['text']==' by '],
 'default_tail':at(0xe2df1c)}
result['thought_prayer']={'id':180,'subthought':2,'normal':[at(0xe31723),at(0xe31732)],
 'recalled':[at(0xe31732)],'subject_connector':at(0xe3174c),'suffix':at(0xe3178e)}
result['thought_dead_body']={'id':240,'normal':[at(0xe2c6d6),at(0xe2c6eb)],'recalled':[at(0xe2c6eb)],
 'anonymous_prefix':at(0xe2c7ff),'possessive':at(0xe2c836),'unknown':at(0xe2c866),'suffix':at(0xe2c84f)}
result['thought_syndrome']={'id':187,'normal':[at(0xe2e31f)],'recalled':[]}
result['thought_victory']={'id':280,'normal':[at(0xe3056c),at(0xe3057b)],'recalled':[at(0xe3057b)],'location_connector':at(0xe3059f)}
result['thought_building']={'id':27,'normal':[at(0xe2d384),at(0xe2d39e),at(0xe2d431)],
 'recalled':[at(0xe2d39e),at(0xe2d431)],'space':at(0xe2d487),
 'quality':[dict(minimum=n,**at(a))for n,a in [(0,0xe2d502),(128,0xe2d4f6),(256,0xe2d4ed),(384,0xe2d4e4),(512,0xe2d475)]]}
result['thought_building_labels']=[]
for n,start in enumerate(struct.unpack('<55I',p.get_data(0x54e7c4,220))):
 code=instructions(start,start+16)
 if len(code)>=2 and code[0].mnemonic=='mov' and code[0].op_str.startswith('r8d, ') and (v:=literal(code[1])):
  result['thought_building_labels'].append(dict(id=n,**v))
memory_code={i.address:i for i in instructions(0x482cf9,0x4842d4)}
memory_words=struct.unpack('<170I',p.get_data(0x4844bc,680))
memory_color_starts=struct.unpack('<9I',p.get_data(0x4843ec,36));memory_colors=p.get_data(0x484410,170)
memory_recall_starts=struct.unpack('<4I',p.get_data(0x48482c,16));memory_recalls=p.get_data(0x48483c,169)
def memory_parts(slot):
 pc=memory_words[slot];parts=[];pending=None
 for _ in range(50):
  if pc==0x482d57:return parts
  if pc==0x483a62:
   parts.append(at(0x483a68))
   pc=memory_recall_starts[memory_recalls[slot-1]] if slot else 0x482d3a
  i=memory_code[pc];pc+=i.size
  if i.mnemonic=='lea' and i.op_str.startswith('rdx,'):pending=literal(i)
  elif i.mnemonic=='call':
   assert i.operands[0].imm in (0x6fa10,0x6f560) and pending,(hex(i.address),i.op_str)
   parts.append(pending);pending=None
  elif i.mnemonic=='jmp':pc=i.operands[0].imm
  else:assert i.mnemonic in ('lea','mov'),(hex(i.address),i.op_str)
 raise AssertionError(slot)
result['memory_descriptions']=[]
for slot in range(170):
 start=memory_color_starts[memory_colors[slot]]
 color=next((literal(i)for i in instructions(start,start+16)if literal(i)),None) if start!=0x482cd6 else None
 result['memory_descriptions'].append(dict(id=slot-1,color=color,parts=memory_parts(slot)))
def memory_facet(start,positive):
 pc=start
 for _ in range(12):
  i=memory_code[pc];pc+=i.size
  if i.mnemonic=='lea' and (v:=literal(i)):return v
  if i.mnemonic=='jle' and not positive:pc=i.operands[0].imm
 raise AssertionError(start)
result['memory_facet_changes']=[dict(id=n,increase=memory_facet(start,True),decrease=memory_facet(start,False))for n,start in enumerate(struct.unpack('<50I',p.get_data(0x484764,200)))]
result['memory_value_labels']=[dict(id=n,**at(start))for n,start in enumerate(struct.unpack('<33I',p.get_data(0x4848e8,132)))]
result['memory_joiners']={name:at(address)for name,address in [
 ('circumstance_color',0x482d5d),('suffix',0x482da5),('effect_color',0x482ddd),('became',0x482e06),
 ('and_learned',0x4840eb),('learned',0x484114),('value',0x484105),('disdain',0x48411d),
 ('effect_suffix',0x4842c4),('before_time',0x4827a7),('year_separator',0x4829ad)]}
# Personality causes scan all cores in source order and retain the last match.
result['personality_cause_joiners']={kind:{name:at(address) for name,address in entries} for kind,entries in {
 'value':[('prefix',0xe2676b),('color',0xe2678d),('open',0xe267a2),('turn',0xe26855),('strengthen',0xe26874),('moderate',0xe2688d),('due',0xe2689c),('year',0xe268d1),('close',0xe268f1),('restore',0xe2690b)],
 'facet':[('prefix',0xe29a4e),('color',0xe29a6a),('turn',0xe29b17),('strengthen',0xe29b30),('moderate',0xe29b43),('after',0xe29b52),('year',0xe29b87),('restore',0xe29bc9)]}.items()}
assert all(v for group in result['personality_cause_joiners'].values() for v in group.values())
temporary_code={i.address:i for i in instructions(0xe2b7ec,0xe2bdd5)}
def temporary_facet(start,increase):
 pc=start
 for _ in range(12):
  i=temporary_code[pc];pc+=i.size
  if i.mnemonic=='lea' and (v:=literal(i)):return v
  if i.mnemonic=='jle' and not increase:pc=i.operands[0].imm
 raise AssertionError(start)
result['facet_temporary_descriptions']=[dict(id=n,increase=temporary_facet(start,True),decrease=temporary_facet(start,False)) for n,start in enumerate(struct.unpack('<50I',p.get_data(0xe2bfbc,200)))]
# Follow the conflict switch using numeric resident values and original string
# concatenation calls. All comparison thresholds are 40/60 (facet), -10/10
# (value); count registers select combined-conflict wording.
conflict_code={i.address:i for i in instructions(0xe29bfe,0xe2b709)}
conflict_targets=struct.unpack('<15I',p.get_data(0xe2bf4c,60))
conflict_starts=[conflict_targets[v] for v in p.get_data(0xe2bf88,50)]
conflict_values={0x64:0,0x68:1,0x50:3,0x58:4,0x54:9,0x70:11,0x6c:13,0x5c:14,0x44:16,0x38:17,0x34:18,0x40:19,0x48:21,0x60:24,0x4c:26,0x3c:29,0x74:30}
def facet_conflict(start,trait,values):
 regs={};locals_={-8:[{'pronoun':'subject'}],0x118:[{'pronoun':'object'}],0x18:[{'pronoun':'possessive'}],0xf8:[{'pronoun':'reflexive'}]};out=[];comparison=0;used=set()
 def resolve(v):return locals_[v[1]] if isinstance(v,tuple) else v
 def read(op):
  if op.type==capstone.x86.X86_OP_IMM:return op.imm
  if op.type==capstone.x86.X86_OP_REG:return regs.get(c.reg_name(op.reg))
  if op.mem.base==capstone.x86.X86_REG_R15:return trait
  assert op.mem.base==capstone.x86.X86_REG_RSP,op.mem.base
  assert op.mem.disp in conflict_values,(hex(i.address),i.op_str)
  key=conflict_values[op.mem.disp];used.add(key);return values.get(key,0)
 pc=start
 for _ in range(1000):
  if pc in (0xe2aefd,0xe2af02):return out,used
  i=conflict_code[pc];pc+=i.size;o=i.operands;m=i.mnemonic
  if m=='cmp':comparison=read(o[0])-read(o[1])
  elif m in ('jle','jl','jge','jg','je','jne','jb','jmp'):
   if m=='jmp' or {'jle':comparison<=0,'jl':comparison<0,'jge':comparison>=0,'jg':comparison>0,'je':comparison==0,'jne':comparison!=0,'jb':comparison<0}.get(m,False):pc=o[0].imm
  elif m=='lea':
   dest=i.reg_name(o[0].reg);mem=o[1].mem
   if mem.base==capstone.x86.X86_REG_RIP:
    v=literal(i);assert v,hex(i.address);regs[dest]=[v]
   else:
    assert mem.base==capstone.x86.X86_REG_RBP,hex(i.address)
    regs[dest]=('local',mem.disp)
  elif m=='mov':regs[i.reg_name(o[0].reg)]=read(o[1])
  elif m=='xor':regs[i.reg_name(o[0].reg)]=0
  elif m=='inc':regs[i.reg_name(o[0].reg)]+=1
  elif m in ('cmovg','cmovl'):
   if (comparison>0 if m=='cmovg' else comparison<0):regs[i.reg_name(o[0].reg)]=read(o[1])
  elif m=='call':
   target=o[0].imm
   if target in (0x14af80,0x14abf0,0xeb0b0):
    v=resolve(regs['rdx'])+resolve(regs['r8']);dest=regs['rcx'];assert isinstance(dest,tuple)
    locals_[dest[1]]=v;regs['rax']=dest
   elif target in (0x6f560,0xb9d10,0x6fa10):out+=resolve(regs['rdx'])
   else:assert target in (0x67e30,0x6f850),(hex(i.address),hex(target))
  else:assert m=='nop',(hex(i.address),m)
 raise AssertionError('Conflict path did not terminate')
import itertools
result['facet_value_conflicts']=[]
for n,start in enumerate(conflict_starts):
 if start==0xe2af02:continue
 _,used=facet_conflict(start,50,{})
 # Some secondary values load only when a prior branch survives. Discover all.
 for _ in range(3):
  probe_keys=sorted(used)
  for vals in itertools.product((-11,0,11),repeat=len(probe_keys)):
   for trait in (39,50,61):used|=facet_conflict(start,trait,dict(zip(probe_keys,vals)))[1]
 keys=sorted(used)
 for vals in itertools.product((-11,0,11),repeat=len(keys)):
  for trait in (39,50,61):
   parts,_=facet_conflict(start,trait,dict(zip(keys,vals)))
   if not parts:continue
   bounds=({'facet_max':39} if trait==39 else {'facet_min':61} if trait==61 else {'facet_min':40,'facet_max':60})
   predicates=[dict(value_id=k,**({'max':-11} if v<0 else {'min':11} if v>0 else {'min':-10,'max':10}))for k,v in zip(keys,vals)]
   result['facet_value_conflicts'].append(dict(facet_id=n,**bounds,values=predicates,parts=parts))
# Exercise every boundary and adjacent value for single-value arms; enumerate
# representative multi-value regions above so combined-conflict clauses survive.
for n,start in enumerate(conflict_starts):
 rules=[r for r in result['facet_value_conflicts'] if r['facet_id']==n]
 if not rules:continue
 keys=sorted({v['value_id'] for r in rules for v in r['values']})
 for trait in (0,39,40,50,60,61,100):
  for vals in itertools.product((-50,-11,-10,0,10,11,50),repeat=len(keys)):
   state=dict(zip(keys,vals))
   matched=[r for r in rules if r.get('facet_min',0)<=trait<=r.get('facet_max',100) and all(v.get('min',-50)<=state[v['value_id']]<=v.get('max',50) for v in r['values'])]
   assert len(matched)<=1,(n,trait,state)
   actual,_=facet_conflict(start,trait,state)
   assert (matched[0]['parts'] if matched else [])==actual,(n,trait,state)
result['facet_value_conflicts_unresolved']=[]
result['overview_need_labels']=[dict(id=n,**at(address))for n,address in enumerate([
 0x167e94,0x167ed7,0x167fe5,0x168098,0x1680db,0x16811e,0x168161,0x1681a4,0x1681e7,0x16822a,
 0x16826d,0x1682b0,0x1682f3,0x168336,0x168379,0x1683bc,0x1683ff,0x168442,0x168485,0x1684c8,
 0x16850b,0x16854e,0x168591,0x1685d4,0x168617,0x16865a,0x16869d,0x1686e0,0x168723,0x168763])]
# ThinkAbstractly is a separate tail case in this executable's 30-entry table;
# derive actual IDs from the switch rather than assuming contiguous text order.
need_targets=struct.unpack('<30I',p.get_data(0x19efa0,120))
need_addresses=[r['instruction_rva'] for r in result['overview_need_labels']]+['0x1687a3']
result['overview_need_labels']=[dict(id=n,**at(next(int(a,16)for a in need_addresses if start<=int(a,16)<(sorted(set(need_targets))+[0x1687e1])[sorted(set(need_targets)).index(start)+1])))for n,start in enumerate(need_targets)]
result['overview_need_joiners']={'prefix':at(0x167d5c),'none':at(0x167ca2),'prayer_deity':at(0x168025),'meditate':at(0x168098)}
result['skill_rust_labels']={'very_rusty':at(0x167431),'rusty':at(0x16749d)}
result['personality_condition_joiners']={name:at(address)for name,address in [
 ('color',0x481946),('alcohol',0x48198f),('alcohol_far',0x481a1d),('alcohol_wants',0x481a2d),('alcohol_slow',0x481a3d),
 ('alcohol_forgot_before',0x4819ab),('alcohol_forgot_after',0x4819f4),('suffix',0x481a56),
 ('outdoors2',0x481b03),('outdoors1',0x481b35),('hardened100',0x481bdc),('hardened67',0x481c13),('hardened33',0x481c4a)]}
result['mannerism_descriptions']=[
 dict(id=13,situation=11,parts=[{'pronoun':'subject_capitalized'},at(0x10e33ef),at(0x10e465b),{'pronoun':'subject'},at(0x10e4677)]),
 dict(id=63,situation=11,parts=[{'pronoun':'subject_capitalized'},at(0x10e33ef),at(0x10e7f33),{'pronoun':'subject'},at(0x10e4e2a)])]
result['mannerism_suffix']=at(0x10e80da)
result['facet_temporary_joiners']={name:at(address) for name,address in [('color',0xe2b7a1),('currently',0xe2b7bf),('suffix',0xe2bdda),('restore',0xe2bdee)]}
result['memory_seasons']=[at(a)for a in [0x482970,0x48294b,0x482926,0x482901]]
result['preference_joiners']={name:at(address) for name,address in [
 ('color',0x480151),('likes',0x480223),('wood',0x48031e),('fabric',0x480357),
 ('reason',0x480452),('color_prefix',0x48065c),('poetic_prefix',0x480737),
 ('musical_prefix',0x4807ab),('dance_prefix',0x480814),('comma',0x480871),
 ('and',0x48087c),('suffix',0x480885),('food_prefix',0x480984),
 ('food_connector',0x480a37),('hate_connector',0x4812d6)]}
assert all(result['preference_joiners'].values())
# Native item helper a84f60 jumps to a88053, then appends character 0x73
# at a88061 whenever quantity != 1. Preferences passes quantity -1.
result['preference_item_subjects']=[dict(item_type=36,parts=[at(0xa84f60)],suffix_codepoint=0x73)]
for n in range(33):
 expected={b['tier']:b['parts'] for b in result['value_base_descriptions'][n]['bands']}
 for strength in range(-50,51):
  tier=3 if strength>40 else 2 if strength>25 else 1 if strength>10 else 0 if strength>=-10 else -1 if strength>=-25 else -2 if strength>=-40 else -3
  assert value_base(n,strength)==expected[tier],(n,strength)
result['health_empty_labels']={name:at(address) for name,address in [
 ('Wounds',0x47cdd6),('Treatment',0x47b78c),('History',0x47afdd)]}
result['room_quality_labels']={name:[dict(minimum=value,**at(address)) for value,address in entries] for name,entries in {
 'Bedroom':[(10000,0xab5121),(2500,0xab513b),(1500,0xab5155),(1000,0xab516f),(500,0xab5189),(250,0xab51a3),(100,0xab51ba),(1,0xab51d0),(0,0xab51e2)],
 'Office':[(10000,0xab5202),(2500,0xab521c),(1500,0xab5236),(1000,0xab5250),(500,0xab526a),(250,0xab5284),(100,0xab529b),(1,0xab52b1),(0,0xab52bd)],
 'DiningHall':[(10000,0xab5046),(2500,0xab5060),(1500,0xab507a),(1000,0xab5094),(500,0xab50ae),(250,0xab50c8),(100,0xab50df),(1,0xab50f5),(0,0xab5107)],
 'Tomb':[(10000,0xab4f71),(2500,0xab4f8b),(1500,0xab4fa5),(1000,0xab4fbf),(500,0xab4fd9),(250,0xab4ff3),(100,0xab500a),(1,0xab5020),(0,0xab5032)]}.items()}
result['physical_long_joiners']={name:at(address) for name,address in [
 ('positive_color',0x1380fc3),('negative_color',0x1380fcc),('is',0x1380ffd),
 ('sign_change_prefix',0x1381020),('but',0x138104e),('comma',0x1381093),
 ('and',0x13810a2),('space',0x13810c1),('suffix',0x13810f6)]}
assert all(result['physical_long_joiners'].values())
result['evidence'].update({name:[f'{i.address:08x} {i.mnemonic} {i.op_str}' for i in instructions(start,end)] for name,start,end in [
 ('overview_physical_score',0x1a2bf0,0x1a2caa),('overview_mental_score',0x1a2e80,0x1a2f59),('overview_six_slot_insertion',0x1a31a0,0x1a322d),
 ('personality_gate',0x73710,0x7375c),('overview_cultural_filter',0x1a2540,0x1a26e9),
 ('overview_personal_values',0x1a26e9,0x1a2854),('overview_facets',0x1a2870,0x1a2b53),
 ('physical_paragraph_join',0x1380fa8,0x1381110),
 ('mental_score',0x13812b4,0x138138f),('mental_signed_sort',0x13813e0,0x138140d),
 ('mental_sign_groups',0x1381751,0x13817ab),('mental_paragraph_join',0x1382101,0x138226e)]})
Path(args.output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'needs':len(needs),'tiers':len(tiers),'attribute_pairs':len(overview),'output':args.output}))
