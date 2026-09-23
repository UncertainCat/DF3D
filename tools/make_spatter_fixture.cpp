// Deterministic persistent material state, including cleanup. No shipped art.
#include <cstdio>
#include "fixture_io.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
  if(argc!=2)return 2;
  std::vector<std::vector<uint8_t>> frames;
  for(int frame=0;frame<3;++frame) {
    flatbuffers::FlatBufferBuilder f;
    std::vector<TileState> tiles(256,TileState(TileShape::Floor,MaterialKind::Stone,0,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
    const auto terrain=CreateMapBlock(f,0,0,0,f.CreateVectorOfStructs(tiles));
    const auto blocks=f.CreateVector(std::vector{terrain});
    const auto mats=f.CreateVector(std::vector{f.CreateString("INORGANIC:GRANITE"),f.CreateString("CREATURE:DWARF:BLOOD"),f.CreateString("CREATURE:VORACIOUS_CAVE_CRAWLER:ICHOR"),f.CreateString("CREATURE:TROLL:BLOOD"),f.CreateString("CREATURE:GOBLIN:BLOOD")});
    std::vector<GroundSpatter> es;
    if(frame!=2) {
      for(int y=6;y<=8;++y)for(int x=6;x<=8;++x)es.emplace_back(uint8_t(y*16+x),100,1,MatterState::Liquid);
      for(int x=4;x<=7;++x)es.emplace_back(uint8_t(4*16+x),uint8_t(1+(x-4)*25),1,MatterState::Liquid);
      es.emplace_back(10*16+10,100,2,MatterState::Liquid);
      es.emplace_back(10*16+5,100,3,MatterState::Liquid);
      // Current-state records: split red blood beats one larger ichor record.
      // Adjacent equivalent pile verifies connectivity after aggregation.
      es.emplace_back(7*16+12,60,1,MatterState::Liquid);
      es.emplace_back(7*16+12,60,4,MatterState::Liquid);
      es.emplace_back(7*16+12,100,2,MatterState::Liquid);
      es.emplace_back(8*16+12,120,1,MatterState::Liquid);
      es.emplace_back(8*16+12,100,2,MatterState::Liquid);
      // A larger ichor pile remains distinct, rather than being tinted red.
      es.emplace_back(9*16+12,120,1,MatterState::Liquid);
      es.emplace_back(9*16+12,160,2,MatterState::Liquid);
    }
    const auto stain=CreateSpatterBlock(f,0,0,0,f.CreateVectorOfStructs(es));
    const auto stains=f.CreateVector(std::vector{stain});
    const TilePos size(16,16,1);SnapshotBuilder b(f);
    b.add_schema_version(uint32_t(SchemaVersion::Current));b.add_tick(10+frame);b.add_emitted_at_ms(1000+frame*10000);b.add_map_size(&size);
    if(frame==0){b.add_terrain_scope(TerrainScope::Full);b.add_blocks(blocks);}
    b.add_materials(mats);b.add_spatter_scope(frame==0?ChangeScope::Full:ChangeScope::Delta);b.add_spatters(stains);
    FinishSizePrefixedSnapshotBuffer(f,b.Finish());
    frames.emplace_back(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  }
  const auto bytes=assembleFixture(frames);FixtureStream parsed;std::string error;
  if(!parseFixture(bytes,parsed,error))return 1;
  if(const auto invalid=validateStream(parsed)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
  if(!writeFixtureFile(argv[1],bytes,error))return 1;
  std::printf("wrote spatter fixture: %zu bytes\n",bytes.size());
}
