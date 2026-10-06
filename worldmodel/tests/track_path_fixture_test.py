"""Compare model output to retained native paths, not a second implementation."""
import json
from pathlib import Path
import subprocess
import sys

fixture = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))['routing']
rows = fixture['clear'] + fixture['obstacles'] + fixture['model_validation']['cases']
request = []
for row in rows:
    walls = row.get('walls', {'wall-east': [[1,0]], 'wall-diagonal': [[1,1]]}.get(row.get('scenario'), []))
    request.append(' '.join(map(str, row['target'][:2] + [len(walls)] + [v for p in walls for v in p])))
run = subprocess.run([sys.argv[1]], input='\n'.join(request)+'\n', text=True, capture_output=True, check=True, timeout=30)
lines = run.stdout.splitlines()
assert len(lines) == len(rows), (len(lines),len(rows),run.stderr)
for index,(line,row) in enumerate(zip(lines,rows)):
    values = list(map(int,line.split()))
    status,size = values[:2]
    assert len(values) == 2+size*3
    actual = [values[i:i+3] for i in range(2,len(values),3)]
    assert status == (0 if row['path'] else 1), (index,status)
    assert actual == row['path'], (index,row.get('scenario'),row['target'],actual,row['path'])
print(f'TRACK_PATH_NATIVE_FIXTURE_PASS {len(rows)} recorded cases')

native=json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
# Compare semantic tile rules against native routes, including native detours.
terrain=native['terrain_eligibility']
shape_ids={'EMPTY':0,'ENDLESS_PIT':0,'WALL':1,'FLOOR':2,'RAMP':3,'RAMP_TOP':4,
           'STAIR_UP':5,'STAIR_DOWN':6,'STAIR_UPDOWN':7,'FORTIFICATION':8,
           'SHRUB':13,'SAPLING':14}
site_requests=[]
site_paths=[]
def site_case(start,goal,probe,shape,occupancy,hidden,depth,magma,path):
    site_requests.append(' '.join(map(str,[*start[:2],*goal[:2],*probe[:2],shape,occupancy,1,int(hidden),depth,int(magma)])))
    site_paths.append(path)
for row in terrain['cases']+terrain['vertical_neighbors']['cases']:
    site_case([0,0,0],row['target'],[1,0,0],shape_ids[row['shape']],0,row['hidden'],row['depth'],row['magma'],row['path'])
for section in ['support_occupancy','abstract_occupancy','zone_alone_and_existing_stockpiles']:
    for row in terrain[section]['cases']:
        origin=[row['probe']['x']-1,row['probe']['y'],row['probe']['z']]
        def relative(p):return [p[k]-origin[i] for i,k in enumerate(('x','y','z'))]
        site_case([0,0,0],relative(row['target']),[1,0,0],2,
                  0 if row['occupancy']==0 else 2,False,0,False,
                  [relative(p) for p in row['state']['path']])
run=subprocess.run([sys.argv[1],'--site-route'],input='\n'.join(site_requests)+'\n',text=True,capture_output=True,check=True,timeout=30)
for index,(line,path) in enumerate(zip(run.stdout.splitlines(),site_paths,strict=True)):
    assert line!='unverified',(index,site_requests[index])
    values=list(map(int,line.split()))
    assert values[0]==(0 if path else 1) and values[1]==len(path)
    assert [values[i:i+3] for i in range(2,len(values),3)]==path,(index,line,path)
print(f'TRACK_SITE_NATIVE_FIXTURE_PASS {len(site_paths)} recorded routes')

# These input-contract checks are not native observations. Unknown facts must
# remain distinguishable from a native refusal, even when no route is found.
unknown=['0 0 1 0 1 0 15 0 1 0 0 0',
         '0 0 1 0 1 0 2 3 1 0 0 0',
         '0 0 1 0 1 0 2 0 1 0 8 0']
run=subprocess.run([sys.argv[1],'--site-route'],input='\n'.join(unknown)+'\n',text=True,capture_output=True,check=True,timeout=30)
assert run.stdout.splitlines()==['unverified']*len(unknown)

elevation=native['elevation']
shapes={'StoneRamp':1,'RampTop':2,'StoneWall':3}
route_cases=[]
for row in elevation['cases']:
    edits=[[*v[:3],shapes[v[3]]] for v in elevation['scenarios'][row['scenario']]]
    route_cases.append(([0,0,0],row['target'],edits,row['path']))
