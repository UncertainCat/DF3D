#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(20,20,1);auto stone=fort.material("INORGANIC:GRANITE"),iron=fort.material("INORGANIC:IRON");
 fort.fillBox(TilePos(0,0,0),TilePos(19,19,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 for(int i=0;i<16;++i) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::BarsVertical;b.material=stone;b.verticalBarsConnections=i;b.constructionItemIsLog=0;b.constructionItemMaterial=iron;
  b.x1=b.x2=2+(i%4)*4;b.y1=b.y2=3+(i/4)*4;fort.placeBuilding(100+i,b);
 }
 for(int i=0;i<2;++i) {
  SyntheticFort::BuildingSpec b;b.kind=i==0?BuildingKind::BarsFloor:BuildingKind::Support;b.material=stone;b.constructionItemIsLog=0;b.constructionItemMaterial=iron;
  b.x1=b.x2=18;b.y1=b.y2=3+i*4;fort.placeBuilding(200+i,b);
 }
 {SyntheticFort::BuildingSpec b;b.kind=BuildingKind::WindowGem;b.material=fort.material("INORGANIC:RUBY");b.x1=b.x2=18;b.y1=b.y2=11;fort.placeBuilding(202,b);}
 for(int i=0;i<2;++i){SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Well;b.material=iron;b.wellChainIsMetal=i;b.x1=b.x2=2+i*4;b.y1=b.y2=18;fort.placeBuilding(203+i,b);}
 {SyntheticFort::BuildingSpec b;b.kind=BuildingKind::WindowGlass;b.material=fort.material("GLASS_GREEN");b.materialSolidColor="DARK_GREEN";b.x1=b.x2=18;b.y1=b.y2=15;fort.placeBuilding(205,b);}
 const BuildingKind openings[]={BuildingKind::Door,BuildingKind::Hatch,BuildingKind::GrateWall,BuildingKind::GrateFloor,BuildingKind::Floodgate};
 for(int i=0;i<5;++i){SyntheticFort::BuildingSpec b;b.kind=openings[i];b.material=stone;b.x1=b.x2=1+i*4;b.y1=b.y2=1;fort.placeBuilding(206+i,b);}
 const BuildingKind furniture[]={BuildingKind::Chair,BuildingKind::Table,BuildingKind::Box,BuildingKind::Cabinet};
 for(int i=0;i<4;++i){SyntheticFort::BuildingSpec b;b.kind=furniture[i];b.material=stone;b.x1=b.x2=10+i*2;b.y1=b.y2=18;fort.placeBuilding(211+i,b);}
 const BuildingKind ordinary[]={BuildingKind::Coffin,BuildingKind::Cage,BuildingKind::Chain,BuildingKind::AnimalTrap};
 for(int i=0;i<4;++i){SyntheticFort::BuildingSpec b;b.kind=ordinary[i];b.material=fort.material(i==0?"INORGANIC:GRANITE":i==3?"PLANT:OAK:WOOD":"INORGANIC:IRON");b.x1=b.x2=2+i*4;b.y1=b.y2=16;fort.placeBuilding(215+i,b);}
 int step=0;auto snap=[&](){fort.snapshot(10+step,1000+1000*step);++step;};snap();
 for(int i=100;i<116;++i)fort.setBuildingStage(i,BuildingStage::Planned);for(int i=200;i<219;++i)fort.setBuildingStage(i,BuildingStage::Planned);snap();
 for(int i=100;i<116;++i){auto b=fort.building(i);b.stage=BuildingStage::Complete;b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;fort.placeBuilding(i,b);}for(int i=200;i<219;++i){auto b=fort.building(i);b.stage=BuildingStage::Complete;b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;fort.placeBuilding(i,b);}snap();
 for(int i=100;i<116;++i){auto b=fort.building(i);b.verticalBarsConnections=15-b.verticalBarsConnections;fort.placeBuilding(i,b);}for(int i=203;i<205;++i){auto b=fort.building(i);b.wellChainIsMetal=1-b.wellChainIsMetal;fort.placeBuilding(i,b);}snap();
 auto b=fort.building(100),well=fort.building(203);fort.removeBuilding(100);fort.removeBuilding(203);snap();fort.placeBuilding(100,b);fort.placeBuilding(203,well);snap();
 // Native completed-opening references in bars_rendering.json, in capture order.
 struct Opening {BuildingKind kind;int id;const char* material;const char* color;};
 const Opening cases[]={
  {BuildingKind::Door,48520,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48521,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48554,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48555,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48556,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48557,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48558,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48559,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48560,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48561,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48562,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48563,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48564,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48565,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48566,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48567,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48568,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48569,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48570,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48571,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48572,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48573,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48574,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48575,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48576,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48577,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48578,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48579,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48580,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48581,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48582,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48583,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48584,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48585,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48520,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48521,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48545,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48546,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48547,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48548,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48549,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48550,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48551,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48552,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Door,48553,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48554,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48555,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48556,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48557,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48558,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48559,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48560,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48561,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48562,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48563,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48564,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48565,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48566,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48567,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48568,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Hatch,48569,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48570,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48571,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48572,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48573,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48574,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48575,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Hatch,48576,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Door,48585,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48586,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48587,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48588,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48589,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48590,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48593,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48594,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Door,48598,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48600,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48603,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48606,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48609,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48610,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Door,48611,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48647,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48648,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48657,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48658,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48660,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48663,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48664,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48665,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Hatch,48666,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48667,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48668,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48669,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48675,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48676,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48677,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Hatch,48679,"PLANT:OAK:WOOD","AUBURN"},
 };
 for(const auto& sample:cases) {
  const int id=sample.kind==BuildingKind::Door?206:207;auto b=fort.building(id);
  b.stage=BuildingStage::Complete;b.material=fort.material(sample.material);b.constructionItemMaterial=b.material;b.constructionItemIsLog=0;b.constructionItemId=sample.id;
  b.constructionItemSolidColor=sample.color;fort.placeBuilding(id,b);snap();
 }
 const Opening furnitureCases[]={
  {BuildingKind::Chair,48520,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48521,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48522,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48523,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48561,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48562,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48563,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48564,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48565,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48566,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48567,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48568,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Chair,48569,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48570,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48571,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48572,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48573,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48574,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48575,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48576,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Chair,48577,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48578,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48579,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48580,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48581,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48582,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48583,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48584,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Chair,48585,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48586,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48587,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48588,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48589,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48590,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48591,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Chair,48592,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48593,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48594,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48595,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48596,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48597,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48598,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48599,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48600,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Table,48601,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48602,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48603,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48604,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48605,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48606,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48607,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48608,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Table,48609,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48610,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48611,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48612,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48613,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48614,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48615,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48616,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Table,48617,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48618,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48619,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48620,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48621,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48622,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48623,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Table,48624,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48625,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48626,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48627,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48628,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48629,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48630,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48631,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48632,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Box,48633,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48634,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48635,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48636,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48637,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48638,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48639,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48640,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Box,48641,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48642,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48643,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48644,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48645,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48646,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48647,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48648,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Box,48649,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48650,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48651,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48652,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48653,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48654,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48655,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Box,48656,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48657,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48658,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48659,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48660,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48661,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48662,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48663,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48664,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Cabinet,48665,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48666,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48667,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48668,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48669,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48670,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48671,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48672,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Cabinet,48673,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48674,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48675,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48676,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48677,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48678,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48679,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48680,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Cabinet,48681,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48682,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48683,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48684,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48685,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48686,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48687,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Cabinet,48688,"PLANT:OAK:WOOD","AUBURN"},
 };
 for(const auto& sample:furnitureCases) {
  const int id=sample.kind==BuildingKind::Chair?211:sample.kind==BuildingKind::Table?212:sample.kind==BuildingKind::Box?213:214;auto b=fort.building(id);
  b.stage=BuildingStage::Complete;b.material=fort.material(sample.material);b.constructionItemMaterial=b.material;b.constructionItemIsLog=0;b.constructionItemId=sample.id;
  b.constructionItemSolidColor=sample.color;fort.placeBuilding(id,b);snap();
 }
 const Opening equipmentCases[]={
  {BuildingKind::Armorstand,0,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Armorstand,0,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Armorstand,0,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Armorstand,0,"PLANT:OAK:WOOD","AUBURN"},
  {BuildingKind::Weaponrack,0,"INORGANIC:GRANITE","CLEAR"},
  {BuildingKind::Weaponrack,0,"INORGANIC:IRON","GRAY"},
  {BuildingKind::Weaponrack,0,"GLASS_GREEN","DARK_GREEN"},
  {BuildingKind::Weaponrack,0,"PLANT:OAK:WOOD","AUBURN"},
 };
 for(const auto& sample:equipmentCases) {
  SyntheticFort::BuildingSpec b;b.kind=sample.kind;b.stage=BuildingStage::Planned;b.material=fort.material(sample.material);b.materialSolidColor=sample.color;
  b.x1=b.x2=sample.kind==BuildingKind::Armorstand?5:9;b.y1=b.y2=17;fort.placeBuilding(sample.kind==BuildingKind::Armorstand?219:220,b);snap();
 }
 const char* chainMaterials[]={"INORGANIC:IRON","PLANT:COTTON:THREAD","INORGANIC:IRON","INORGANIC:IRON","PLANT:COTTON:THREAD","INORGANIC:IRON"};
 for(const auto* material:chainMaterials){auto b=fort.building(217);b.stage=BuildingStage::Complete;b.material=fort.material(material);fort.placeBuilding(217,b);snap();}
 struct Ordinary {BuildingKind kind;int id;const char* material;const char* component;const char* color;const char* buildingColor;int count;};
 const Ordinary ordinaryCases[]={
  {BuildingKind::Coffin,48520,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",1},
  {BuildingKind::Armorstand,48521,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",1},
  {BuildingKind::Weaponrack,48522,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",1},
  {BuildingKind::Cage,48523,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",1},
  {BuildingKind::AnimalTrap,48525,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",1},
  {BuildingKind::Coffin,48553,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",1},
  {BuildingKind::Coffin,48555,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",1},
  {BuildingKind::Coffin,48557,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",1},
  {BuildingKind::Armorstand,48561,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",1},
  {BuildingKind::Armorstand,48563,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",1},
  {BuildingKind::Armorstand,48565,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",1},
  {BuildingKind::Weaponrack,48569,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",1},
  {BuildingKind::Weaponrack,48571,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",1},
  {BuildingKind::Weaponrack,48573,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",1},
  {BuildingKind::Cage,48577,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",1},
  {BuildingKind::Cage,48579,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",1},
  {BuildingKind::AnimalTrap,48587,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",1},
  {BuildingKind::Coffin,48520,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",2},
  {BuildingKind::Armorstand,48521,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",2},
  {BuildingKind::Weaponrack,48522,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","CLEAR",2},
  {BuildingKind::Cage,48523,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",2},
  {BuildingKind::AnimalTrap,48525,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",2},
  {BuildingKind::Coffin,48520,"INORGANIC:IRON","INORGANIC:GRANITE","CLEAR","GRAY",1},
  {BuildingKind::Coffin,48554,"INORGANIC:GRANITE","INORGANIC:IRON","GRAY","CLEAR",1},
  {BuildingKind::Armorstand,48521,"INORGANIC:IRON","INORGANIC:GRANITE","CLEAR","GRAY",1},
  {BuildingKind::Armorstand,48555,"INORGANIC:GRANITE","INORGANIC:IRON","GRAY","CLEAR",1},
  {BuildingKind::Weaponrack,48522,"INORGANIC:IRON","INORGANIC:GRANITE","CLEAR","GRAY",1},
  {BuildingKind::Weaponrack,48556,"INORGANIC:GRANITE","INORGANIC:IRON","GRAY","CLEAR",1},
  {BuildingKind::Cage,48523,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","AUBURN",1},
  {BuildingKind::Cage,48557,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","GRAY",1},
  {BuildingKind::AnimalTrap,48525,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","GRAY",1},
  {BuildingKind::AnimalTrap,48559,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","AUBURN",1},
  {BuildingKind::Coffin,48566,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",2},
  {BuildingKind::Coffin,48572,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",2},
  {BuildingKind::Coffin,48580,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",2},
  {BuildingKind::Armorstand,48594,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",2},
  {BuildingKind::Armorstand,48599,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",2},
  {BuildingKind::Armorstand,48605,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",2},
  {BuildingKind::Weaponrack,48621,"INORGANIC:IRON","INORGANIC:IRON","GRAY","GRAY",2},
  {BuildingKind::Weaponrack,48628,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","DARK_GREEN",2},
  {BuildingKind::Weaponrack,48634,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","AUBURN",2},
 };
 for(const auto& sample:ordinaryCases) {
  const int id=sample.kind==BuildingKind::Coffin?215:sample.kind==BuildingKind::Cage?216:sample.kind==BuildingKind::AnimalTrap?218:sample.kind==BuildingKind::Armorstand?219:220;
  auto b=fort.building(id);b.stage=BuildingStage::Complete;b.material=fort.material(sample.material);
  const bool equipment=sample.kind==BuildingKind::Armorstand || sample.kind==BuildingKind::Weaponrack;
  if(equipment)b.materialSolidColor=sample.buildingColor;
  else {b.constructionItemId=sample.id;b.constructionItemMaterial=fort.material(sample.component);b.constructionItemIsLog=0;b.constructionItemSolidColor=sample.color;}
  if(equipment || sample.kind==BuildingKind::Coffin)b.containedItemCount=sample.count;
  fort.placeBuilding(id,b);snap();
 }
 struct ToolFurniture {BuildingKind kind;bool complete;const char* material;const char* component;const char* color;const char* raw;int id;};
 const ToolFurniture toolCases[]={
  {BuildingKind::Bed,false,"INORGANIC:GRANITE","","","",-1},
  {BuildingKind::Bookcase,false,"INORGANIC:GRANITE","","","ITEM_TOOL_BOOKCASE",-1},
  {BuildingKind::DisplayFurniture,false,"INORGANIC:GRANITE","","","ITEM_TOOL_PEDESTAL",-1},
  {BuildingKind::OfferingPlace,false,"INORGANIC:GRANITE","","","ITEM_TOOL_ALTAR",-1},
  {BuildingKind::Hive,false,"INORGANIC:GRANITE","","","ITEM_TOOL_HIVE",-1},
  {BuildingKind::NestBox,false,"INORGANIC:GRANITE","","","ITEM_TOOL_NEST_BOX",-1},
  {BuildingKind::TractionBench,false,"INORGANIC:GRANITE","","","",-1},
  {BuildingKind::Bookcase,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_BOOKCASE",48521},
  {BuildingKind::DisplayFurniture,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_PEDESTAL",48522},
  {BuildingKind::OfferingPlace,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_ALTAR",48523},
  {BuildingKind::Hive,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_HIVE",48524},
  {BuildingKind::NestBox,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_NEST_BOX",48525},
  {BuildingKind::TractionBench,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","",48526},
  {BuildingKind::Bed,false,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","",48562},
  {BuildingKind::Bed,false,"INORGANIC:IRON","INORGANIC:IRON","GRAY","",48563},
  {BuildingKind::Bed,false,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","",48564},
  {BuildingKind::Bed,false,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","",48565},
  {BuildingKind::Bookcase,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_BOOKCASE",48567},
  {BuildingKind::Bookcase,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_BOOKCASE",48568},
  {BuildingKind::Bookcase,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_BOOKCASE",48569},
  {BuildingKind::DisplayFurniture,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_PEDESTAL",48571},
  {BuildingKind::DisplayFurniture,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_PEDESTAL",48572},
  {BuildingKind::DisplayFurniture,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_PEDESTAL",48573},
  {BuildingKind::DisplayFurniture,true,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","ITEM_TOOL_DISPLAY_CASE",48574},
  {BuildingKind::DisplayFurniture,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_DISPLAY_CASE",48575},
  {BuildingKind::DisplayFurniture,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_DISPLAY_CASE",48576},
  {BuildingKind::DisplayFurniture,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_DISPLAY_CASE",48577},
  {BuildingKind::OfferingPlace,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_ALTAR",48579},
  {BuildingKind::OfferingPlace,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_ALTAR",48580},
  {BuildingKind::OfferingPlace,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_ALTAR",48581},
  {BuildingKind::Hive,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_HIVE",48583},
  {BuildingKind::Hive,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_HIVE",48584},
  {BuildingKind::Hive,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_HIVE",48585},
  {BuildingKind::NestBox,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","ITEM_TOOL_NEST_BOX",48587},
  {BuildingKind::NestBox,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","ITEM_TOOL_NEST_BOX",48588},
  {BuildingKind::NestBox,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_NEST_BOX",48589},
  {BuildingKind::TractionBench,false,"INORGANIC:GRANITE","INORGANIC:GRANITE","CLEAR","",48590},
  {BuildingKind::TractionBench,true,"INORGANIC:IRON","INORGANIC:IRON","GRAY","",48591},
  {BuildingKind::TractionBench,false,"INORGANIC:IRON","INORGANIC:IRON","GRAY","",48591},
  {BuildingKind::TractionBench,true,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","",48592},
  {BuildingKind::TractionBench,false,"GLASS_GREEN","GLASS_GREEN","DARK_GREEN","",48592},
  {BuildingKind::TractionBench,true,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","",48593},
  {BuildingKind::TractionBench,false,"PLANT:OAK:WOOD","PLANT:OAK:WOOD","AUBURN","",48593},
  {BuildingKind::Bed,false,"PLANT:OAK:WOOD","","","",-1},
  {BuildingKind::Bookcase,false,"PLANT:OAK:WOOD","","","ITEM_TOOL_BOOKCASE",-1},
  {BuildingKind::DisplayFurniture,false,"PLANT:OAK:WOOD","","","ITEM_TOOL_DISPLAY_CASE",-1},
  {BuildingKind::OfferingPlace,false,"PLANT:OAK:WOOD","","","ITEM_TOOL_ALTAR",-1},
  {BuildingKind::Hive,false,"PLANT:OAK:WOOD","","","ITEM_TOOL_HIVE",-1},
  {BuildingKind::NestBox,false,"PLANT:OAK:WOOD","","","ITEM_TOOL_NEST_BOX",-1},
  {BuildingKind::TractionBench,false,"PLANT:OAK:WOOD","","","",-1},
  {BuildingKind::Bookcase,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_BOOKCASE",48521},
  {BuildingKind::Bookcase,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","ITEM_TOOL_BOOKCASE",48552},
  {BuildingKind::DisplayFurniture,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_DISPLAY_CASE",48522},
  {BuildingKind::DisplayFurniture,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","ITEM_TOOL_DISPLAY_CASE",48553},
  {BuildingKind::OfferingPlace,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_ALTAR",48523},
  {BuildingKind::OfferingPlace,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","ITEM_TOOL_ALTAR",48554},
  {BuildingKind::Hive,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_HIVE",48524},
  {BuildingKind::Hive,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","ITEM_TOOL_HIVE",48555},
  {BuildingKind::NestBox,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","ITEM_TOOL_NEST_BOX",48525},
  {BuildingKind::NestBox,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","ITEM_TOOL_NEST_BOX",48556},
  {BuildingKind::TractionBench,true,"INORGANIC:IRON","PLANT:OAK:WOOD","AUBURN","",48526},
  {BuildingKind::TractionBench,true,"PLANT:OAK:WOOD","INORGANIC:IRON","GRAY","",48557},
 };
 for(const auto& sample:toolCases) {
  const int id=sample.kind==BuildingKind::Bed?221:sample.kind==BuildingKind::Bookcase?222:sample.kind==BuildingKind::DisplayFurniture?223:sample.kind==BuildingKind::OfferingPlace?224:sample.kind==BuildingKind::Hive?225:sample.kind==BuildingKind::NestBox?226:227;
  SyntheticFort::BuildingSpec b;b.kind=sample.kind;b.stage=sample.complete?BuildingStage::Complete:BuildingStage::Planned;b.material=fort.material(sample.material);b.constructionToolRaw=sample.raw;
  b.x1=b.x2=2+(id-221)*2;b.y1=b.y2=6;
  const bool component=sample.kind!=BuildingKind::Hive && sample.kind!=BuildingKind::TractionBench;
  if(component && sample.id>=0) {b.constructionItemIsLog=0;b.constructionItemMaterial=fort.material(sample.component);
   if(sample.kind!=BuildingKind::Bed){b.constructionItemId=sample.id;b.constructionItemSolidColor=sample.color;}
   else {b.bedding.sheet=0;b.bedding.pillow=0;b.bedding.baseColor="CLEAR";b.bedding.sheetColor="WHITE";}
  }
  fort.placeBuilding(id,b);snap();
 }
 struct BedReference {const char* material;const char* component;int sheet;int pillow;const char* baseColor;const char* sheetColor;};
 const BedReference bedCases[]={
  {"INORGANIC:GRANITE","INORGANIC:GRANITE",0,2,"CLEAR","DARK_PEACH"},
  {"INORGANIC:GRANITE","INORGANIC:GRANITE",1,0,"CLEAR","TAUPE_DARK"},
  {"INORGANIC:IRON","INORGANIC:IRON",0,0,"GRAY","BLACK"},
  {"GLASS_GREEN","GLASS_GREEN",0,1,"DARK_GREEN","TEAL"},
  {"PLANT:OAK:WOOD","PLANT:OAK:WOOD",1,1,"AUBURN","GREEN-YELLOW"},
  {"INORGANIC:IRON","PLANT:OAK:WOOD",1,1,"AUBURN","GREEN-YELLOW"},
  {"PLANT:OAK:WOOD","PLANT:OAK:WOOD",1,1,"AUBURN","GREEN-YELLOW"},
 };
 for(const auto& sample:bedCases){auto b=fort.building(221);b.stage=BuildingStage::Complete;b.material=fort.material(sample.material);b.constructionItemIsLog=0;b.constructionItemMaterial=fort.material(sample.component);
  b.bedding.sheet=sample.sheet;b.bedding.pillow=sample.pillow;b.bedding.baseColor=sample.baseColor;b.bedding.sheetColor=sample.sheetColor;fort.placeBuilding(221,b);snap();}
 const char* bridgeMaterials[]={"INORGANIC:GRANITE","INORGANIC:IRON","GLASS_GREEN","PLANT:OAK:WOOD"};
 const char* bridgeColors[]={"CLEAR","GRAY","DARK_GREEN","AUBURN"};
 for(int m=0;m<4;++m)for(int stage=0;stage<2;++stage)for(int direction=-1;direction<4;++direction)for(bool raised:{false,true}) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Bridge;b.x1=8;b.x2=10;b.y1=8;b.y2=10;b.material=fort.material(bridgeMaterials[m]);b.materialSolidColor=bridgeColors[m];
  b.stage=stage?BuildingStage::Complete:BuildingStage::Planned;b.bridge.direction=direction;b.bridge.raised=raised;fort.placeBuilding(228,b);snap();
 }
 for(int stage:{0,1,2,3,1,2}) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Workshop;b.subtype=0;b.x1=4;b.x2=6;b.y1=4;b.y2=6;b.material=stone;
  b.constructionStage=stage;b.stage=stage==0?BuildingStage::Planned:stage==3?BuildingStage::Complete:BuildingStage::InProgress;
  fort.placeBuilding(229,b);snap();
 }
 for(int family=0;family<3;++family)for(const char* component:{"INORGANIC:GRANITE","INORGANIC:IRON","GLASS_GREEN","PLANT:OAK:WOOD"})for(int stage=0;stage<4;++stage) {
  SyntheticFort::BuildingSpec b;b.kind=family==0?BuildingKind::Workshop:family==1?BuildingKind::Furnace:BuildingKind::TradeDepot;b.subtype=family==0?0:family==1?1:0;
  b.x1=4;b.y1=4;b.x2=b.y2=family==2?8:6;b.material=stone;b.constructionItemIsLog=0;b.constructionItemMaterial=fort.material(component);b.constructionItemId=1000;
  b.constructionItemSolidColor=std::string(component)=="GLASS_GREEN"?"DARK_GREEN":std::string(component)=="INORGANIC:IRON"?"GRAY":std::string(component)=="PLANT:OAK:WOOD"?"AUBURN":"CLEAR";
  b.constructionStage=stage;b.stage=stage==0?BuildingStage::Planned:stage==3?BuildingStage::Complete:BuildingStage::InProgress;
  fort.placeBuilding(229+family,b);snap();
 }
 for(uint32_t id=100;id<116;++id)fort.removeBuilding(id);
 for(uint32_t id=200;id<=231;++id)fort.removeBuilding(id);
 for(int material=-1;material<4;++material)for(int stage=0;stage<2;++stage) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Workshop;b.subtype=17;b.x1=b.x2=10;b.y1=b.y2=10;b.material=stone;
  b.constructionStage=stage;b.stage=stage?BuildingStage::Complete:BuildingStage::Planned;
  if(material>=0) {b.constructionItemIsLog=0;b.constructionItemId=1000;b.constructionItemMaterial=fort.material(bridgeMaterials[material]);b.constructionItemSolidColor=bridgeColors[material];}
  fort.placeBuilding(232,b);snap();
 }
 fort.removeBuilding(232);
 for(const char* material:bridgeMaterials)for(int stage=0;stage<2;++stage) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::ArcheryTarget;b.x1=b.x2=10;b.y1=b.y2=10;b.material=fort.material(material);
  b.stage=stage?BuildingStage::Complete:BuildingStage::Planned;b.constructionStage=stage;
  fort.placeBuilding(233,b);snap();
 }
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
