"""Convert inspected native text evidence to a distributable offsets-only recipe."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
d=json.loads((root/'build/native-creature-prose.json').read_text());d.pop('evidence',None)
def convert(v):
 if isinstance(v,dict):
  result={k:convert(x) for k,x in v.items() if k not in ['text','string_rva','instruction_rva','file_offset']}
  if 'text' in v:result.update(offset=v['file_offset'],length=len(v['text'].encode('ascii')))
  return result
 if isinstance(v,list):return [convert(x) for x in v]
 return v
(root/'presentations/godot/project/panels/native_creature_text.json').write_text(json.dumps(convert(d),indent=2)+'\n')
