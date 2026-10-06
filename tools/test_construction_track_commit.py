"""Track commit outcome accounting; native operation failures must never replay."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class Commit(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.commit=self.lua.execute((ROOT/'bridge/plugin/construction_track_commit.lua').read_text())
        self.lua.execute('''
        calls={};fail_at=0;failure='rejected'
        function apply(piece)
          calls[#calls+1]=piece.x
          if #calls==fail_at then
            if failure=='throw' then error('fixture native exception')end
            if failure=='malformed' then return {outcome='applied',building_id=-1}end
            return {outcome=failure}
          end
          return {outcome='applied',building_id=piece.action==1 and piece.building_id or 100+piece.x}
        end
        ''')
        self.plan=self.lua.table_from({'pieces':[
            {'x':1,'y':0,'z':0,'action':0,'item_id':3225,'building_id':-1},
            {'x':2,'y':0,'z':0,'action':1,'building_id':200},
            {'x':3,'y':0,'z':0,'action':2,'building_id':201},
            {'x':4,'y':0,'z':0,'action':0,'item_id':3226,'building_id':-1}]},recursive=True)

    def test_complete_counts_and_unchanged_skip(self):
        g=self.lua.globals();r=self.commit(self.plan,g.apply)
        self.assertEqual(r['outcome'],'complete')
        self.assertEqual((r['created'],r['updated'],r['unchanged'],r['attempted']),(2,1,1,3))
        self.assertEqual([g.calls[i] for i in range(1,4)],[1,2,4])
        self.assertEqual(r['first_building'],101)
        r['completed'][1]['x']=999
        self.assertEqual(self.plan['pieces'][1]['x'],1)

    def test_rejected_partial_unknown_and_no_replay(self):
        for index in [1,2,3]:
            for failure in ['rejected','throw','malformed','unrecognized']:
                with self.subTest(index=index,failure=failure):
                    g=self.lua.globals();g.calls=self.lua.table();g.fail_at=index;g.failure=failure
                    r=self.commit(self.plan,g.apply)
                    expected=('rejected' if index==1 else 'partial') if failure=='rejected' else 'unknown'
                    self.assertEqual(r['outcome'],expected)
                    self.assertEqual(len(g.calls),index)
                    self.assertEqual(len(r['completed']),index-1)
                    self.assertEqual(r['failed_index'],[1,2,4][index-1])
                    self.assertEqual(r['attempted'],index)

    def test_malformed_late_piece_prevents_all_writes(self):
        self.plan['pieces'][4]['item_id']=-1
        self.assertIsNone(self.commit(self.plan,self.lua.globals().apply))
        self.assertEqual(len(self.lua.globals().calls),0)

if __name__=='__main__':
    r=unittest.main(exit=False).result
    if r.wasSuccessful():print('CONSTRUCTION_TRACK_COMMIT_PASS')
    raise SystemExit(0 if r.wasSuccessful() else 1)