edits=[[*v[:3],shapes[v[3]]] for v in elevation['scenarios']['ramp-east-wall']]
for section in ['upper_goal_matrix','upper_start_matrix']:
    for row in elevation[section]['cases']:
        route_cases.append((elevation[section]['start'],row['target'],edits,row['path']))
for row in elevation['direction_matrix']['cases']:
    dx,dy=row['direction']
    edits=[[dx,dy,0,1],[dx,dy,1,2],[2*dx,2*dy,0,3]]
    route_cases.append(([row['start'][k] for k in ('x','y','z')],
                        [row['goal'][k] for k in ('x','y','z')],edits,
                        [[p[k] for k in ('x','y','z')] for p in row['path']]))
requests=[' '.join(map(str,[*start,*goal,len(edits)]+[v for edit in edits for v in edit])) for start,goal,edits,path in route_cases]
run=subprocess.run([sys.argv[1],'--route3d'],input='\n'.join(requests)+'\n',text=True,capture_output=True,check=True,timeout=30)
for index,(line,case) in enumerate(zip(run.stdout.splitlines(),route_cases,strict=True)):
    values=list(map(int,line.split()));status,size=values[:2]
    actual=[values[i:i+3] for i in range(2,len(values),3)]
    assert size==len(actual) and status==(0 if case[3] else 1)
    assert actual==case[3],(index,case,actual)
print(f'TRACK_3D_NATIVE_FIXTURE_PASS {len(route_cases)} recorded cases')
placement_sets=[(native['placed_pieces'],None),
                (native['ramp_placement']['pieces'],native['ramp_placement']['setup']['origin'])]
requests=[]
expected=[]
for pieces,origin in placement_sets:
    values=[len(pieces)]; output=[len(pieces)]
    for piece in pieces:
        # Input ramp comes from prepared terrain, independently of native output subtype.
        ramp=bool(origin and piece['x']==origin['x']+1 and piece['y']==origin['y'] and piece['z']==origin['z'])
        values.extend([piece['x'],piece['y'],piece['z'],int(ramp)])
        subtype=piece['subtype']
        suffix=subtype.removeprefix('Track').removeprefix('Ramp')
        output.extend([sum({'N':1,'S':2,'E':4,'W':8}[c] for c in suffix),int('Ramp' in subtype)])
    requests.append(' '.join(map(str,values))); expected.append(' '.join(map(str,output)))
# Reject gaps, x/y diagonals, same-column vertical moves, ungrounded rises,
# repeated tiles and isolated single-tile routes rather than inventing pieces.
for path in [[(0,0,0,0),(2,0,0,0)],[(0,0,0,0),(1,1,0,0)],
             [(0,0,0,1),(0,0,1,0)],[(0,0,0,0),(1,0,1,0)],
             [(0,0,0,0),(1,0,0,0),(0,0,0,0)],[(0,0,0,0)]]:
    requests.append(' '.join(map(str,[len(path)]+[v for p in path for v in p])))
    expected.append('invalid')
run=subprocess.run([sys.argv[1],'--pieces'],input='\n'.join(requests)+'\n',text=True,capture_output=True,check=True,timeout=30)
assert run.stdout.splitlines()==expected,(run.stdout,expected)
print('TRACK_PIECES_NATIVE_FIXTURE_PASS 2 native placements, 6 invalid routes')

def position(piece):
    return tuple(piece[k] for k in ('x','y','z'))

def connections(piece):
    return sum({'N':1,'S':2,'E':4,'W':8}[c] for c in piece['subtype'].removeprefix('Track').removeprefix('Ramp'))

requests=[]
expected=[]
for key in ['pending_crossing','pending_endpoint_join','pending_overlap_selection',
            'completed_crossing','completed_overlap','pending_replacement','carved_crossing']:
    case=native[key]
    before={position(p):p for p in case.get('before',[])}
    terrain={position(p):p for p in case.get('terrain_before',case.get('completed_before',[]))}
    kind=case.get('terrain_kind',2)
    def terrain_mask(p):
        return connections({'subtype':p['tile'].replace('ConstructedFloor','').replace('StoneFloor','')})
    after={position(p):p for p in case['after']}
    values=[len(case['path']),len(before),len(terrain)]
    for p in case['path']: values.extend(position(p))
    for p in before.values(): values.extend([*position(p),p['id'],connections(p)])
    for p in terrain.values(): values.extend([*position(p),terrain_mask(p),kind])
    output=[case['new_job_count']]
    for p in case['path']:
        old=before.get(position(p)); new=after[position(p)]
        if old:
            assert old['id']==new['id']
            output.extend([2 if old['subtype']==new['subtype'] else 1,old['id'],connections(old),connections(new)])
        else:
            output.extend([0,-1,0,connections(new)])
        old_terrain=terrain.get(position(p))
        output.extend([terrain_mask(old_terrain) if old_terrain else 0,kind if old_terrain else 0])
    requests.append(' '.join(map(str,values)))
    expected.append(' '.join(map(str,output)))
