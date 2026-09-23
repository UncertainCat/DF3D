"""Bake screen-independent skill labels/colors from the pinned DFHack enum metadata."""
from pathlib import Path
import json,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2]
def attrs(node):return {a.attrib['name']:a.attrib['value'] for a in node.findall('item-attr')}
prof=ET.parse(root/'external/dfhack/library/xml/df.d_basics.xml').getroot().find("enum-type[@type-name='profession']")
professions={n.attrib['name']:attrs(n) for n in prof.findall('enum-item')}
skills=ET.parse(root/'external/dfhack/library/xml/df.skill_enum.xml').getroot().find("enum-type[@type-name='job_skill']")
rows={};value=-1
for n in skills.findall('enum-item'):
 value=int(n.attrib.get('value',value+1))
 if value<0:continue
 a=attrs(n);p=professions.get(a.get('profession','NONE'),{})
 # Native reference spelling differs from DFHack's nouns for these two.
 name={'PLANT':'Planter','WOODCUTTING':'Woodcutter'}.get(n.attrib['name'],a.get('caption_noun',a.get('caption',n.attrib['name'])))
 rows[str(value)]={'name':name,'color':int(p.get('color','7'))}
 # Verified in creature-native-refine-skills-combat.png. DFHack classifies
 # these as Personal, but native creature sheets place them under Combat.
 if n.attrib['name'] in ['DISCIPLINE','SITUATIONAL_AWARENESS']: rows[str(value)]['category']='Combat'
(root/'presentations/godot/project/panels/creature_skills.json').write_text(json.dumps({'source':'Pinned DFHack df.skill_enum.xml and df.d_basics.xml profession attributes','skills':rows},indent=2)+'\n')
print(len(rows),'skills')
