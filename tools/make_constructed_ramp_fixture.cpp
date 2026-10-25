#include <cstdio>
#include <fstream>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=3)return 2;
 std::ifstream input(argv[1]);if(!input)return 2;
 SyntheticFort fort(12,12,1);const auto stone=fort.material("INORGANIC:GRANITE");
 fort.fillBox(TilePos(0,0,0),TilePos(11,11,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 int mask,support,material,step=0;
 const int dx[]={0,0,0,1,-1},dy[]={0,-1,1,0,0};
 while(input>>mask>>support>>material) {
  if(mask<1 || mask>15 || support<0 || support>4 || material<0 || material>1)return 2;
  const auto id=fort.material(material==0?"INORGANIC:COAL_BITUMINOUS":"PLANT:WILLOW:WOOD");
  const auto tile=[&](TileShape shape,MaterialKind kind,uint16_t mat){return TileState(shape,kind,mat,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None);};
  for(int side=1;side<=4;++side)fort.setTile(4+dx[side],4+dy[side],0,tile(side==support?TileShape::Wall:TileShape::Floor,MaterialKind::Stone,stone));
  fort.setTile(4,4,0,tile(TileShape::Ramp,MaterialKind::Constructed,id));
  fort.setCompletedTrack(4,4,0,uint8_t(mask));
  fort.snapshot(10+step,1000+1000*step);++step;
 }
 if(!input.eof() || !step)return 2;
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[2],bytes,error)?0:1;
}