# Malformed snapshots must not become mutable plans. These are validation checks,
# independent of the recorded native expectations above.
for jobs in [[(0,0,0,-1,4)],[(0,0,0,1,0)],[(0,0,0,1,16)],
             [(0,0,0,1,4),(1,0,0,1,8)],[(0,0,0,1,4),(0,0,0,2,8)]]:
    requests.append(' '.join(map(str,[2,len(jobs),0,0,0,0,1,0,0]+[v for p in jobs for v in p])))
    expected.append('invalid')
requests.append('2 0 0 0 0 0 1 0 1')
expected.append('invalid')
# Unknown terrain kinds/masks, duplicate snapshots and conflicting connections
# cannot be accepted as verified placement plans.
for row in ['2 0 1 0 0 0 1 0 0 0 0 0 0 2',
            '2 0 2 0 0 0 1 0 0 0 0 0 4 2 0 0 0 8 2',
            '2 1 1 0 0 0 1 0 0 0 0 0 1 4 0 0 0 8 2',
            '2 0 1 0 0 0 1 0 0 0 0 0 4 0']:
    requests.append(row); expected.append('invalid')
run=subprocess.run([sys.argv[1],'--pending-plan'],input='\n'.join(requests)+'\n',text=True,capture_output=True,check=True,timeout=30)
assert run.stdout.splitlines()==expected,(run.stdout,expected)
print('TRACK_CONSTRUCTION_PLAN_PASS 7 native placements, 10 invalid inputs')

requests=[]
expected=[]
for key in ['ramp_placement','pending_ramp_join','completed_ramp_join']:
    case=native[key]
    before={position(p):p for p in case.get('initial_ramp_jobs',[]) if key=='pending_ramp_join'}
    terrain={position(p):p for p in case.get('completed_before',[])}
    after={position(p):p for p in case.get('after',case.get('pieces',[]))}
    origin=case['setup']['origin']
    ramp_pos=(origin['x']+1,origin['y'],origin['z'])
    def terrain_connections(p):
        return connections({'subtype':p['tile'].replace('ConstructedFloor','').replace('ConstructedRamp','')})
    values=[len(case['path']),len(before),len(terrain)]
    for p in case['path']: values.extend([*position(p),int(position(p)==ramp_pos)])
    for p in before.values(): values.extend([*position(p),p['id'],connections(p),int('Ramp' in p['subtype'])])
    for p in terrain.values(): values.extend([*position(p),terrain_connections(p),2,int('Ramp' in p['tile'])])
    output=[case.get('new_job_count',4)]
    for p in case['path']:
        old=before.get(position(p)); tile=terrain.get(position(p)); new=after[position(p)]
        if old:
            assert old['id']==new['id']
            output.extend([2 if old['subtype']==new['subtype'] else 1,old['id'],connections(old),connections(new)])
        else: output.extend([0,-1,0,connections(new)])
        output.extend([terrain_connections(tile) if tile else 0,2 if tile else 0,
                       int('Ramp' in new['subtype']),int(bool(old and 'Ramp' in old['subtype'])),int(bool(tile and 'Ramp' in tile['tile']))])
    requests.append(' '.join(map(str,values))); expected.append(' '.join(map(str,output)))
# A ramp-shaped job or terrain conflicting with the independent terrain facts
# must not silently turn into a flat piece, even if the connection mask agrees.
for path,jobs,terrain in [
    ([(0,0,0,0),(1,0,0,0)],[(0,0,0,10,4,1)],[]),
    ([(0,0,0,0),(1,0,0,0)],[],[(0,0,0,4,2,1)]),
    ([(0,0,0,1),(1,0,0,0)],[(0,0,0,10,4,0)],[(0,0,0,4,2,1)])]:
    values=[len(path),len(jobs),len(terrain)]+[v for rows in (path,jobs,terrain) for p in rows for v in p]
    requests.append(' '.join(map(str,values))); expected.append('invalid')
run=subprocess.run([sys.argv[1],'--ramp-plan'],input='\n'.join(requests)+'\n',text=True,capture_output=True,check=True,timeout=30)
assert run.stdout.splitlines()==expected,(run.stdout,expected)
print('TRACK_RAMP_PLAN_PASS 3 native placements, 3 shape conflicts')
