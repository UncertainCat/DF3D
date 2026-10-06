#include <doctest.h>

#include <algorithm>
#include <iostream>

#include "management_codecs.h"
#include "management_util.h"

namespace codec = wm::detail::management;
namespace wire = df3d::mirror;

TEST_CASE("building removal cancellation is explicit and isolated from older peers") {
  wm::ManagementRequest q;q.action=wm::ManagementAction::Remove;q.definition="Bed";q.buildingId=9;q.cancelRemoval=true;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  auto r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(r->cancel_removal());CHECK_FALSE(wire::validateConstructionRequest(*r).has_value());
  q.action=wm::ManagementAction::Inspect;b.Clear();codec::encodeRequest(b,q,1,3,3);
  r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).has_value());
}

TEST_CASE("standalone construction identities cannot substitute same-material items") {
  for(int mode=0;mode<5;++mode) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::Place;q.definition="Chair";
    wm::ConstructionSelection s;s.filter=0;s.count=1;s.expectedListRevision=1;
    s.individualId=mode==4?-2:2;s.itemIds=std::vector<int32_t>{mode==1?3:2};
    if(mode==2)s.itemIds.reset();
    if(mode==3)s.count=2;
    q.selections={s};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateConstructionRequest(*r).has_value()==(mode!=0));
    CHECK(r->selections()->Get(0)->individual_id()==s.individualId);
  }
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> rows;
    for(int id=1;id<=3;++id) {
      auto item=wire::CreateConstructionMaterialCandidate(b,id,b.CreateString("fixture item"),2);
      auto items=b.CreateVector(std::vector{item});
      if(mode==2 && id==2)items={};
      rows.push_back(wire::CreateConstructionMaterial(b,0,-1,0,1,b.CreateString("fixture row"),{},1,items,
        id==1 || mode==3?-1:(mode==1?4:id),b.CreateString(mode==4?std::string(129,'x'):std::string("fixture generic history"))));
    }
    auto materials=b.CreateVector(rows);
    wire::ConstructionStateBuilder domain(b);domain.add_materials(materials);auto c=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(c);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0){wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.materials.size()==3);CHECK(decoded.construction.materials[1].individualId==2);
      CHECK(decoded.construction.materials[1].lastName=="fixture generic history");}
  }
}

TEST_CASE("construction material anchor preserves gesture and validates volume corners") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::ConstructionMaterials;
  base.definition="Construction:Stairs";base.filter=0;base.x=2;base.y=3;base.z=4;
  base.width=3;base.height=2;base.depth=3;base.materialAnchor=wm::TilePos{4,4,6};
  for(int mode=0;mode<9;++mode) {
    auto q=base;
    if(mode==1)q.materialAnchor=wm::TilePos{2,3,4};
    if(mode==2)q.action=wm::ManagementAction::Place,q.filter=-1;
    if(mode==3)q.materialAnchor.reset();
    if(mode==4)q.materialAnchor->z=5; // Interior, not a selected corner.
    if(mode==5)q.materialAnchor->x=-1;
    if(mode==6)q.definition="Chair";
    if(mode==7)q.retracting=true;
    if(mode==8)q.depth=257;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateConstructionRequest(*r).has_value()==(mode>=4));
    CHECK(r->depth()==q.depth);CHECK(bool(r->material_anchor())==q.materialAnchor.has_value());
    if(r->material_anchor())CHECK(r->material_anchor()->z()==q.materialAnchor->z);
  }
}

TEST_CASE("reinforced area material requests preserve their selected corner") {
  for(const auto action : {wm::ManagementAction::Preview, wm::ManagementAction::Place,
                          wm::ManagementAction::ConstructionMaterials}) {
    wm::ManagementRequest q;q.action=action;q.definition="Construction:ReinforcedWall";
    q.x=2;q.y=3;q.z=4;q.width=2;q.height=2;q.depth=1;
    q.filter=action==wm::ManagementAction::ConstructionMaterials?1:-1;
    q.materialAnchor=wm::TilePos{3,4,4};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*r).has_value());
    REQUIRE(r->material_anchor());CHECK(r->material_anchor()->x()==3);
  }
}

TEST_CASE("construction appearance is owned semantic data with strict optional bounds") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    auto material=b.CreateString(mode==2?"":mode==3?std::string(257,'x'):"INORGANIC:IRON");
    auto subtype=b.CreateString(mode==5?std::string(129,'x'):"ITEM_FIXTURE");
    auto color=b.CreateString(mode==4?std::string("\xff"):mode==10?std::string(129,'x'):"IRON_GRAY");
    auto appearance=wire::CreateConstructionItemAppearance(b,material,subtype,color,
      mode==6?0:mode==7?uint32_t(INT32_MAX)+1:7,mode==8?1:32);
    if(mode==1)appearance={};
    auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("iron bars"),2,appearance);
    auto candidates=b.CreateVector(std::vector{candidate});
    auto row=wire::CreateConstructionMaterial(b,mode==9?-1:0,-1,0,3,b.CreateString("iron bars"),{},1,candidates);
    auto rows=b.CreateVector(std::vector{row});
    wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);
    root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
    b.Finish(root.Finish());auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode>=2));
    if(mode<2) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();
      REQUIRE(decoded.construction.materials.size()==1);
      const auto& item=decoded.construction.materials[0].candidates->at(0);
      CHECK(item.appearance.has_value()==(mode==0));
      if(item.appearance) { CHECK(item.appearance->materialToken=="INORGANIC:IRON");
        CHECK(item.appearance->subtypeRaw=="ITEM_FIXTURE");CHECK(item.appearance->colorToken=="IRON_GRAY");
        CHECK(item.appearance->stack==7);CHECK(item.appearance->flags==32); }
    }
  }
}

TEST_CASE("construction outcomes preserve confirmed effects and reject contradictory receipts") {
  for(int mode=0;mode<12;++mode) {
    const auto outcome=mode<5?wire::ConstructionOutcome(mode):mode==5?wire::ConstructionOutcome(5):
      mode==6?wire::ConstructionOutcome::Complete:mode==7?wire::ConstructionOutcome::Rejected:
      mode==8?wire::ConstructionOutcome::Partial:mode==9?wire::ConstructionOutcome::Unknown:wire::ConstructionOutcome::None;
    const uint32_t placed=(outcome==wire::ConstructionOutcome::Partial && mode!=8) || mode==7 ? 1:0;
    const uint32_t updated=mode==4 || mode==10?2:0;
    const int32_t failed=mode==11?0:(outcome==wire::ConstructionOutcome::Partial || outcome==wire::ConstructionOutcome::Unknown ? 3:-1);
    flatbuffers::FlatBufferBuilder b;
    wire::ConstructionStateBuilder domain(b);domain.add_outcome(outcome);domain.add_placed(placed);
    domain.add_updated(updated);domain.add_failed_index(failed);const auto c=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(c);
    root.add_action(mode==9?wire::ManagementAction::Catalog:wire::ManagementAction::Place);
    root.add_status(mode==6 || outcome!=wire::ConstructionOutcome::Complete?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode>=5));
    if(mode<5) { wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      CHECK(int(decoded.construction.outcome)==int(outcome));CHECK(decoded.construction.updated==updated);
      CHECK(decoded.construction.placed==placed);CHECK(decoded.construction.failedIndex==failed); }
  }
}

TEST_CASE("Construction candidate contract preserves identity and rejects incomplete or ambiguous rows") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ConstructionMaterialCandidate>> items;
    items.push_back(wire::CreateConstructionMaterialCandidate(b,mode==1?-1:10,b.CreateString(mode==2?"":"iron bars [7]"),2));
    items.push_back(wire::CreateConstructionMaterialCandidate(b,mode==3?10:11,b.CreateString(std::string(mode==4?129:9,'x')),mode==5?1:2));
    if(mode==10) { items.clear();for(int id=0;id<16385;++id)
      items.push_back(wire::CreateConstructionMaterialCandidate(b,id,b.CreateString("bars"),0)); }
    auto candidates=b.CreateVector(items);
    if(mode==7)candidates={}; // Aggregate-only source remains distinguishable.
    if(mode==8)candidates=b.CreateVector(std::vector<flatbuffers::Offset<wire::ConstructionMaterialCandidate>>{});
    const auto material=wire::CreateConstructionMaterial(b,0,-1,0,3,b.CreateString("iron bars"),{},mode==6?3:mode==10?16385:2,candidates);
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> rows{material};
    if(mode==9)rows.push_back(wire::CreateConstructionMaterial(b,0,-1,0,4,b.CreateString("copper bars"),{},2,candidates));
    const auto materials=b.CreateVector(rows);
    const auto key=b.CreateString("Construction:Track");
    wire::ConstructionStateBuilder construction(b);construction.add_building_key(key);construction.add_materials(materials);
    const auto domain=construction.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_construction(domain);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode!=0 && mode!=7));
    if(mode==0 || mode==7) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.materials.size()==1);
      const auto& row=decoded.construction.materials[0];
      CHECK(row.candidates.has_value()==(mode==0));
      if(row.candidates) { REQUIRE(row.candidates->size()==2);CHECK(row.candidates->at(0).id==10);
        CHECK(row.candidates->at(0).distance==2);CHECK(row.candidates->at(0).name=="iron bars [7]"); }
    }
  }
}

TEST_CASE("Connected Track preview validates complete geometry and preserves typed outcomes") {
  for(int mode=0;mode<16;++mode) {
    std::vector<wire::TilePos> path{{2,3,4},{1,3,4}};
    auto outcome=wire::ConnectedTrackStatus::Found;
    if(mode>=1 && mode<=5){outcome=wire::ConnectedTrackStatus(mode);path.clear();}
    if(mode==6)path.resize(1);
    if(mode==7)outcome=wire::ConnectedTrackStatus(6);
    if(mode==10)path[1]=wire::TilePos(-1,3,4);
    if(mode==11)path[1]=wire::TilePos(1,2,4);
    if(mode==12)path[1]=wire::TilePos(0,3,4);
    if(mode==13)path.push_back(path[0]);
    if(mode==14)outcome=wire::ConnectedTrackStatus::NoPath;
    if(mode==15)path.resize(wire::kConnectedTrackMaxTiles+1);
    flatbuffers::FlatBufferBuilder b;
    auto track=wire::CreateConnectedTrackPreview(b,outcome,b.CreateVectorOfStructs(path));
    const auto key=b.CreateString(mode==8?"Construction:Wall":"Construction:Track");
    wire::ConstructionStateBuilder construction(b);construction.add_building_key(key);construction.add_connected_track(track);
    const auto domain=construction.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(mode==9?wire::ManagementAction::Catalog:wire::ManagementAction::Preview);root.add_construction(domain);
    b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode>=6));
    if(mode<6) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.connectedTrack);
      CHECK(int(decoded.construction.connectedTrack->status)==mode);
      CHECK(decoded.construction.connectedTrack->path.size()==path.size());
      if(mode==0)CHECK(decoded.construction.connectedTrack->path==std::vector<wm::TilePos>{{2,3,4},{1,3,4}});
    }
  }
}

TEST_CASE("Connected Track keeps ordered endpoints and rejects ambiguous request geometry") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::Preview;
  base.definition="Construction:Track";base.x=20;base.y=19;base.z=18;
  base.connectedTrackDestination=wm::TilePos{2,3,4};
  for(int mode=0;mode<13;++mode) {
    auto q=base;
    if(mode==1)q.action=wm::ManagementAction::Place;
    if(mode==2){q.action=wm::ManagementAction::ConstructionMaterials;q.filter=0;}
    if(mode==3)q.connectedTrackDestination=wm::TilePos{20,19,18}; // native stationary preview
    if(mode==4)q.connectedTrackDestination.reset();
    if(mode==5)q.connectedTrackDestination->x=-1;
    if(mode==6)q.definition="Construction:Wall";
    if(mode==7)q.action=wm::ManagementAction::Catalog;
    if(mode==8)q.width=2;
    if(mode==9)q.height=2;
    if(mode==10)q.depth=2;
    if(mode==11)q.direction=1;
    if(mode==12)q.retracting=true;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);
    CHECK(bool(wire::validateConstructionRequest(*request))==(mode>=4));
    if(mode<3) {
      REQUIRE(request->connected_track());REQUIRE(request->connected_track()->destination());
      CHECK(request->origin()->x()==20);CHECK(request->origin()->z()==18);
      CHECK(request->connected_track()->destination()->x()==2);
      CHECK(request->connected_track()->destination()->y()==3);
      CHECK(request->connected_track()->destination()->z()==4);
    }
  }
}

TEST_CASE("Staff edits require both receipts and reject unrelated fields") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  auto& a=base.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationStaffEdit;
  a.locationSiteId=651;a.locationId=0;a.occupationId=87;
  a.expectedRevision=9007199254740993ULL;a.expectedListRevision=INT64_MAX;
  for(int mode=0;mode<24;++mode) {
    auto q=base;
    if(mode==1)q.area.unitId=0;
    if(mode==2)q.area.unitId=INT32_MAX;
    if(mode==3)q.area.expectedRevision=0;
    if(mode==4)q.area.expectedListRevision=0;
    if(mode==5)q.area.expectedRevision=uint64_t(INT64_MAX)+1;
    if(mode==6)q.area.expectedListRevision=uint64_t(INT64_MAX)+1;
    if(mode==7)q.area.locationSiteId=-1;
    if(mode==8)q.area.locationId=-1;
    if(mode==9)q.area.occupationId=-1;
    if(mode==10)q.area.unitId=-2;
    if(mode==11)q.area.id=0;
    if(mode==12)q.area.cursor=128;
    if(mode==13)q.area.query="fixture";
    if(mode==14)q.area.assign=1;
    if(mode==15)q.area.value=1;
    if(mode==16)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==17)q.action=wm::ManagementAction::AreaInspect;
    if(mode==18)q.area.operation=wm::AreaOperation::LocationAccess;
    if(mode==19)q.area.locationKind=2;
    if(mode==20)q.area.countGeneration=1;
    if(mode==21)q.area.sort=1;
    if(mode==22)q.area.name="fixture";
    if(mode==23)q.area.operation=static_cast<wm::AreaOperation>(26);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=3));
    CHECK(encoded->area()->unit_id()==q.area.unitId);
    CHECK(encoded->area()->expected_revision()==q.area.expectedRevision);
    CHECK(encoded->area()->expected_list_revision()==q.area.expectedListRevision);
  }
}

TEST_CASE("Staff candidate requests own occupation identity and paging receipt") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaInspect;
  auto& a=base.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationStaffCandidates;
  a.locationSiteId=651;a.locationId=0;a.occupationId=87;
  for(int mode=0;mode<17;++mode) {
    auto q=base;
    if(mode==1){q.area.cursor=128;q.area.expectedListRevision=INT64_MAX;}
    if(mode==2)q.area.locationSiteId=-1;
    if(mode==3)q.area.locationId=-1;
    if(mode==4)q.area.occupationId=-1;
    if(mode==5)q.area.id=0;
    if(mode==6)q.area.expectedRevision=1;
    if(mode==7)q.area.cursor=128;
    if(mode==8){q.area.cursor=1;q.area.expectedListRevision=1;}
    if(mode==9)q.area.query="fixture";
    if(mode==10)q.area.unitId=1;
    if(mode==11)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==12)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==13)q.area.operation=wm::AreaOperation::LocationDetails;
    if(mode==14)q.area.sort=1;
    if(mode==15)q.area.countGeneration=1;
    if(mode==16)q.area.occupationId=-2;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=2));
    CHECK(encoded->area()->occupation_id()==q.area.occupationId);
  }
}

TEST_CASE("Staff candidate replies reject malformed pages and preserve native facts") {
  for(int mode=0;mode<46;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationStaffCandidate>> rows;
    const int count=mode==17?129:mode==18?128:mode==19?0:2;
    for(int i=0;i<count;++i) {
      std::vector<flatbuffers::Offset<wire::LocationStaffSkill>> skills;
      skills.push_back(wire::CreateLocationStaffSkill(b,mode==10?-1:58,mode==11?-1:3,mode==12?-1:2000000,mode==13?0:1));
      if(mode==14)skills.push_back(wire::CreateLocationStaffSkill(b,58,3,0,1));
      if(mode==27)for(int j=0;j<10;++j)skills.push_back(wire::CreateLocationStaffSkill(b,j,0,0,1));
      rows.push_back(wire::CreateLocationStaffCandidate(b,mode==8?1:100+i,mode==9?-2:900+i,
          b.CreateString(std::string(mode==15?2049:mode==18?2048:5,'x')),mode==16?4:mode==26?i+2:3,b.CreateVector(skills),
          mode==32?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(std::string(mode==28?2049:mode==34?0:4,'b')),
          mode==33?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(std::string(mode==29?2049:mode==35?0:4,'p')),
          mode==30?-1:mode==31?16:7,i!=0,
          mode==36?-1:mode==37?0:mode==38?count:mode==45?1-i:i,mode==39?-1:809,mode==40?-1:100000,
          mode==41?flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{}:b.CreateVector(std::vector<uint8_t>(mode==43?2049:2,255)),
          mode==42?flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{}:b.CreateVector(std::vector<uint8_t>(mode==44?2049:2,128))));
    }
    const auto page=wire::CreateLocationStaffCandidates(b,mode==2?-1:651,0,mode==3?-1:87,mode==4?3:8,
        mode==5?0:INT64_MAX,mode==6?1:0,mode==7?128:0,mode==20?3:count,b.CreateVector(rows));
    wire::AreaStateBuilder area(b);area.add_operation(mode==21?wire::AreaOperation::None:wire::AreaOperation::LocationStaffCandidates);
    if(mode!=1 && mode!=22)area.add_location_staff_candidates(page);
    if(mode==23)area.add_next_cursor(128);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);
    root.add_revision(1);root.add_world_epoch(7);root.add_action(mode==24?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect);
    root.add_status(mode==1 || mode==25?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode!=0 && mode!=1 && mode!=19 && mode!=34 && mode!=35));
    if(mode==0) {
      const auto model=codec::decodeArea(state->area());REQUIRE(model.locationStaffCandidates);
      const auto& c=*model.locationStaffCandidates;CHECK(c.siteId==651);CHECK(c.locationId==0);CHECK(c.occupationId==87);
      CHECK(c.role==8);CHECK(c.revision==INT64_MAX);CHECK(c.cursor==0);CHECK(c.nextCursor==0);CHECK(c.total==2);
      REQUIRE(c.rows.size()==2);CHECK(c.rows[1].unitId==101);CHECK(c.rows[1].histfigId==901);
      CHECK(c.rows[1].sourceIndex==1);CHECK(c.rows[1].professionOrder==809);CHECK(c.rows[1].statusOrder==100000);
      CHECK(c.rows[1].nameSortKey==std::vector<uint8_t>{255,255});CHECK(c.rows[1].professionSortKey==std::vector<uint8_t>{128,128});
      CHECK(c.rows[1].baseName=="bbbb");CHECK(c.rows[1].professionName=="pppp");CHECK(c.rows[1].professionColor==7);
      CHECK_FALSE(c.rows[0].legendary);CHECK(c.rows[1].legendary); // unrelated skills can make the name legendary
      CHECK(c.rows[1].name=="xxxxx");CHECK(c.rows[1].score==3);REQUIRE(c.rows[1].skills.size()==1);
      CHECK(c.rows[1].skills[0].id==58);CHECK(c.rows[1].skills[0].rating==3);
      CHECK(c.rows[1].skills[0].experience==2000000);CHECK(c.rows[1].skills[0].weight==1);
    }
    if(mode==1)CHECK_FALSE(codec::decodeArea(state->area()).locationStaffCandidates);
  }
}

TEST_CASE("Location details requests require their own site and location identities") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationDetails;
  a.locationSiteId=651;a.locationId=0;
  for(int mode=0;mode<11;++mode) {
    auto q=request;
    if(mode==1)q.area.locationSiteId=-1;
    if(mode==2)q.area.locationId=-1;
    if(mode==3)q.area.id=23;
    if(mode==4)q.area.expectedRevision=7;
    if(mode==5)q.area.cursor=1;
    if(mode==6)q.area.query="fixture";
    if(mode==7)q.area.expectedListRevision=7;
    if(mode==8)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==9)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==10){q.area.operation=wm::AreaOperation::LocationList;q.area.id=23;q.area.locationId=-2;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode!=0));
    if(mode==0){CHECK(encoded->area()->location_site_id()==651);CHECK(encoded->area()->location_id()==0);}
  }
}

TEST_CASE("Location details replies validate ownership and preserve raw facts") {
  for(int mode=0;mode<31;++mode) {
    const int appraisal=mode==12?-3:mode==13?-2:mode==14?-1:mode==15?0:mode==16?INT32_MAX:10;
    const int dx=mode==24?-2:mode==25?-1:mode==26?0:mode==27?-1:mode==28?0:mode==29?2:mode==30?INT32_MAX:7;
    const int dy=mode==25?-1:mode==26?0:mode==28?2:mode==29?0:8;
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<(mode==2?9:10);++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,mode==3?0:i,INT32_MAX-i,15000+i));
    const auto zones=b.CreateVector(std::vector<int32_t>{23,mode==4?23:914});
    const auto facilities=wire::CreateLocationFacilities(b,mode==17?-1:3,7,1,1,17,1,2,mode==18?3:1);
    const auto detail=wire::CreateLocationDetails(b,mode==5?-1:651,0,mode==6?0:5,b.CreateString("Synthetic hospital"),
        mode==7?0:9007199254740993ULL,mode==8?3:0,true,true,false,-1,0,272,2,true,b.CreateVector(supplies),zones,appraisal,mode==19?0:facilities,mode==20?-2:mode==21?-1:mode==22?0:mode==23?INT32_MAX:6,dx,dy);
    wire::AreaStateBuilder area(b);area.add_operation(mode==9?wire::AreaOperation::None:wire::AreaOperation::LocationDetails);
    if(mode!=1 && mode!=10)area.add_location_details(detail);
    if(mode==11)area.add_next_cursor(1);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);
    root.add_revision(1);root.add_world_epoch(7);root.add_action(wire::ManagementAction::AreaInspect);
    root.add_status(mode==1?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==((mode>=2 && mode<=12) || mode==17 || mode==18 || mode==20 || mode==24 || (mode>=27 && mode<=29)));
    if(mode==0 || (mode>=13 && mode!=17 && mode!=18 && mode!=20 && mode!=24 && !(mode>=27 && mode<=29))) {
      auto model=codec::decodeArea(state->area());REQUIRE(model.locationDetails);
      const auto& d=*model.locationDetails;CHECK(d.siteId==651);CHECK(d.id==0);CHECK(d.kind==5);
      CHECK(d.revision==9007199254740993LL);CHECK(d.name=="Synthetic hospital");CHECK(d.recognized);
      CHECK(d.visitors);CHECK(d.residents);CHECK_FALSE(d.members);CHECK(d.access==0);
      CHECK(d.profession==-1);CHECK(d.tier==0);CHECK(d.value==272);CHECK(d.desiredCopies==2);CHECK(d.appraisal==appraisal);
      CHECK(d.writtenObjects==(mode==21?-1:mode==22?0:mode==23?INT32_MAX:6));
      CHECK_FALSE(d.staff);
      CHECK(d.danceFloorX==dx);CHECK(d.danceFloorY==dy);
      REQUIRE(d.supplies.size()==10);CHECK(d.supplies[4].kind==4);CHECK(d.supplies[4].stored==INT32_MAX-4);CHECK(d.supplies[4].desired==15004);
      CHECK(d.zoneIds==std::vector<int32_t>{23,914});
      if(mode==19)CHECK_FALSE(d.facilities);
      else {REQUIRE(d.facilities);const auto& f=*d.facilities;
        CHECK(f.chests==3);CHECK(f.beds==7);CHECK(f.tables==1);CHECK(f.tractionBenches==1);
        CHECK(f.bookcases==17);CHECK(f.chairs==1);CHECK(f.rooms==2);CHECK(f.rentedRooms==1);}

    }
    if(mode==1)CHECK_FALSE(codec::decodeArea(state->area()).locationDetails);
  }
}

TEST_CASE("Location choice requests own only catalog selector and page receipt") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  request.area.kind=wm::AreaKind::Zone;request.area.operation=wm::AreaOperation::LocationChoices;request.area.locationKind=2;
  for(int mode=0;mode<12;++mode) {
    auto q=request;
    if(mode==1){q.area.locationKind=4;q.area.cursor=128;q.area.expectedListRevision=19;}
    if(mode==2)q.area.locationKind=1;
    if(mode==3)q.area.id=4;
    if(mode==4)q.area.expectedRevision=3;
    if(mode==5)q.area.cursor=128;
    if(mode==6){q.area.cursor=1;q.area.expectedListRevision=19;}
    if(mode==7)q.area.profession=41;
    if(mode==8)q.area.query="fixture";
    if(mode==9)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==10)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==11)q.area.countGeneration=5;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    CAPTURE(mode);
    CHECK(bool(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())))==(mode>=2));
  }
}

TEST_CASE("Typed location pages validate nested identities and preserve model metadata") {
  for(int mode=0;mode<10;++mode) {
    flatbuffers::FlatBufferBuilder b;
    auto deity=wire::CreateLocationDeity(b,7,b.CreateString("Synthetic deity"),b.CreateVector(std::vector<int32_t>{3,mode==2?130:8}));
    auto sentinel=wire::CreateLocationReligion(b,1,-1,b.CreateString(""),0,false);
    auto named=wire::CreateLocationReligion(b,2,mode==3?9:7,b.CreateString("Synthetic deity"),mode==4?-1:24,true,b.CreateVector(std::vector{deity}));
    auto rows=b.CreateVector(std::vector{sentinel,named});
    auto catalog=wire::CreateLocationCatalog(b,mode==5?4:2,mode==6?0:25,mode==7?1:0,mode==8?3:2,mode==9?128:0,rows);
    wire::AreaStateBuilder area(b);area.add_operation(mode==1?wire::AreaOperation::None:wire::AreaOperation::LocationChoices);area.add_location_catalog(catalog);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());const auto* wireArea=state->area();
    CAPTURE(mode);
    CHECK(bool(wire::validateLocationCatalog(*wireArea->location_catalog()))==(mode>=2));
    CHECK(bool(wire::validateManagementState(*state))==(mode>=1));
    if(mode==0) {
      const auto model=codec::decodeArea(wireArea);
      REQUIRE(model.locationCatalog);CHECK(model.locationCatalog->revision==25);
      REQUIRE(model.locationCatalog->religions.size()==2);
      const auto& row=model.locationCatalog->religions[1];CHECK(row.id==7);CHECK(row.worshippers==24);CHECK(row.hasTemple);
      REQUIRE(row.deities.size()==1);CHECK(row.deities[0].name=="Synthetic deity");CHECK(row.deities[0].spheres==std::vector<int32_t>{3,8});
    }
  }
}

TEST_CASE("management schema defaults match the versioned transport") {
  flatbuffers::FlatBufferBuilder b;
  b.Finish(wire::CreateConstructionRequest(b));
  CHECK(flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())->schema_version()==wire::kManagementVersion);
  b.Clear();b.Finish(wire::CreateManagementState(b));
  CHECK(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())->schema_version()==wire::kManagementVersion);
}

TEST_CASE("Paint count requests preserve local geometry and reject mutation fields") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::PaintCounts;
  a.zoneType=92;a.paintZ=32767;a.countGeneration=INT64_MAX;
  for(int mode=0;mode<18;++mode) {
    auto q=request;auto& v=q.area;
    if(mode==1)v.paintPreview=wm::AreaPaintPreview{32767,32767,1,1};
    if(mode==2) {
      for(int y=0;y<128;++y)for(int x=0;x<256;++x)v.spans.push_back({int16_t(y),int16_t(x),1});
      v.paintPreview=wm::AreaPaintPreview{0,0,256,128};
    }
    if(mode==3)v.countGeneration=0;
    if(mode==4)v.countGeneration=-1;
    if(mode==5)v.id=1;
    if(mode==6)v.expectedRevision=1;
    if(mode==7)v.interactionId=1;
    if(mode==8)v.undoToken=1;
    if(mode==9)v.paintMode=1;
    if(mode==10)q.action=wm::ManagementAction::AreaCreate;
    if(mode==11)v.paintPreview=wm::AreaPaintPreview{32767,0,2,1};
    if(mode==12)v.paintPreview=wm::AreaPaintPreview{0,0,256,129};
    if(mode==13)v.spans={{1,0,2},{1,1,1}};
    if(mode==14)v.spans={{1,0,1},{0,0,1}};
    if(mode==15)v.spans={{0,0,1},{256,0,1}};
    if(mode==16)v.paintZ=-1;
    if(mode==17)v.kind=wm::AreaKind::Stockpile;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*wireRequest))==(mode>=3));
    if(mode<3) {
      CHECK(b.GetSize()<wire::kManagementCommandCapacity);
      CHECK(wireRequest->area()->count_generation()==uint64_t(INT64_MAX));
      CHECK(wireRequest->area()->paint_z()==32767);
      CHECK_FALSE(wireRequest->area()->origin());
      CHECK(bool(wireRequest->area()->paint_preview())==(mode!=0));
      if(mode==1)CHECK(wireRequest->area()->paint_preview()->x()==32767);
      if(mode==2)CHECK(wireRequest->area()->spans()->size()==32768);
    }
  }
  for(int field=0;field<2;++field) {
    auto q=request;q.action=wm::ManagementAction::AreaCreate;
    q.area.operation=wm::AreaOperation::Paint;q.area.paintMode=1;q.area.spans={{0,0,1}};
    q.area.countGeneration=field==0?1:0;
    if(field==1)q.area.paintPreview=wm::AreaPaintPreview{0,0,1,1};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).has_value());
  }
}

TEST_CASE("Paint count replies distinguish unknown from zero and reject foreign fields") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);
    a.add_operation(mode==10?wire::AreaOperation::Paint:wire::AreaOperation::PaintCounts);
    a.add_count_generation(mode==3?0:mode==4?uint64_t(INT64_MAX)+1:uint64_t(INT64_MAX));
    a.add_painted_count(mode==0?-1:mode==1?0:mode==5?-2:mode==6?32769:32768);
    a.add_preview_count(mode==0?3:0);
    if(mode==7)a.add_interaction_id(1);
    if(mode==8)a.add_next_cursor(1);
    if(mode==9)a.add_area_id(1);
    const auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode>=3));
    if(mode<3) {
      const auto result=codec::decodeArea(state->area());
      CHECK(result.countGeneration==INT64_MAX);CHECK(result.paintedCount==(mode==0?-1:mode==1?0:32768));
      CHECK(result.previewCount==(mode==0?3:0));CHECK(result.undoToken==0);
    }
  }
}

TEST_CASE("Multi requests carry selection and scoped Undo without area-page limits") {
  for(int op=16;op<=18;++op) {
    wm::ManagementRequest request;
    request.action=op==16?wm::ManagementAction::AreaCreate:wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation(op);a.interactionId=INT64_MAX;
    if(op==16){a.x=0;a.y=0;a.z=32767;a.width=32768;a.height=32768;a.roomFurniture=4;}
    if(op==17)a.undoToken=INT64_MAX;
    for(int defect=0;defect<8;++defect) {
      auto candidate=request;auto& v=candidate.area;
      if(defect==1)v.interactionId=0;
      if(defect==2)v.id=1;
      if(defect==3)v.expectedRevision=1;
      if(defect==4)v.kind=wm::AreaKind::Stockpile;
      if(defect==5){if(op==16)v.x=1;else v.roomFurniture=1;}
      if(defect==6){if(op==17)v.undoToken=0;else v.undoToken=1;}
      if(defect==7)v.interactionId=-1;
      flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,candidate,1,2,3);
      const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
      const auto error=wire::validateConstructionRequest(*r);CAPTURE(op);CAPTURE(defect);
      CHECK(bool(error)==(defect!=0));
      if(!defect) {
        CHECK(r->area()->interaction_id()==uint64_t(INT64_MAX));
        CHECK(r->area()->undo_token()==uint64_t(a.undoToken));
        CHECK(bool(r->area()->origin())==(op==16));
        if(op==16){CHECK(r->area()->width()==32768);CHECK(r->area()->room_furniture()==4);}
      }
    }
  }
}

TEST_CASE("Multi receipt replies carry native counts independently of area records") {
  for(int op=16;op<=18;++op)for(int defect=0;defect<7;++defect) {
    flatbuffers::FlatBufferBuilder b;
    wire::AreaStateBuilder a(b);a.add_operation(wire::AreaOperation(op));
    a.add_interaction_id(defect==1?0:INT64_MAX);
    a.add_room_outcome(defect==2?wire::AreaRoomOutcome::None:wire::AreaRoomOutcome::Completed);
    if(op==16){a.add_undo_token(defect==3?0:INT64_MAX);a.add_rooms_created(129);a.add_rooms_in_use(1000);a.add_rooms_unenclosed(2000);}
    else {if(defect==3)a.add_undo_token(1);if(op==17)a.add_rooms_removed(129);}
    if(defect==4)a.add_area_id(7);
    if(defect==5)a.add_next_cursor(1);
    a.add_rooms_dormitories(defect==6?130:op==16?7:0);
    const auto domain=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(op);CAPTURE(defect);CHECK(bool(wire::validateManagementState(*state))==(defect!=0));
    if(!defect) {
      const auto result=codec::decodeArea(state->area());
      CHECK(result.interactionId==INT64_MAX);CHECK(result.areas.empty());
      CHECK(result.roomOutcome==wm::AreaRoomOutcome::Completed);
      CHECK(result.roomsDormitories==uint32_t(op==16?7:0));
      if(op==16){CHECK(result.undoToken==INT64_MAX);CHECK(result.roomsCreated==129);CHECK(result.roomsInUse==1000);CHECK(result.roomsUnenclosed==2000);}
      if(op==17)CHECK(result.roomsRemoved==129);
    }
  }
}

TEST_CASE("Multi request fields cannot leak into older area operations") {
  for(int field=0;field<3;++field) {
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCreate;
    auto& a=request.area;a.operation=wm::AreaOperation::Paint;a.paintMode=1;a.paintZ=0;a.spans={{0,0,1}};
    if(field==0)a.roomFurniture=1;
    if(field==1)a.interactionId=1;
    if(field==2)a.undoToken=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*r).has_value());
  }
  for(int op=16;op<=18;++op)for(int action=8;action<=14;++action) {
    wm::ManagementRequest request;request.action=wm::ManagementAction(action);
    auto& a=request.area;a.operation=wm::AreaOperation(op);a.kind=wm::AreaKind::Zone;a.interactionId=1;
    if(op==16)a.roomFurniture=1;
    if(op==17)a.undoToken=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*r))!=(action==(op==16?10:11)));
  }
}

TEST_CASE("Multi outcomes distinguish empty creation and uncertain partial removal") {
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);
    a.add_operation(mode==0?wire::AreaOperation::MultiCreate:wire::AreaOperation::MultiUndo);
    a.add_interaction_id(1);
    a.add_room_outcome(mode==0?wire::AreaRoomOutcome::Completed:
        mode==1?wire::AreaRoomOutcome::Unknown:mode==2?wire::AreaRoomOutcome::Rejected:wire::AreaRoomOutcome::Stale);
    if(mode==1 || mode==4)a.add_rooms_removed(2);
    const auto domain=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state))==(mode==4));
  }
}

TEST_CASE("full paint fits one versioned management command") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCreate;
  auto& a=request.area;a.operation=wm::AreaOperation::Paint;a.paintMode=1;a.paintZ=3;
  // Deliberately uncoalesced worst case: one span per supported footprint cell.
  for(int y=0;y<128;++y)for(int x=0;x<256;++x)a.spans.push_back({int16_t(y),int16_t(x),1});
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  CHECK(b.GetSize()<wire::kManagementCommandCapacity);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).value_or("")=="");
  CHECK(r->area()->spans()->size()==32768);
  a.spans.push_back({128,0,1});b.Clear();codec::encodeRequest(b,request,1,2,3);
  r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).value_or("")=="too many area spans");
}

TEST_CASE("area operation codecs preserve every selector and omit legacy origin") {
  const wm::ManagementAction actions[]{wm::ManagementAction::AreaInspect,wm::ManagementAction::AreaInspect,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaCreate,wm::ManagementAction::AreaInspect,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaInspect,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaCandidates,wm::ManagementAction::AreaLink};
  for(int op=0;op<=15;++op) {
    CAPTURE(op);
    wm::ManagementRequest request;request.action=actions[op];auto& a=request.area;
    a.operation=wm::AreaOperation(op);a.id=7;a.expectedRevision=INT64_MAX;a.query="observed";a.cursor=128;
    a.kind=op==15?wm::AreaKind::Workshop:((op>=6 && op<=9) || op==11 || op==12 || op==14)?wm::AreaKind::Zone:wm::AreaKind::Stockpile;
    if(op==0){a.x=10;a.y=11;a.z=12;a.width=3;a.height=4;a.categories=3;a.changedCategories=1;a.barrels=2;a.bins=3;a.wheelbarrows=1;a.linksOnly=1;}
    if(op==1 || op==6 || op==10 || op==14)a.expectedListRevision=INT64_MAX;
    if(op==1 || op==2)a.listKey="food/meat";
    if(op==2){a.rowKey="material:4";a.scope=1;a.value=2;}
    if(op==3)a.preset=19;
    if(op==4)a.name="Native name";
    if(op==5){a.id=-1;a.paintZ=17;a.paintMode=1;a.spans={{14,15,128},{15,15,256}};a.zoneType=1;}
    if(op==7)a.locationId=-1;
    if(op==8){a.locationKind=2;a.deityKind=3;a.deityId=900;}
    if(op==9)a.zoneSettings={2,4,0,1,1,0};
    if(op==11){a.unitId=0;a.assign=0;}
    if(op==12){a.squadId=0;a.squadUse=0;}
    if(op==13){a.organic=0;a.inorganic=1;}
    if(op==14){a.candidateKind=3;a.sort=3;a.sortDescending=true;}
    if(op==15){a.linkId=8;a.give=false;a.unlink=true;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*r).value_or("")=="");
    const auto* q=r->area();REQUIRE(q);CHECK(int(q->operation())==op);CHECK(q->id()==a.id);CHECK(int(q->kind())==int(a.kind));
    CHECK(q->expected_revision()==INT64_MAX);CHECK(q->expected_list_revision()==uint64_t(a.expectedListRevision));
    CHECK(q->query()->str()==a.query);CHECK(q->cursor()==a.cursor);
    CHECK((q->origin()!=nullptr)==(op==0));
    if(q->origin()){CHECK(q->origin()->x()==10);CHECK(q->origin()->y()==11);CHECK(q->origin()->z()==12);}
    CHECK(q->width()==a.width);CHECK(q->height()==a.height);CHECK(q->zone_type()==a.zoneType);
    CHECK(q->categories()==a.categories);CHECK(q->changed_categories()==a.changedCategories);
    CHECK(q->barrels()==a.barrels);CHECK(q->bins()==a.bins);CHECK(q->wheelbarrows()==a.wheelbarrows);
    CHECK(q->links_only()==a.linksOnly);CHECK(q->active()==a.active);CHECK(q->owner_id()==a.ownerId);
    CHECK(q->link_id()==a.linkId);CHECK(q->give()==a.give);CHECK(q->unlink()==a.unlink);
    CHECK(q->list_key()->str()==a.listKey);CHECK(q->row_key()->str()==a.rowKey);CHECK(q->name()->str()==a.name);
    CHECK(q->scope()==a.scope);CHECK(q->value()==a.value);CHECK(q->preset()==a.preset);
    CHECK(q->spans()->size()==a.spans.size());
    for(size_t i=0;i<a.spans.size();++i){CHECK(q->spans()->Get(i)->y()==a.spans[i].y);CHECK(q->spans()->Get(i)->x()==a.spans[i].x);CHECK(q->spans()->Get(i)->length()==a.spans[i].length);}
    CHECK(q->paint_mode()==a.paintMode);CHECK(q->paint_z()==a.paintZ);CHECK(q->location_id()==a.locationId);
    CHECK(q->location_kind()==a.locationKind);CHECK(q->profession()==a.profession);CHECK(q->deity_kind()==a.deityKind);CHECK(q->deity_id()==a.deityId);
    REQUIRE(q->zone_settings());const auto* z=q->zone_settings();
    CHECK(z->pond_mode()==a.zoneSettings.pondMode);CHECK(z->facing()==a.zoneSettings.facing);
    CHECK(z->tomb_citizens()==a.zoneSettings.tombCitizens);CHECK(z->tomb_pets()==a.zoneSettings.tombPets);
    CHECK(z->gather_trees()==a.zoneSettings.gatherTrees);CHECK(z->gather_shrubs()==a.zoneSettings.gatherShrubs);
    CHECK(q->unit_id()==a.unitId);CHECK(q->assign()==a.assign);CHECK(q->squad_id()==a.squadId);CHECK(q->squad_use()==a.squadUse);
    CHECK(q->organic()==a.organic);CHECK(q->inorganic()==a.inorganic);CHECK(q->candidate_kind()==a.candidateKind);
    CHECK(q->sort()==a.sort);CHECK(q->sort_descending()==a.sortDescending);
    a.expectedRevision=0;
    flatbuffers::FlatBufferBuilder missing;codec::encodeRequest(missing,request,1,2,3);
    const bool mutation=request.action==wm::ManagementAction::AreaUpdate || request.action==wm::ManagementAction::AreaLink;
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(missing.GetBufferPointer())).value_or("") ==
        (mutation ? "area revision required" : ""));
  }
}

TEST_CASE("legacy area mutations and update paint require an inspection revision") {
  for(auto action:{wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaDelete,wm::ManagementAction::AreaLink}) {
    for(int64_t revision:{int64_t(0),int64_t(1),INT64_MAX}) {
      wm::ManagementRequest request;request.action=action;request.area.id=7;request.area.linkId=8;
      request.area.expectedRevision=revision;
      flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
      CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("") ==
          (revision ? "" : "area revision required"));
    }
  }
  wm::ManagementRequest paint;paint.action=wm::ManagementAction::AreaUpdate;
  paint.area.operation=wm::AreaOperation::Paint;paint.area.id=7;paint.area.paintMode=1;paint.area.spans={{1,1,1}};
  for(int64_t revision:{int64_t(0),INT64_MAX}) {
    paint.area.expectedRevision=revision;flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,paint,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("") ==
        (revision ? "" : "area revision required"));
  }
}

TEST_CASE("legacy area choices cannot share a response with area records or new pages") {
  for(int family=0;family<5;++family) {
    CAPTURE(family);flatbuffers::FlatBufferBuilder b;
    const auto text=b.CreateString("observed");
    const auto choices=b.CreateVector(std::vector{wire::CreateAreaChoice(b,1,text,text)});
    wire::TilePos origin(1,2,3);
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);
    const auto areas=b.CreateVector(std::vector{info.Finish()});
    const auto settings=b.CreateVector(std::vector{wire::CreateAreaSettingRow(b,text,0,text,1,1)});
    const auto locations=b.CreateVector(std::vector{wire::CreateAreaLocationRow(b,1,text,1)});
    const auto candidates=b.CreateVector(std::vector{wire::CreateAreaCandidateRow(b,1,text)});
    const auto links=b.CreateVector(std::vector{wire::CreateAreaLinkRow(b,1,wire::AreaKind::Stockpile,1,text)});
    wire::AreaStateBuilder area(b);area.add_choices(choices);
    if(family==0)area.add_areas(areas);
    if(family==1)area.add_settings(settings);
    if(family==2)area.add_locations(locations);
    if(family==3)area.add_candidates(candidates);
    if(family==4)area.add_links(links);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    CHECK(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())).value_or("") == "area response mixes list families");
  }
}

TEST_CASE("work order choices reject area-only labels but retain legacy names") {
  for(int label=0;label<3;++label) {
    flatbuffers::FlatBufferBuilder b;const auto name=b.CreateString("native name");
    const auto areaLabel=label ? b.CreateString(label==1 ? "" : "area label") : flatbuffers::Offset<flatbuffers::String>{};
    const auto choices=b.CreateVector(std::vector{wire::CreateAreaChoice(b,1,name,areaLabel)});
    wire::WorkOrderStateBuilder work(b);work.add_choices(choices);const auto domain=work.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_work_order(domain);b.Finish(root.Finish());
    CHECK(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())).value_or("") ==
        (label==2 ? "invalid work order choice" : ""));
  }
}

TEST_CASE("area response codec carries list families and unknown sentinels") {
  for(int family=0;family<6;++family) {
    CAPTURE(family);flatbuffers::FlatBufferBuilder b;
    const auto text=b.CreateString("observed"),key=b.CreateString("food/meat");
    const auto zone=wire::CreateAreaZoneSettings(b,2,4,0,1,1,0);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});wire::TilePos origin(1,2,3);
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);info.add_extents(extents);
    info.add_name(text);info.add_revision(INT64_MAX);info.add_zone_label(text);info.add_location_id(99);info.add_location_site_id(651);info.add_location_name(text);
    info.add_religion(text);info.add_organic(0);info.add_inorganic(1);info.add_zone_settings(zone);info.add_tile_count(1);info.add_assigned_count(4);
    info.add_location_kind(2);info.add_owner_profession(text);info.add_owner_sex(1);
    const auto record=info.Finish();const auto areas=b.CreateVector(std::vector{record});
    const auto setting=wire::CreateAreaSettingRow(b,key,5,text,4,3,true);const auto settings=b.CreateVector(std::vector{setting});
    const auto location=wire::CreateAreaLocationRow(b,99,text,4,text,41,2,651);const auto locations=b.CreateVector(std::vector{location});
    const auto candidate=wire::CreateAreaCandidateRow(b,8,text,text,1,7,true,true,15);const auto candidates=b.CreateVector(std::vector{candidate});
    const auto link=wire::CreateAreaLinkRow(b,9,wire::AreaKind::Workshop,2,text);const auto links=b.CreateVector(std::vector{link});
    const auto choice=wire::CreateAreaChoice(b,1,text,text);const auto choices=b.CreateVector(std::vector{choice});
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::CandidateList);area.add_area_id(7);area.add_list_key(key);
    area.add_candidate_kind(3);area.add_sort(2);area.add_sort_descending(true);area.add_query(text);area.add_list_revision(INT64_MAX);
    area.add_build_phase(2);area.add_build_done(18);area.add_build_total(19);area.add_omitted(4);area.add_captured_tick(9876543210);
    area.add_next_cursor(128);area.add_truncated(true);
    if(family<4)area.add_areas(areas);
    if(family==0)area.add_settings(settings);
    if(family==1)area.add_locations(locations);
    if(family==2)area.add_candidates(candidates);
    if(family==3)area.add_links(links);
    if(family==4)area.add_choices(choices);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    REQUIRE_FALSE(wire::validateManagementState(*state));const auto decoded=codec::decodeArea(state->area());
    CHECK(decoded.operation==wm::AreaOperation::CandidateList);CHECK(decoded.areaId==7);CHECK(decoded.listKey=="food/meat");
    CHECK(decoded.candidateKind==3);CHECK(decoded.sort==2);CHECK(decoded.sortDescending);CHECK(decoded.query=="observed");
    CHECK(decoded.listRevision==INT64_MAX);CHECK(decoded.buildPhase==2);CHECK(decoded.buildDone==18);CHECK(decoded.buildTotal==19);
    CHECK(decoded.omitted==4);CHECK(decoded.capturedTick==9876543210);CHECK(decoded.nextCursor==128);CHECK(decoded.truncated);
    if(family<4){REQUIRE(decoded.areas.size()==1);const auto& v=decoded.areas[0];CHECK(v.revision==INT64_MAX);CHECK(v.zoneLabel=="observed");
      CHECK(v.locationId==99);CHECK(v.locationSiteId==651);CHECK(v.locationName=="observed");CHECK(v.religion=="observed");CHECK(v.organic==0);CHECK(v.inorganic==1);
      CHECK(v.zoneSettings==wm::AreaZoneSettings{2,4,0,1,1,0});CHECK(v.tileCount==1);CHECK(v.assignedCount==4);
      CHECK(v.locationKind==2);CHECK(v.ownerProfession=="observed");CHECK(v.ownerSex==1);}
    if(family==0){REQUIRE(decoded.settings.size()==1);const auto& v=decoded.settings[0];CHECK(v.key=="food/meat");CHECK(v.index==5);CHECK(v.label=="observed");CHECK(v.kind==4);CHECK(v.state==3);CHECK(v.estimated);}
    if(family==1){REQUIRE(decoded.locations.size()==1);const auto& v=decoded.locations[0];CHECK(v.id==99);CHECK(v.name=="observed");CHECK(v.locationKind==4);CHECK(v.religion=="observed");CHECK(v.guildProfession==41);CHECK(v.locationTier==2);CHECK(v.siteId==651);}
    if(family==2){REQUIRE(decoded.candidates.size()==1);const auto& v=decoded.candidates[0];CHECK(v.id==8);CHECK(v.name=="observed");CHECK(v.profession=="observed");CHECK(v.sex==1);CHECK(v.mood==7);CHECK(v.grazer);CHECK(v.assigned);CHECK(v.squadUse==15);}
    if(family==3){REQUIRE(decoded.links.size()==1);const auto& v=decoded.links[0];CHECK(v.id==9);CHECK(v.kind==wm::AreaKind::Workshop);CHECK(v.direction==2);CHECK(v.name=="observed");}
    if(family==4){REQUIRE(decoded.choices.size()==1);CHECK(decoded.choices[0].label=="observed");}
    if(family==5){CHECK(decoded.areas.empty());CHECK(decoded.candidates.empty());}
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateAreaState(b));
  const auto empty=codec::decodeArea(flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer()));
  CHECK(empty.areaId==-1);CHECK(empty.capturedTick==-1);CHECK(empty.listRevision==0);CHECK(empty.buildPhase==0);
  CHECK(wm::AreaRequest{}.locationId==-2);CHECK(wm::AreaRequest{}.deityKind==-1);CHECK(wm::AreaInfo{}.tileCount==-1);CHECK(wm::AreaInfo{}.locationSiteId==-1);CHECK(wm::AreaLocationRow{}.siteId==-1);
}

TEST_CASE("area metadata validates boundaries and preserves unknown values") {
  for(int variant=0;variant<5;++variant) {
    flatbuffers::FlatBufferBuilder b;wire::TilePos origin(1,2,3);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});
    const auto profession=b.CreateString(std::string(variant==4 ? 513 : 0,'x'));
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);info.add_extents(extents);
    info.add_location_kind(variant==1 ? 6 : 0);info.add_owner_sex(variant==2 ? 2 : variant==3 ? -2 : -1);info.add_owner_profession(profession);
    const auto rows=b.CreateVector(std::vector{info.Finish()});
    const auto area=wire::CreateAreaState(b,rows);wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(variant!=0));
    if(variant==0){const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.areas.size()==1);
      CHECK(decoded.areas[0].locationKind==0);CHECK(decoded.areas[0].ownerSex==-1);CHECK(decoded.areas[0].ownerProfession.empty());}
  }
}

TEST_CASE("work detail request boundaries and absent optional edits") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,1,7);
    auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    CHECK(error.value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailCreate;r.citizen.expectedRevision=INT64_MAX;
  check(r,"");r.citizen.name="";r.citizen.labors={};check(r,"");
  r.citizen.unitId=-2;check(r,"invalid citizen request");r.citizen.unitId=-1;
  r.citizen.detailIndex=-2;check(r,"invalid citizen request");r.citizen.detailIndex=-1;
  r.citizen.member=0;check(r,"unexpected citizen edit fields");r.citizen.member=-1;
  r.citizen.mode=0;check(r,"unexpected citizen edit fields");r.citizen.mode=-1;
  r.citizen.edit=1;check(r,"unexpected work detail edit");r.citizen.edit=0;
  r.citizen.onlyAssigned=0;check(r,"unexpected citizen work scope");r.citizen.onlyAssigned=-1;
  r.citizen.expectedRevision=uint64_t(INT64_MAX)+1;check(r,"invalid citizen request");r.citizen.expectedRevision=INT64_MAX;
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.unitId=0;check(r,"unexpected new work detail identity");r.citizen.unitId=-1;
  r.citizen.expectedRevision=0;check(r,"citizen receipt required");r.citizen.expectedRevision=1;
  for(auto action:{wm::ManagementAction::WorkDetailCreate,wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit,wm::ManagementAction::CitizenWorkScope}) {
    auto search=r;search.action=action;
    if(action==wm::ManagementAction::WorkDetailDelete || action==wm::ManagementAction::WorkDetailEdit)search.citizen.detailIndex=0;
    if(action==wm::ManagementAction::WorkDetailEdit)search.citizen.edit=1;
    if(action==wm::ManagementAction::CitizenWorkScope){search.citizen.unitId=0;search.citizen.onlyAssigned=0;}
    check(search,"");search.citizen.cursor=1;check(search,"unexpected citizen search");search.citizen.cursor=0;
    search.citizen.query="x";check(search,"unexpected citizen search");search.citizen.query="";check(search,"");
    search.citizen.expectedRevision=0;check(search,"citizen receipt required");
  }
  for(auto action:{wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit}) {
    r.action=action;r.citizen.edit=action==wm::ManagementAction::WorkDetailEdit?1:0;
    check(r,"work detail index required");r.citizen.detailIndex=0;check(r,"");
    r.citizen.detailIndex=127;check(r,"");r.citizen.detailIndex=128;check(r,"invalid citizen request");
    r.citizen.detailIndex=-1;
  }
  r.citizen.detailIndex=0;r.citizen.edit=1;
  r.citizen.name=std::string(160,'x');check(r,"");r.citizen.name+='x';check(r,"work detail name too long");
  r.citizen.name="";check(r,"");r.citizen.edit=0;check(r,"invalid work detail edit");
  r.citizen.edit=4;check(r,"invalid work detail edit");r.citizen.edit=2;
  for(int i=0;i<94;++i)r.citizen.labors.push_back(i);
  check(r,"");
  r.citizen.labors.push_back(94);check(r,"too many work detail labors");
  for(auto values:{std::vector<int16_t>{-1},std::vector<int16_t>{94},std::vector<int16_t>{0,0}}) {
    r.citizen.labors=values;check(r,"invalid work detail labor");
  }
  r.citizen.labors={};check(r,"");r.citizen.edit=3;check(r,"");
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.labors={1};check(r,"unexpected work detail labors");r.citizen.labors={};
  r.action=wm::ManagementAction::CitizenWorkScope;r.citizen.edit=0;r.citizen.detailIndex=-1;
  check(r,"invalid citizen work scope");r.citizen.unitId=0;
  for(int value:{0,1}) {r.citizen.onlyAssigned=value;check(r,"");}
  for(int value:{-1,2}) {r.citizen.onlyAssigned=value;check(r,"invalid citizen work scope");}
  r={};r.action=wm::ManagementAction::WorkDetailList;check(r,"");r.citizen.cursor=1;
  check(r,"work detail list revision required");r.citizen.expectedListRevision=INT64_MAX;check(r,"");
  r.citizen.expectedListRevision=uint64_t(INT64_MAX)+1;check(r,"invalid work detail list revision");
  r.citizen.expectedListRevision=1;r.action=wm::ManagementAction::CitizenList;check(r,"unexpected work detail list revision");
}

TEST_CASE("citizen codec preserves every appended state field and defaults") {
  for(bool populated:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto skill=b.CreateString(populated?"Legendary Miner":"");
    auto error=b.CreateString(populated?"Row exceeds name cap":"");
    wire::TilePos origin(0,0,0);
    wire::CitizenInfoBuilder person(b);person.add_id(0);person.add_origin(&origin);
    if(populated) {
      person.add_revision(INT64_MAX);person.add_detail_member(1);person.add_detail_skill(1);
      person.add_detail_skill_rating(15);person.add_detail_skill_name(skill);person.add_portrait_state(3);person.add_row_error(error);
    }
    auto u=person.Finish();
    wire::WorkDetailInfoBuilder detail(b);detail.add_index(0);
    if(populated){detail.add_icon(18);detail.add_row_error(error);}
    auto d=detail.Finish();auto people=b.CreateVector(std::vector{u});auto details=b.CreateVector(std::vector{d});
    auto recalc=b.CreateString(populated?"Native recalculation failed; labors may be stale":"");
    wire::CitizenStateBuilder state(b);state.add_citizens(people);state.add_details(details);
    if(populated){state.add_recalc_done(1);state.add_recalc_total(5000);state.add_recalc_error(recalc);state.add_detail_list_revision(INT64_MAX);}
    b.Finish(state.Finish());auto decoded=codec::decodeCitizen(flatbuffers::GetRoot<wire::CitizenState>(b.GetBufferPointer()));
    REQUIRE(decoded.citizens.size()==1);REQUIRE(decoded.details.size()==1);
    const auto& row=decoded.citizens[0];CHECK(row.revision==(populated?INT64_MAX:0));
    CHECK(row.detailMember==(populated?1:-1));CHECK(row.detailSkill==(populated?1:-1));
    CHECK(row.detailSkillRating==(populated?15:-1));CHECK(row.detailSkillName==(populated?"Legendary Miner":""));
    CHECK(row.portraitState==(populated?3:0));CHECK(row.rowError==(populated?"Row exceeds name cap":""));
    CHECK(decoded.details[0].icon==(populated?18:-2));CHECK(decoded.details[0].rowError==row.rowError);
    CHECK(decoded.recalcDone==(populated?1:0));CHECK(decoded.recalcTotal==(populated?5000:0));
    CHECK(decoded.detailListRevision==(populated?INT64_MAX:0));CHECK(decoded.recalcError==(populated?"Native recalculation failed; labors may be stale":""));
  }
}

TEST_CASE("management encoding isolates domain payloads while preserving envelope identity") {
  wm::ManagementRequest request;
  request.area.id = 0;
  request.area.ownerId = -2;
  request.workOrder.id = 37;
  request.workOrder.expectedRevision = (uint64_t(1) << 54) + 1;
  request.workOrder.query = "steel";
  for (auto action : {wm::ManagementAction::Catalog, wm::ManagementAction::AreaInspect,
                      wm::ManagementAction::WorkOrderInspect}) {
    request.action = action;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder, request, 123, (uint64_t(1) << 55) + 7, 456);
    flatbuffers::Verifier verifier(builder.GetBufferPointer(), builder.GetSize());
    REQUIRE(verifier.VerifyBuffer<wire::ConstructionRequest>(nullptr));
    const auto* encoded =
        flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->client_id() == 123);
    CHECK(encoded->seq() == (uint64_t(1) << 55) + 7);
    CHECK(encoded->world_epoch() == 456);
    CHECK(bool(encoded->area()) == (action == wm::ManagementAction::AreaInspect));
    CHECK(bool(encoded->work_order()) == (action == wm::ManagementAction::WorkOrderInspect));
    CHECK_FALSE(encoded->production());
    CHECK_FALSE(encoded->citizen());
    if (encoded->area()) {
      CHECK(encoded->area()->id() == 0);
      CHECK(encoded->area()->owner_id() == -2);
      CHECK(encoded->area()->active() == -1);
    }
    if (encoded->work_order()) {
      CHECK(encoded->work_order()->expected_revision() == request.workOrder.expectedRevision);
      CHECK(encoded->work_order()->query()->str() == "steel");
      CHECK(encoded->work_order()->remaining() == -1);
    }
  }
}

TEST_CASE("management domain decoding owns nested data independently of the wire buffer") {
  flatbuffers::FlatBufferBuilder builder;
  auto fact = wire::CreateCreatureFact(builder, builder.CreateString("age"),
                                       builder.CreateString("Twenty years"), 20, true);
  auto record = wire::CreateCreatureRecord(builder, 17, -1, builder.CreateString("Identity"),
                                           builder.CreateVector(std::vector{fact}));
  auto section = wire::CreateCreatureSection(builder, wire::CreatureSectionKind::Identity, true,
                                             false, {}, builder.CreateVector(std::vector{record}));
  const auto sections = builder.CreateVector(std::vector{section});
  const auto name = builder.CreateString("Cerol");
  wire::CreatureStateBuilder creature(builder);
  creature.add_unit_id(42);
  creature.add_name(name);
  creature.add_sections(sections);
  builder.Finish(creature.Finish());
  auto decoded =
      codec::decodeCreature(flatbuffers::GetRoot<wire::CreatureState>(builder.GetBufferPointer()));
  // The collector reuses this storage as soon as decode returns.
  std::fill_n(builder.GetBufferPointer(), builder.GetSize(), uint8_t(0));
  CHECK(decoded.unitId == 42);
  CHECK(decoded.name == "Cerol");
  CHECK(decoded.species.empty());
  REQUIRE(decoded.sections.size() == 1);
  REQUIRE(decoded.sections[0].records.size() == 1);
  const auto& row = decoded.sections[0].records[0];
  CHECK(row.relatedId == -1);
  REQUIRE(row.facts.size() == 1);
  CHECK(row.facts[0].text == "Twenty years");
  CHECK(row.facts[0].hasNumber);
  CHECK(row.facts[0].number == 20);
  decoded = codec::decodeCreature(nullptr);
  CHECK(decoded.unitId == -1);
  CHECK(decoded.sections.empty());
}

namespace {
namespace mm = df3d::mirror;
struct EncodedRequest {
  flatbuffers::FlatBufferBuilder b;
  bool invalid(const wm::ManagementRequest& r) {
    b.Clear();
    codec::encodeRequest(b, r, 1, 1, 7);
    return mm::validateConstructionRequest(*get()).has_value();
  }
  const mm::ConstructionRequest* get() const {
    return flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer());
  }
};
}
TEST_CASE("trade exchange wire guards native receipts and whole-good selections") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::TradeExchangeSelect;r.trade.depotId=17;r.trade.itemId=55;r.trade.side=1;r.trade.selected=1;
  CHECK(encoded.invalid(r));
  r.trade.receipt=123;REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->trade());CHECK(q->trade()->receipt()==123);CHECK(q->trade()->item_id()==55);CHECK(q->trade()->side()==1);CHECK(q->trade()->selected()==1);
  r.action=wm::ManagementAction::TradeExchangeSubmit;CHECK(encoded.invalid(r));
  r.trade.itemId=-1;r.trade.selected=-1;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==123);
  r.action=wm::ManagementAction::TradeExchangeClose;r.trade.receipt=0;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==0);
}
TEST_CASE("Stocks requests keep membership receipts separate from trade") {
  EncodedRequest encoded;
  wm::ManagementRequest r; r.action=wm::ManagementAction::StocksList; r.stocks.category=39;
  CHECK(encoded.invalid(r));
  r.stocks.receipt=12; r.stocks.cursor=512; r.stocks.query="iron";
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get();
  REQUIRE(q->stocks()); CHECK(q->trade()==nullptr); CHECK(q->stocks()->receipt()==12);
  CHECK(q->stocks()->category()==39); CHECK(q->stocks()->cursor()==512); CHECK(q->stocks()->query()->str()=="iron");
  r.action=wm::ManagementAction::StocksInspect; CHECK(encoded.invalid(r));
  r.stocks.itemId=0; REQUIRE_FALSE(encoded.invalid(r)); CHECK(encoded.get()->stocks()->item_id()==0);
}
TEST_CASE("Appointments require role identity and consumed-context receipts") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::AppointmentsAssign;r.appointments.unitId=5173;
  CHECK(encoded.invalid(r));
  r.appointments.entityId=483;r.appointments.positionId=10;r.appointments.assignmentId=6;r.appointments.receipt=25;
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get(); REQUIRE(q->appointments()); CHECK(q->stocks()==nullptr);CHECK(q->appointments()->receipt()==25);CHECK(q->appointments()->unit_id()==5173);CHECK(q->appointments()->assignment_id()==6);
  r.appointments.unitId=-1; REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->appointments()->unit_id()==-1);
}
TEST_CASE("Kitchen requests carry exact ingredient tuples and reject malformed edits") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::KitchenSetPermission;
  r.kitchen.itemType=1;r.kitchen.matType=419;r.kitchen.matIndex=20;r.kitchen.permission=2;r.kitchen.allowed=0;
  CHECK(encoded.invalid(r));r.kitchen.receipt=7;r.kitchen.query="berries";
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->kitchen());CHECK(q->appointments()==nullptr);
  CHECK(q->kitchen()->item_type()==1);CHECK(q->kitchen()->item_subtype()==-1);CHECK(q->kitchen()->mat_type()==419);CHECK(q->kitchen()->mat_index()==20);CHECK(q->kitchen()->permission()==2);CHECK(q->kitchen()->allowed()==0);CHECK(q->kitchen()->receipt()==7);CHECK(q->kitchen()->query()->str()=="berries");
  for(auto flag:{0,3}){r.kitchen.permission=uint8_t(flag);CHECK(encoded.invalid(r));}
  r.kitchen.permission=1;r.kitchen.allowed=-1;CHECK(encoded.invalid(r));
  r.kitchen.allowed=1;r.kitchen.matIndex=-2;CHECK(encoded.invalid(r));
  r.kitchen.matIndex=20;r.action=wm::ManagementAction::KitchenList;CHECK(encoded.invalid(r));
  r.kitchen={};r.kitchen.receipt=7;r.kitchen.cursor=4097;CHECK(encoded.invalid(r));
  r.kitchen.cursor=0;r.kitchen.query=std::string(129,'x');CHECK(encoded.invalid(r));
}
TEST_CASE("selection transport request payloads preserve ownership") {
  EncodedRequest encoded;
  wm::ManagementRequest request;request.action=wm::ManagementAction::Selection;
  request.selection.x=88;request.selection.y=71;request.selection.z=143;
  REQUIRE_FALSE(encoded.invalid(request));
  const auto* command=encoded.get();REQUIRE(command->selection());
  CHECK(command->selection()->tile()->x()==88);CHECK(command->selection()->tile()->z()==143);
  CHECK(command->selection()->receipt()==0);
  request.selection.receipt=77;REQUIRE_FALSE(encoded.invalid(request));
  CHECK(encoded.get()->selection()->receipt()==77); // replacement click carries ownership
}

TEST_CASE("empty work-order traits do not turn moves or details into another edit") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderUpdate;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.move=1;
  w.expectedNeighbor=1;w.expectedListRevision=1;w.traits.emplace();
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  w.traits->clear();w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  // Condition edits retain an explicit empty replacement, distinct from absence.
  w={};w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;w.traits.emplace();
  r.action=wm::ManagementAction::WorkOrderCondition;
  REQUIRE_FALSE(encoded.invalid(r));REQUIRE(encoded.get()->work_order()->traits());
  CHECK(encoded.get()->work_order()->traits()->size()==0);
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.query=std::string(64,'q');REQUIRE_FALSE(encoded.invalid(r));
  w.query.push_back('q');CHECK(encoded.invalid(r));
}

TEST_CASE("maximal producer order page fits the management channel") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<16;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    std::vector<flatbuffers::Offset<mm::WorkOrderInput>> inputs;
    for(int index=0;index<8;++index) {
      std::vector<std::string> traits;
      for(int t=0;t<16;++t)traits.push_back("rc:"+std::string(59,'x')+char('a'+t)+char('a'+index));
      conditions.push_back(mm::CreateWorkOrderCondition(b,0,index,b.CreateString(std::string(256,'c')),
        true,0,1,-1,-1,-1,false,-1,-1,-1,b.CreateVectorOfStrings(traits),1,true,-1));
      // The producer currently emits empty input descriptions.
      inputs.push_back(mm::CreateWorkOrderInput(b,index,b.CreateString(""),-1,-1,true));
    }
    std::vector<int32_t> jobs;for(int j=0;j<128;++j)jobs.push_back(id*128+j);
    auto name=b.CreateString(std::string(512,'n')),reason=b.CreateString(std::string(1024,'r'));
    auto cs=b.CreateVector(conditions);auto ins=b.CreateVector(inputs);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_name(name);o.add_reason(reason);
    o.add_total(10);o.add_remaining(10);o.add_conditions(cs);o.add_inputs(ins);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  auto os=b.CreateVector(orders);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_list_revision(INT64_MAX);auto ws=w.Finish();
  auto citizen=mm::CreateCitizenState(b,
    b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenInfo>>{}),
    b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkDetailInfo>>{}));
  mm::ManagementStateBuilder s(b);s.add_schema_version(mm::kManagementVersion);s.add_revision(1);
  s.add_action(mm::ManagementAction::WorkOrderList);s.add_status(mm::ManagementStatus::Ok);s.add_work_order(ws);s.add_citizen(citizen);
  b.Finish(s.Finish());
  CHECK(b.GetSize()<mm::kManagementCapacity);
  CHECK_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
}

TEST_CASE("non-citizen replies reject populated citizen tables") {
  for(bool detail : {false,true}) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<mm::CitizenInfo>> people;
    std::vector<flatbuffers::Offset<mm::WorkDetailInfo>> details;
    if(detail) details.push_back(mm::CreateWorkDetailInfo(b));
    else people.push_back(mm::CreateCitizenInfo(b));
    auto citizens=mm::CreateCitizenState(b,b.CreateVector(people),b.CreateVector(details));
    mm::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(mm::ManagementAction::WorkOrderList);state.add_citizen(citizens);
    b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="unexpected citizen state");
  }
}

TEST_CASE("work-order request fields and exclusive intents survive encoding") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderCondition;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;
  w.itemSubtype=2;w.matType=419;w.matIndex=7;w.traits=std::vector<std::string>{"f1:0","rc:X"};
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get()->work_order();
  CHECK(q->item_subtype()==2);CHECK(q->mat_type()==419);CHECK(q->mat_index()==7);
  REQUIRE(q->traits());CHECK(q->traits()->Get(1)->str()=="rc:X");
  w.traits=std::vector<std::string>(256,std::string(64,'t'));CHECK_FALSE(encoded.invalid(r));
  w.traits->push_back("x");CHECK(encoded.invalid(r));w.traits->pop_back();
  w.traits->front().push_back('x');CHECK(encoded.invalid(r));
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.groupType=0;w.groupSubtype=2;w.groupCustom=3;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->group_type()==0);CHECK(q->group_subtype()==2);CHECK(q->group_custom()==3);
  CHECK(q->expected_list_revision()==INT64_MAX);
  w={};r.action=wm::ManagementAction::WorkOrderUpdate;w.id=0;w.expectedRevision=1;
  w.move=1;w.expectedNeighbor=2;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->move()==1);CHECK(q->expected_neighbor()==2);CHECK(q->expected_list_revision()==INT64_MAX);
  w.move=-1;CHECK_FALSE(encoded.invalid(r));w.move=2;CHECK(encoded.invalid(r));
  w.move=-2;CHECK(encoded.invalid(r));w.move=1;
  const auto move=r;
  for(int missing=0;missing<5;++missing) {
    r=move;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=-1;
    if(missing==4)w.expectedListRevision=0;
    CHECK(encoded.invalid(r));
  }
  r=move;w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;w.encrustFlags=1092;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->input_index()==0);CHECK(q->mat_type()==0);CHECK(q->mat_index()==0);CHECK(q->encrust_flags()==1092);
  const auto input=r;
  for(int missing=0;missing<7;++missing) {
    r=input;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=0;
    if(missing==4)w.expectedListRevision=1;
    if(missing==5)w.move=1;
    if(missing==6){w.matType=-1;w.matIndex=-1;w.encrustFlags=-1;}
    CHECK(encoded.invalid(r));
  }
  // New scalar identities retain -1 and zero, and refuse values below -1.
  for(int field=0;field<9;++field) for(int value:{-1,0,-2}) {
    r={};r.action=wm::ManagementAction::WorkOrderCatalog;
    switch(field) {
      case 0:w.expectedNeighbor=value;break;case 1:w.itemSubtype=value;break;
      case 2:w.matType=value;break;case 3:w.matIndex=value;break;
      case 4:w.groupType=value;break;case 5:w.groupSubtype=value;break;
      case 6:w.groupCustom=value;break;case 7:w.encrustFlags=value;break;
      case 8:w.inputIndex=value;if(value==0)r=input;break;
    }
    CHECK(encoded.invalid(r)==(value==-2));
  }
  r=move;w.expectedListRevision=-1;CHECK(encoded.invalid(r));
  // Every unrelated field must leave its default only in a separate intent.
  for(const auto& base:{move,input}) for(int field=0;field<25;++field) {
    r=base;
    switch(field) {
      case 0:w.remaining=0;break;case 1:w.frequency=0;break;
      case 2:w.workshopId=-1;break;case 3:w.maxWorkshops=0;break;
      case 4:w.recipe="x";break;case 5:w.query="x";break;case 6:w.cursor=1;break;
      case 7:w.conditionKind=1;break;case 8:w.conditionIndex=0;break;
      case 9:w.removeCondition=true;break;case 10:w.compare=0;break;
      case 11:w.threshold=0;break;case 12:w.itemType=0;break;
      case 13:w.targetOrder=1;break;case 14:w.dependency=0;break;
      case 15:w.candidateKind=1;break;case 16:w.itemSubtype=0;break;
      case 17:w.traits=std::vector<std::string>{"f1:0"};break;
      case 18:w.groupType=0;break;case 19:w.groupSubtype=0;break;case 20:w.groupCustom=0;break;
      case 21:if(base.workOrder.move)w.inputIndex=0;else w.inputIndex=-1;break;
      case 22:if(base.workOrder.move)w.matType=0;else w.move=1;break;
      case 23:if(base.workOrder.move)w.matIndex=0;else w.expectedNeighbor=0;break;
      case 24:if(base.workOrder.move)w.encrustFlags=0;else w.expectedListRevision=1;break;
    }
    CAPTURE(field);CHECK(encoded.invalid(r));
  }
}

TEST_CASE("work-order response fields decode with owned strings and absent defaults") {
  for(bool present:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>{"f5:31","rp:X"});
    mm::WorkOrderConditionBuilder c(b);
    if(present){c.add_item_subtype(3);c.add_mat_type(419);c.add_mat_index(7);c.add_traits(ts);
      c.add_satisfaction(2);c.add_estimated(true);c.add_estimate_count(42);}
    auto cs=b.CreateVector(std::vector{c.Finish()});
    auto in=mm::CreateWorkOrderInput(b,2,b.CreateString("input"),0,5,true);
    auto ins=b.CreateVector(std::vector{in});
    mm::WorkOrderInfoBuilder o(b);o.add_id(0);o.add_revision(1);o.add_conditions(cs);
    if(present){o.add_position(12);o.add_detail_kind(6);o.add_size_raw(17);o.add_encrust_flags(1092);
      o.add_mat_type(19);o.add_mat_index(8);o.add_material_category(4096);o.add_inputs(ins);}
    auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b,0,4,b.CreateString("material"));
    auto mats=b.CreateVector(std::vector{mat});
    auto trait=mm::CreateWorkOrderTrait(b,b.CreateString("rc:X"),b.CreateString("trait"));
    auto traits=b.CreateVector(std::vector{trait});
    auto type=mm::CreateWorkOrderItemType(b,3,2,b.CreateString("type"));
    auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b,0,2,7,b.CreateString("group"),9);
    auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b,b.CreateString("key"),b.CreateString("task"),11,b.CreateString("reaction"),3,2,419,7);
    auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder state(b);state.add_orders(os);
    if(present){state.add_materials(mats);state.add_traits(traits);state.add_types(types);state.add_groups(groups);state.add_tasks(tasks);
      state.add_total(128);state.add_list_revision(INT64_MAX);state.add_build_phase(3);state.add_build_done(17);state.add_build_total(128);}
    b.Finish(state.Finish());auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<mm::WorkOrderState>(b.GetBufferPointer()));
    std::fill_n(b.GetBufferPointer(),b.GetSize(),uint8_t(0));
    REQUIRE(decoded.orders.size()==1);const auto& order=decoded.orders[0];REQUIRE(order.conditions.size()==1);const auto& cond=order.conditions[0];
    CHECK(order.position==(present?12:-1));CHECK(order.detailKind==(present?6:0));CHECK(order.sizeRaw==(present?17:-1));
    CHECK(order.encrustFlags==(present?1092:0));CHECK(order.matType==(present?19:-1));CHECK(order.matIndex==(present?8:-1));CHECK(order.materialCategory==(present?4096:0));
    CHECK(cond.itemSubtype==(present?3:-1));CHECK(cond.matType==(present?419:-1));CHECK(cond.matIndex==(present?7:-1));
    CHECK(cond.satisfaction==(present?2:0));CHECK(cond.estimated==present);CHECK(cond.estimateCount==(present?42:-1));
    CHECK(decoded.total==(present?128:0));CHECK(decoded.listRevision==(present?INT64_MAX:0));
    CHECK(decoded.buildPhase==(present?3:0));CHECK(decoded.buildDone==(present?17:0));CHECK(decoded.buildTotal==(present?128:0));
    if(present) {
      CHECK(cond.traits==std::vector<std::string>{"f5:31","rp:X"});
      REQUIRE(order.inputs.size()==1);const auto& i=order.inputs[0];CHECK(i.index==2);CHECK(i.description=="input");CHECK(i.matType==0);CHECK(i.matIndex==5);CHECK(i.editable);
      REQUIRE(decoded.materials.size()==1);CHECK(decoded.materials[0].matType==0);CHECK(decoded.materials[0].matIndex==4);CHECK(decoded.materials[0].name=="material");
      REQUIRE(decoded.traits.size()==1);CHECK(decoded.traits[0].key=="rc:X");CHECK(decoded.traits[0].name=="trait");
      REQUIRE(decoded.types.size()==1);CHECK(decoded.types[0].itemType==3);CHECK(decoded.types[0].itemSubtype==2);CHECK(decoded.types[0].name=="type");
      REQUIRE(decoded.groups.size()==1);const auto& g=decoded.groups[0];CHECK(g.type==0);CHECK(g.subtype==2);CHECK(g.custom==7);CHECK(g.name=="group");CHECK(g.count==9);
      REQUIRE(decoded.tasks.size()==1);const auto& t=decoded.tasks[0];CHECK(t.key=="key");CHECK(t.name=="task");CHECK(t.jobType==11);CHECK(t.reaction=="reaction");CHECK(t.itemType==3);CHECK(t.itemSubtype==2);CHECK(t.matType==419);CHECK(t.matIndex==7);
    } else {
      CHECK(cond.traits.empty());CHECK(order.inputs.empty());CHECK(decoded.materials.empty());CHECK(decoded.traits.empty());CHECK(decoded.types.empty());CHECK(decoded.groups.empty());CHECK(decoded.tasks.empty());
    }
  }
}

namespace {
// One boundary changes per case; the valid baseline saturates every page cap.
struct WorkOrderPageBounds {
  int orders=16,conditions=128,traits=2048,jobs=2048,rows=128,keyBytes=64,nameBytes=128;
  int detailKind=6,satisfaction=2,phase=3,done=128,total=128;
  uint64_t revision=INT64_MAX;
  int list=-1; // -1: all catalogs; otherwise select one catalog for its boundary.
};
void workOrderPage(flatbuffers::FlatBufferBuilder& b,const WorkOrderPageBounds& n) {
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<n.orders;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    const int count=n.conditions/n.orders+(id<n.conditions%n.orders);
    for(int index=0;index<count;++index) {
      const int ordinal=id*(n.conditions/n.orders)+std::min(id,n.conditions%n.orders)+index;
      const int traitCount=n.traits/n.conditions+(ordinal<n.traits%n.conditions);
      auto traits=b.CreateVectorOfStrings(std::vector<std::string>(traitCount,std::string(n.keyBytes,'t')));
      mm::WorkOrderConditionBuilder c(b);c.add_index(index);c.add_traits(traits);c.add_satisfaction(n.satisfaction);
      conditions.push_back(c.Finish());
    }
    std::vector<int32_t> jobs;
    for(int j=0;j<n.jobs/n.orders+(id<n.jobs%n.orders);++j)jobs.push_back(id*1024+j);
    auto cs=b.CreateVector(conditions);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_detail_kind(n.detailKind);o.add_conditions(cs);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  std::vector<flatbuffers::Offset<mm::WorkOrderMaterial>> mats;
  std::vector<flatbuffers::Offset<mm::WorkOrderTrait>> traits;
  std::vector<flatbuffers::Offset<mm::WorkOrderItemType>> types;
  std::vector<flatbuffers::Offset<mm::WorkOrderGroup>> groups;
  std::vector<flatbuffers::Offset<mm::WorkOrderTask>> tasks;
  for(int i=0;i<n.rows;++i) {
    if(n.list<0 || n.list==0)mats.push_back(mm::CreateWorkOrderMaterial(b,0,i,b.CreateString(std::string(n.nameBytes,'m'))));
    if(n.list<0 || n.list==1)traits.push_back(mm::CreateWorkOrderTrait(b,b.CreateString(std::string(n.keyBytes,'t')),b.CreateString(std::string(n.nameBytes,'t'))));
    if(n.list<0 || n.list==2)types.push_back(mm::CreateWorkOrderItemType(b,0,i,b.CreateString(std::string(n.nameBytes,'y'))));
    if(n.list<0 || n.list==3)groups.push_back(mm::CreateWorkOrderGroup(b,0,0,i,b.CreateString(std::string(n.nameBytes,'g')),1));
    if(n.list<0 || n.list==4)tasks.push_back(mm::CreateWorkOrderTask(b,b.CreateString(std::string(n.keyBytes,'k')),b.CreateString(std::string(n.nameBytes,'n')),0,b.CreateString(std::string(64,'r')),0,0,0,i));
  }
  auto os=b.CreateVector(orders);auto ms=b.CreateVector(mats);auto ts=b.CreateVector(traits);auto ys=b.CreateVector(types);auto gs=b.CreateVector(groups);auto ks=b.CreateVector(tasks);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(ms);w.add_traits(ts);w.add_types(ys);w.add_groups(gs);w.add_tasks(ks);
  w.add_list_revision(n.revision);w.add_build_phase(n.phase);w.add_build_done(n.done);w.add_build_total(n.total);auto ws=w.Finish();
  mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
}
}
TEST_CASE("maximal management page and individual state validator boundaries") {
  auto valid=[](const WorkOrderPageBounds& n) {
    flatbuffers::FlatBufferBuilder b;workOrderPage(b,n);
    flatbuffers::Verifier v(b.GetBufferPointer(),b.GetSize());REQUIRE(v.VerifyBuffer<mm::ManagementState>(nullptr));
    CHECK(b.GetSize()<mm::kManagementCapacity);
    return !mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value();
  };
  CHECK(valid({}));
  for(int boundary=0;boundary<10;++boundary) {
    WorkOrderPageBounds n;CAPTURE(boundary);
    switch(boundary) {
      case 0:n.orders=17;break;case 1:n.conditions=129;break;case 2:n.traits=2049;break;
      case 3:n.jobs=2049;break;case 4:n.detailKind=7;break;case 5:n.satisfaction=3;break;
      case 6:n.phase=4;break;case 7:n.done=129;break;case 8:n.revision=uint64_t(INT64_MAX)+1;break;
      case 9:n.keyBytes=65;n.rows=0;break;
    }
    CHECK_FALSE(valid(n));
  }
  for(int list=0;list<5;++list) {
    WorkOrderPageBounds n;n.list=list;CHECK(valid(n));n.rows=129;CHECK_FALSE(valid(n));
    n.rows=128;n.nameBytes=129;CHECK_FALSE(valid(n));
    if(list==1 || list==4){n.nameBytes=128;n.traits=0;n.keyBytes=65;CHECK_FALSE(valid(n));}
  }
}

TEST_CASE("work-order default catalog identities and per-condition trait boundaries") {
  for(int size:{256,257}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>(size,"f1:0"));
    mm::WorkOrderConditionBuilder c(b);c.add_traits(ts);auto cs=b.CreateVector(std::vector{c.Finish()});
    mm::WorkOrderInfoBuilder o(b);o.add_revision(1);o.add_conditions(cs);auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b);auto mats=b.CreateVector(std::vector{mat});
    auto type=mm::CreateWorkOrderItemType(b);auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b);auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b);auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(mats);w.add_types(types);w.add_groups(groups);w.add_tasks(tasks);auto ws=w.Finish();
    mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
    const auto* wire=flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer());
    CHECK(mm::validateManagementState(*wire).has_value()==(size==257));
    const auto decoded=codec::decodeWorkOrder(wire->work_order());
    CHECK(decoded.materials[0].matType==-1);CHECK(decoded.materials[0].matIndex==-1);
    CHECK(decoded.types[0].itemType==-1);CHECK(decoded.types[0].itemSubtype==-1);
    CHECK(decoded.groups[0].type==-1);CHECK(decoded.groups[0].subtype==-1);CHECK(decoded.groups[0].custom==-1);CHECK(decoded.groups[0].count==0);
    const auto& t=decoded.tasks[0];CHECK(t.jobType==-1);CHECK(t.itemType==-1);CHECK(t.itemSubtype==-1);CHECK(t.matType==-1);CHECK(t.matIndex==-1);
  }
}

TEST_CASE("exact construction item identities survive encoding without aggregate fallback") {
  wm::ManagementRequest r;r.action=wm::ManagementAction::Place;r.definition="Chair";
  r.selections={{0,0,-1,0,1,2,42}};
  auto validate=[&]() {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    const auto* ids=q->selections()->Get(0)->item_ids();
    CHECK(bool(ids)==r.selections[0].itemIds.has_value());
    if(ids) { CHECK(ids->size()==r.selections[0].itemIds->size());
      for(size_t i=0;i<ids->size();++i)CHECK(ids->Get(i)==(*r.selections[0].itemIds)[i]); }
    return wire::validateConstructionRequest(*q);
  };
  CHECK_FALSE(validate()); // Aggregate absence is preserved.
  r.selections[0].itemIds=std::vector<int32_t>{3225,3226};CHECK_FALSE(validate());
  r.selections[0].itemIds=std::vector<int32_t>{3226,3225};CHECK_FALSE(validate()); // User order preserved.
  r.selections[0].itemIds=std::vector<int32_t>{};CHECK(validate());
  r.selections[0].itemIds=std::vector<int32_t>{3225};CHECK(validate());
  r.selections[0].count=1;CHECK_FALSE(validate());
  for(int64_t rev:{int64_t(-1),int64_t(0)}){r.selections[0].expectedListRevision=rev;CHECK(validate());}
  r.selections[0].expectedListRevision=42;
  r.selections[0].itemIds=std::vector<int32_t>{-1};CHECK(validate());
  r.selections[0].count=2;r.selections[0].itemIds=std::vector<int32_t>{3225,3225};CHECK(validate());
  r.selections[0].count=1;r.selections[0].itemIds=std::vector<int32_t>{3225};
  r.selections.push_back({1,0,-1,0,1,1,42,std::vector<int32_t>{3225}});CHECK(validate());
  r.selections.back().itemIds=std::vector<int32_t>{3226};CHECK_FALSE(validate());
  r.selections.resize(1);r.selections[0].count=16384;r.selections[0].itemIds->resize(16384);
  for(int i=0;i<16384;++i)(*r.selections[0].itemIds)[i]=i;
  CHECK_FALSE(validate());
  r.selections[0].itemIds->push_back(16384);++r.selections[0].count;CHECK(validate());
}

TEST_CASE("construction selection revisions are optional signed int64 values per entry") {
  wm::ManagementRequest request;
  request.action=wm::ManagementAction::Place;request.definition="Chair";
  request.selections={{0,-1,-1,-1,-1,1},{1,-1,-1,-1,-1,1,42}};
  for (int64_t revision : {int64_t(-2),int64_t(-1),int64_t(0),int64_t(1),int64_t(INT64_MAX)}) {
    request.selections[0].expectedListRevision=revision;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder,request,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->expected_list_revision()==0);
    CHECK(encoded->selections()->Get(0)->expected_list_revision()==revision);
    CHECK(encoded->selections()->Get(1)->expected_list_revision()==42);
    auto error=wire::validateConstructionRequest(*encoded);
    if(revision < -1) { REQUIRE(error);CHECK(*error=="invalid construction selection list revision"); }
    else CHECK_FALSE(error);
  }
  // The appended field is absent in an older selection buffer.
  flatbuffers::FlatBufferBuilder builder;
  builder.Finish(wire::CreateConstructionSelection(builder,0,-1,-1,-1,-1,1));
  CHECK(flatbuffers::GetRoot<wire::ConstructionSelection>(builder.GetBufferPointer())->expected_list_revision()==-1);
  request.selections.clear();
  builder.Clear();codec::encodeRequest(builder,request,1,2,3);
  CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer())));
}

TEST_CASE("construction native decisions survive request codecs and validation") {
  auto error=[](const wm::ManagementRequest& r) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* v=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(v->direction()==r.direction);CHECK(v->depth()==r.depth);
    CHECK(v->origin()->x()==r.x);CHECK(v->origin()->y()==r.y);CHECK(v->origin()->z()==r.z);
    if(!r.selections.empty())CHECK(v->selections()->Get(0)->count()==r.selections[0].count);
    return wire::validateConstructionRequest(*v);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  REQUIRE(error(r));CHECK(*error(r)=="Must span multiple elevations");
  r.depth=2;CHECK_FALSE(error(r));r.depth=1;r.definition="SiegeEngine:Ballista";
  for(uint8_t d=0;d<8;++d){r.direction=d;CHECK_FALSE(error(r));}
  r.direction=8;REQUIRE(error(r));CHECK(*error(r)=="invalid dimensions or orientation");r.direction=0;
  r.action=wm::ManagementAction::Place;
  for(const char* key:{"Weapon","Trap:WeaponTrap"}) {
    r.definition=key;r.selections={{int16_t(r.definition=="Weapon" ? 0 : 1)}};
    CHECK(r.selections[0].count==1);CHECK_FALSE(error(r));
    r.selections[0].count=10;CHECK_FALSE(error(r));
    r.selections[0].count=11;REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
    r.selections[0].count=0;REQUIRE(error(r));CHECK(*error(r)=="invalid or duplicate construction selection");
    r.selections.clear();REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
  }
  r.action=wm::ManagementAction::ConstructionMaterials;r.definition="Chair";r.filter=0;
  r.x=10;r.y=20;r.z=3;CHECK_FALSE(error(r));
}

TEST_CASE("construction codec preserves eight facings and per-tile totals") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
  for(uint8_t d=0;d<8;++d)footprints.push_back(wire::CreateConstructionFootprint(b,d,1,1,0,0));
  const auto fps=b.CreateVector(footprints);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder def(b);def.add_key(key);def.add_width(1);def.add_height(1);
  def.add_orientations(255);def.add_footprints(fps);const auto definition=def.Finish();
  const auto catalog=b.CreateVector(std::vector{definition});
  const auto filter=wire::CreateConstructionFilter(b,0,-1,-1,0,0,1024);
  const auto filters=b.CreateVector(std::vector{filter});
  wire::ConstructionStateBuilder c(b);c.add_filters(filters);c.add_placed(1024);const auto construction=c.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);
  state.add_required(1024);state.add_construction(construction);b.Finish(state.Finish());
  const auto* encoded=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*encoded));
  wm::ManagementState decoded;codec::decodeConstruction(encoded,decoded);
  REQUIRE(decoded.catalog.size()==1);CHECK(decoded.catalog[0].orientations==255);
  REQUIRE(decoded.catalog[0].footprints.size()==8);CHECK(decoded.catalog[0].footprints[7].direction==7);
  CHECK(decoded.required==1024);CHECK(decoded.construction.placed==1024);
  CHECK(decoded.construction.filters[0].quantity==1024);
}

TEST_CASE("material lists require a placement origin and eight footprints is the limit") {
  for(int missing=0;missing<3;++missing) {
    flatbuffers::FlatBufferBuilder b;
    const auto key=b.CreateString(missing==0 ? "" : "Chair");const wire::TilePos origin(0,0,0);
    wire::ConstructionRequestBuilder request(b);request.add_client_id(1);request.add_seq(1);request.add_world_epoch(1);
    request.add_action(wire::ManagementAction::ConstructionMaterials);request.add_definition(key);
    request.add_filter(missing==1 ? -1 : 0);if(missing!=2)request.add_origin(&origin);b.Finish(request.Finish());
    const auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="definition, filter and origin required");
  }
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> rows;
  for(uint8_t d=0;d<9;++d)rows.push_back(wire::CreateConstructionFootprint(b,d%8,1,1,0,0));
  const auto fps=b.CreateVector(rows);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder definition(b);definition.add_key(key);definition.add_width(1);definition.add_height(1);
  definition.add_footprints(fps);const auto def=definition.Finish();const auto catalog=b.CreateVector(std::vector{def});
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);b.Finish(state.Finish());
  const auto error=wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()));
  REQUIRE(error);CHECK(*error=="too many construction footprints");
}


// These maximal wire fixtures exercise schema bounds, not recorded native labels.
// Producer fields: construction.lua definitions/filter_row/materials/placement.
namespace {
struct ConstructionWire {
  flatbuffers::FlatBufferBuilder b;
  const wire::ManagementState* state=nullptr;
  ConstructionWire(const std::string& field="", int64_t n=0, int page=0) {
    auto value=[&](const char* key,int64_t normal){return field==key?n:normal;};
    auto text=[&](const char* key,size_t normal){return b.CreateString(std::string(size_t(value(key,normal)),'x'));};
    std::vector<flatbuffers::Offset<wire::ConstructionFilter>> filters;
    for(int i=0;i<value("filters",8);++i)
      filters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",i)),
        int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
        text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
    auto fs=b.CreateVector(filters);
    std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
    for(int i=0;i<value("footprints",5);++i)
      footprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",i)),
        uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
        int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));

    std::vector<flatbuffers::Offset<wire::BuildingDefinition>> catalog;
    if(page==0)for(int i=0;i<value("catalog",128);++i) {
      std::string key=std::to_string(i);key.resize(size_t(value("key",64)),'k');
      const auto k=b.CreateString(key),name=text("name",128),reason=text("reason",128),native=text("native_name",128),
        family=text("family",64),subtype=text("subtype_key",64),custom=text("custom_code",64);
      // No shared child vectors: model the producer's independently encoded rows.
      std::vector<flatbuffers::Offset<wire::ConstructionFilter>> ownFilters;
      for(int f=0;f<value("filters",8);++f)
        ownFilters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",f)),
          int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
          text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
      const auto ownFs=b.CreateVector(ownFilters);
      std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> ownFootprints;
      for(int f=0;f<value("footprints",5);++f)
        ownFootprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",f)),
          uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
          int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));
      const auto ownFps=b.CreateVector(ownFootprints);
      wire::BuildingDefinitionBuilder d(b);d.add_key(k);d.add_name(name);d.add_reason(reason);
      d.add_native_name(native);d.add_family(family);d.add_subtype_key(subtype);d.add_custom_code(custom);
      d.add_width(uint16_t(value("width",31)));d.add_height(uint16_t(value("height",31)));
      d.add_area_mode(uint8_t(value("area_mode",4)));d.add_orientations(31);
      d.add_max_width(uint16_t(value("max_width",31)));d.add_max_height(uint16_t(value("max_height",31)));
      d.add_max_depth(uint16_t(value("max_depth",256)));d.add_filters(ownFs);d.add_footprints(ownFps);
      catalog.push_back(d.Finish());
    }
    const auto cats=b.CreateVector(catalog);
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> materials;
    if(page==1)for(int i=0;i<value("materials",field=="mat_index"?1:128);++i)
      materials.push_back(wire::CreateConstructionMaterial(b,int16_t(value("item_type",-1)),
        int16_t(value("item_subtype",-1)),int16_t(value("mat_type",-1)),int32_t(value("mat_index",i)),
        text("material_name",128),text("material_caption",64),uint32_t(value("count",1))));
    auto mats=b.CreateVector(materials);
    auto mask=b.CreateVector(std::vector<uint8_t>(size_t(value("mask_size",page==2?1024:0)),uint8_t(value("mask",1))));
    auto pieces=b.CreateVector(std::vector<uint8_t>(size_t(value("pieces_size",page==2?1024:0)),uint8_t(value("piece",3))));
    auto key=text("building_key",64);
    std::vector<flatbuffers::Offset<wire::PressureCreatureExample>> examples;
    if(page==0)for(int i=0;i<value("pressure_count",200);++i)
      examples.push_back(wire::CreatePressureCreatureExample(b,int32_t(value("pressure_size",(i+1)*1000)),
          int32_t(value("pressure_race",i)),text("pressure_name",128)));
    auto pressureExamples=b.CreateVector(examples);
    wire::ConstructionStateBuilder c(b);c.add_building_key(key);c.add_filter(int16_t(value("filter",7)));
    c.add_pressure_creatures(pressureExamples);
    c.add_filters(fs);c.add_materials(mats);c.add_total(128);c.add_list_revision(uint64_t(value("list_revision",INT64_MAX)));
    c.add_estimated(true);c.add_build_phase(uint8_t(value("build_phase",2)));
    c.add_build_done(uint32_t(value("build_done",128)));c.add_build_total(128);
    c.add_placed(uint32_t(value("placed",1024)));c.add_skipped(uint32_t(value("skipped",0)));
    c.add_first_building(int32_t(value("first_building",-1)));c.add_valid_mask(mask);c.add_pieces(pieces);
    if(!footprints.empty())c.add_footprint(footprints[0]);
    const auto construction=c.Finish();
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_schema_version(uint32_t(value("version",wire::kManagementVersion)));
    s.add_catalog(cats);s.add_construction(construction);b.Finish(s.Finish());
    state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  }
  std::optional<std::string> error() const {return wire::validateManagementState(*state);}
};
}

TEST_CASE("construction maximal pages and complete owned field decoding") {
  for(int page=0;page<3;++page) {
    ConstructionWire fixture("",0,page);
    REQUIRE_FALSE(fixture.error());CHECK(fixture.b.GetSize()<wire::kManagementCapacity);
    std::cout<<"CONSTRUCTION_MAX_PAGE "<<page<<" "<<fixture.b.GetSize()<<" bytes\n";
    wm::ManagementState s;codec::decodeConstruction(fixture.state,s);
    const auto& c=s.construction;
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filter==7);CHECK(c.filters.size()==8);
    CHECK(c.total==128);CHECK(c.listRevision==INT64_MAX);CHECK(c.estimated);CHECK(c.buildPhase==2);
    CHECK(c.buildDone==128);CHECK(c.buildTotal==128);CHECK(c.placed==1024);CHECK(c.skipped==0);CHECK(c.firstBuilding==-1);
    REQUIRE(c.footprint);CHECK(c.footprint->direction==0);CHECK(c.footprint->width==31);CHECK(c.footprint->height==31);
    CHECK(c.footprint->centerX==30);CHECK(c.footprint->centerY==-1);
    for(int i=0;i<8;++i) {const auto& f=c.filters[i];CHECK(f.index==i);CHECK(f.itemType==-1);CHECK(f.itemSubtype==-1);
      CHECK(f.caption==std::string(64,'x'));CHECK(f.requirement==std::string(64,'x'));CHECK(f.quantity==-1);}
    if(page==0) {
      REQUIRE(c.pressureCreatures.size()==200);
      for(int i=0;i<200;++i){CHECK(c.pressureCreatures[i].size==(i+1)*1000);CHECK(c.pressureCreatures[i].raceId==i);CHECK(c.pressureCreatures[i].name==std::string(128,'x'));}
      REQUIRE(s.catalog.size()==128);const auto& d=s.catalog[0];CHECK(d.key.size()==64);CHECK(d.name.size()==128);
      CHECK(d.reason.size()==128);CHECK(d.nativeName.size()==128);CHECK(d.family.size()==64);
      CHECK(d.subtypeKey.size()==64);CHECK(d.customCode.size()==64);CHECK(d.areaMode==4);CHECK(d.orientations==31);
      CHECK(d.maxWidth==31);CHECK(d.maxHeight==31);CHECK(d.maxDepth==256);CHECK(d.filters.size()==8);CHECK(d.footprints.size()==5);
    } else if(page==1) {
      REQUIRE(c.materials.size()==128);for(int i=0;i<128;++i) {const auto& m=c.materials[i];
        CHECK(m.itemType==-1);CHECK(m.itemSubtype==-1);CHECK(m.matType==-1);CHECK(m.matIndex==i);
        CHECK(m.name.size()==128);CHECK(m.caption.size()==64);CHECK(m.count==1);}
    } else {CHECK(c.validMask==std::vector<uint8_t>(1024,1));CHECK(c.pieces==std::vector<uint8_t>(1024,3));}
    std::fill_n(fixture.b.GetBufferPointer(),fixture.b.GetSize(),uint8_t(0));
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filters[0].requirement==std::string(64,'x'));
    if(page==0)CHECK(c.pressureCreatures[199].name==std::string(128,'x'));
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateManagementState(b));
  wm::ManagementState defaults;codec::decodeConstruction(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()),defaults);
  CHECK(defaults.construction.filter==-1);CHECK(defaults.construction.firstBuilding==-1);CHECK(defaults.construction.listRevision==0);
  CHECK(defaults.construction.filters.empty());CHECK(defaults.construction.materials.empty());CHECK_FALSE(defaults.construction.footprint);
}

TEST_CASE("construction state rejects each over-limit field with exact messages") {
  for(const char* field:{"pressure_size","pressure_race"}) {
    ConstructionWire invalid(field,std::string(field)=="pressure_size"?1000:-1);
    REQUIRE(invalid.error());CHECK(*invalid.error()=="invalid pressure creature examples");
  }
  struct Case {const char* field;int64_t accept,reject;const char* error;int page=0;};
  for(const auto& c:std::initializer_list<Case>{
      {"pressure_count",200,199,"invalid pressure creature examples"},
      {"pressure_count",200,201,"invalid pressure creature examples"},
      {"pressure_name",128,129,"invalid pressure creature examples"},
      {"pressure_race",0,-2,"invalid pressure creature examples"},
      {"catalog",128,129,"catalog too large"},{"key",64,65,"invalid definition"},
      {"name",128,129,"invalid definition"},{"reason",128,129,"invalid definition"},
      {"native_name",128,129,"invalid definition"},{"family",64,65,"invalid definition"},
      {"subtype_key",64,65,"invalid definition"},{"custom_code",64,65,"invalid definition"},
      {"width",31,32,"invalid definition"},{"height",31,32,"invalid definition"},
      {"max_width",31,32,"invalid definition"},{"max_height",31,32,"invalid definition"},
      {"max_depth",256,257,"invalid definition"},{"area_mode",4,5,"invalid definition"},
      {"filter",7,8,"invalid construction result"},{"filter",-1,-2,"invalid construction result"},
      {"first_building",-1,-2,"invalid construction result"},{"build_phase",3,4,"invalid construction result"},
      {"build_done",128,129,"invalid construction result"},{"placed",1024,1025,"invalid construction result"},
      {"skipped",0,1,"invalid construction result"},{"list_revision",INT64_MAX,INT64_MIN,"invalid construction result"},
      {"building_key",64,65,"invalid construction result"},{"filters",8,9,"invalid construction result"},
      {"filter_caption",64,65,"invalid construction result"},{"requirement",64,65,"invalid construction result"},
      {"filter_type",-1,-2,"invalid construction result"},{"filter_subtype",-1,-2,"invalid construction result"},
      {"quantity",-1,-2,"invalid construction result"},{"fp_width",31,32,"invalid construction result"},
      {"fp_height",31,32,"invalid construction result"},{"center_x",30,31,"invalid construction result"},
      {"center_y",-1,-2,"invalid construction result"},{"footprints",8,9,"too many construction footprints"},
      {"mask_size",1024,1025,"construction mask too large",2},{"mask",1,2,"invalid construction mask",2},
      {"pieces_size",1024,1025,"construction pieces too large",2},{"piece",3,4,"invalid construction piece",2},
      {"materials",128,129,"construction materials page too large",1},{"count",1,0,"invalid construction material",1},
      {"item_type",-1,-2,"invalid construction material",1},{"item_subtype",-1,-2,"invalid construction material",1},
      {"mat_type",-1,-2,"invalid construction material",1},
      {"mat_index",-1,-2,"invalid construction material",1},
      {"width",1,0,"invalid definition"},{"height",1,0,"invalid definition"},
      {"fp_width",1,0,"invalid construction result"},{"fp_height",1,0,"invalid construction result"},
      {"center_x",-1,-2,"invalid construction result"},{"center_y",30,31,"invalid construction result"},
      {"material_name",128,129,"invalid construction material",1},{"material_caption",64,65,"invalid construction material",1},
      {"version",wire::kManagementVersion,wire::kManagementVersion-1,"invalid management version/revision"}}) {
    CAPTURE(c.field);ConstructionWire accepted(c.field,c.accept,c.page);CHECK_FALSE(accepted.error());
    ConstructionWire rejected(c.field,c.reject,c.page);REQUIRE(rejected.error());CHECK(*rejected.error()==c.error);
  }
  for(const char* key:{"name","reason","native_name","family","subtype_key","custom_code","filter_caption","requirement","building_key"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"catalog","filters","footprints","mask_size","pieces_size","materials"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"filter","first_building","build_phase","build_done","placed","list_revision","quantity","area_mode","max_width","max_height","max_depth"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"mask","piece"})CHECK_FALSE(ConstructionWire(key,0,2).error());
  CHECK_FALSE(ConstructionWire("mat_index",0,1).error());
  CHECK_FALSE(ConstructionWire("count",UINT32_MAX,1).error());
  CHECK_FALSE(ConstructionWire("first_building",INT32_MAX).error());
  ConstructionWire badDirection("direction",8);REQUIRE(badDirection.error());CHECK(*badDirection.error()=="invalid construction result");
  for(const char* key:{"filter_index","direction"}) {
    ConstructionWire duplicate(key,0);REQUIRE(duplicate.error());
    CHECK(*duplicate.error()==(std::string(key)=="direction"?"invalid or duplicate construction footprint":"invalid construction result"));
  }
}

TEST_CASE("construction request boundary and absent-field matrix") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected="") {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(q->depth()==r.depth);CHECK(q->filter()==r.filter);CHECK(q->retracting()==r.retracting);
    CHECK(q->roller_speed()==r.rollerSpeed);
    REQUIRE(bool(q->track_stop())==bool(r.trackStop));
    if(r.trackStop){CHECK(q->track_stop()->friction()==r.trackStop->friction);CHECK(q->track_stop()->dump_direction()==r.trackStop->dumpDirection);}
    REQUIRE(bool(q->pressure_plate())==bool(r.pressurePlate));
    if(r.pressurePlate) {
      const auto* p=q->pressure_plate();const auto& v=*r.pressurePlate;
      CHECK(p->units()==v.units);CHECK(p->water()==v.water);CHECK(p->magma()==v.magma);
      CHECK(p->citizens()==v.citizens);CHECK(p->resets()==v.resets);CHECK(p->track()==v.track);
      CHECK(p->unit_min()==v.unitMin);CHECK(p->unit_max()==v.unitMax);
      CHECK(p->water_min()==v.waterMin);CHECK(p->water_max()==v.waterMax);
      CHECK(p->magma_min()==v.magmaMin);CHECK(p->magma_max()==v.magmaMax);
      CHECK(p->track_min()==v.trackMin);CHECK(p->track_max()==v.trackMax);
    }
    CHECK(q->expected_list_revision()==uint64_t(r.expectedListRevision));
    CHECK(wire::validateConstructionRequest(*q).value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Rollers";
  for(auto speed:{0u,10000u,20000u,30000u,40000u,50000u}){r.rollerSpeed=speed;check(r);}
  for(auto speed:{1u,9999u,15000u,60000u,UINT32_MAX}){r.rollerSpeed=speed;check(r,"invalid roller speed intent");}
  r.rollerSpeed=10000;r.definition="Chair";check(r,"invalid roller speed intent");
  r.definition="Rollers";r.action=wm::ManagementAction::Catalog;check(r,"invalid roller speed intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.rollerSpeed=0;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Trap:TrackStop";check(r,"track stop options required");
  r.trackStop=wm::ManagementRequest::TrackStopOptions{};
  for(auto friction:{10u,50u,500u,10000u,50000u})for(uint8_t dump=0;dump<=4;++dump){r.trackStop->friction=friction;r.trackStop->dumpDirection=dump;check(r);}
  r.trackStop->friction=0;check(r,"invalid track stop intent");r.trackStop->friction=50000;
  r.trackStop->dumpDirection=5;check(r,"invalid track stop intent");r.trackStop->dumpDirection=0;
  r.definition="Chair";check(r,"invalid track stop intent");r.definition="Trap:TrackStop";
  r.action=wm::ManagementAction::Catalog;check(r,"invalid track stop intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.trackStop.reset();r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Trap:PressurePlate";check(r,"pressure plate options required");
  r.pressurePlate=wm::ManagementRequest::PressurePlateOptions{};check(r);
  for(int bits=0;bits<64;++bits) {
    auto& p=*r.pressurePlate;p.units=bits&1;p.water=bits&2;p.magma=bits&4;p.citizens=bits&8;p.resets=bits&16;p.track=bits&32;check(r);
  }
  for(int lo=0;lo<=7;++lo)for(int hi=lo;hi<=7;++hi) {
    auto& p=*r.pressurePlate;p.waterMin=p.magmaMin=int8_t(lo);p.waterMax=p.magmaMax=int8_t(hi);check(r);
  }
  for(int lo=1000;lo<=200000;lo+=1000) {r.pressurePlate->unitMin=lo;r.pressurePlate->unitMax=lo+999;check(r);}
  r.pressurePlate->unitMax=200000999;check(r,"invalid pressure plate intent");
  r.pressurePlate=wm::ManagementRequest::PressurePlateOptions{};
  r.pressurePlate->unitMin=1500;check(r,"invalid pressure plate intent");r.pressurePlate->unitMin=5000;
  r.pressurePlate->waterMin=-1;check(r,"invalid pressure plate intent");r.pressurePlate->waterMin=1;
  r.pressurePlate->magmaMax=8;check(r,"invalid pressure plate intent");r.pressurePlate->magmaMax=7;
  r.pressurePlate->trackMax=2;check(r,"invalid pressure plate intent");r.pressurePlate->trackMax=2000;
  r.definition="Chair";check(r,"invalid pressure plate intent");r.definition="Trap:PressurePlate";
  r.action=wm::ManagementAction::Catalog;check(r,"invalid pressure plate intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.pressurePlate.reset();r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.width=4;r.depth=256;check(r);r.depth=257;check(r,"invalid construction depth or volume");
  r.depth=256;r.width=5;check(r,"invalid construction depth or volume");
  r.definition="Chair";r.width=1;r.depth=0;check(r,"invalid construction depth or volume");r.depth=1;check(r);
  r.retracting=true;check(r);r.direction=1;check(r,"invalid retracting orientation");r.direction=0;r.retracting=false;
  r.action=wm::ManagementAction::Catalog;r.depth=2;check(r,"unexpected construction placement fields");r.depth=1;
  r.retracting=true;check(r,"unexpected construction placement fields");r.retracting=false;
  for(auto rev:{int64_t(0),int64_t(INT64_MAX)}){r.expectedListRevision=rev;check(r);}
  r.expectedListRevision=INT64_MIN;check(r,"invalid construction list revision");r.expectedListRevision=0;
  for(auto f:{int16_t(-2),int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}) {
    r.action=wm::ManagementAction::ConstructionMaterials;r.filter=f;
    check(r,f < -1 || f>7?"invalid construction filter":f==-1?"definition, filter and origin required":"");
  }
  r.filter=0;r.definition="";check(r,"definition, filter and origin required");r.definition="Chair";
  r.action=wm::ManagementAction::Catalog;check(r,"unexpected construction filter");r.filter=-1;
  r.action=wm::ManagementAction::Preview;r.expectedListRevision=1;check(r,"unexpected construction list revision");r.expectedListRevision=0;
  r.action=wm::ManagementAction::Place;
  for(int i=0;i<16;++i)r.selections.push_back({int16_t(i%8),-1,-1,-1,i,1,INT64_MAX});
  check(r);
  r.selections.push_back({0,-1,-1,-1,16,1,INT64_MAX});check(r,"too many construction selections");r.selections.pop_back();
  r.selections[1]=r.selections[0];check(r,"invalid or duplicate construction selection");r.selections.resize(1);
  for(auto f:{int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}){r.selections[0].filter=f;check(r,f<0||f>7?"invalid or duplicate construction selection":"");}
  r.selections[0].filter=0;
  for(auto member:{&wm::ConstructionSelection::itemType,&wm::ConstructionSelection::itemSubtype,&wm::ConstructionSelection::matType}) {
    r.selections[0].*member=-1;check(r);r.selections[0].*member=0;check(r);
    r.selections[0].*member=-2;check(r,"invalid or duplicate construction selection");r.selections[0].*member=-1;
  }
  r.selections[0].matIndex=-2;check(r,"invalid or duplicate construction selection");r.selections[0].matIndex=-1;check(r);
  r.selections[0].count=0;check(r,"invalid or duplicate construction selection");r.selections[0].count=1;
  r.selections[0].count=UINT32_MAX;check(r);r.selections[0].count=1;
  r.action=wm::ManagementAction::Preview;check(r,"unexpected construction selections");r.selections.clear();check(r);
  r.action=wm::ManagementAction::Catalog;r.definition="";check(r);
}

#include "../../bridge/plugin/construction_effects.h"
TEST_CASE("construction committed chunks mark mutations and every intersecting block") {
  wire::TilePos origin(15,31,7);bool mutated=false;
  std::vector<std::tuple<int,int,int>> hints;
  auto hint=[&](int x,int y,int z){hints.emplace_back(x,y,z);};
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK_FALSE(mutated);CHECK(hints.empty());
  // The helper receives committed count even when the Lua reply is Rejected.
  df3d_management::constructionEffects(1,&origin,2,2,2,mutated,hint);
  CHECK(mutated);
  const std::vector<std::tuple<int,int,int>> expected{
    {0,16,7},{16,16,7},{0,32,7},{16,32,7},
    {0,16,8},{16,16,8},{0,32,8},{16,32,8}};
  CHECK(hints==expected);
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK(mutated);CHECK(hints==expected);
}


TEST_CASE("maximal area reply families fit the channel without truncation") {
  // Synthetic wire maxima, not claims about native captions or captured worlds.
  // InspectAtTile has 32768 extents and 8192 link IDs across its whole reply.
  for(int family=0;family<6;++family)for(bool overflow:{false,true}) {
    CAPTURE(family);CAPTURE(overflow);flatbuffers::FlatBufferBuilder b;
    auto caption=[&](){return b.CreateString(std::string(512,'x'));};
    std::vector<flatbuffers::Offset<wire::AreaInfo>> records;
    if(family!=4) {
      const int count=family==5?64:1,cells=32768/count,linkCount=family==5?64:1024;
      for(int i=0;i<count;++i) {
        // Keep family 5 exactly at the byte budget, including each site identity.
        auto name=family==5 ? b.CreateString(std::string(508,'x')) : caption();
        auto owner=caption(),zoneLabel=caption(),location=caption(),religion=caption();
        auto extents=b.CreateVector(std::vector<uint8_t>(cells,1));
        std::vector<int32_t> ids;for(int j=0;j<linkCount;++j)ids.push_back(100000+j);
        auto gives=b.CreateVector(ids),takes=b.CreateVector(ids);wire::TilePos origin(1,2,3);
        wire::AreaInfoBuilder info(b);info.add_id(i);info.add_origin(&origin);info.add_width(256);info.add_height(cells/256);
        info.add_extents(extents);info.add_name(name);info.add_owner_name(owner);info.add_zone_label(zoneLabel);
        info.add_location_name(location);info.add_religion(religion);info.add_gives(gives);info.add_takes(takes);
        records.push_back(info.Finish());
      }
    }
    std::vector<flatbuffers::Offset<wire::AreaSettingRow>> settings;
    std::vector<flatbuffers::Offset<wire::AreaLocationRow>> locations;
    std::vector<flatbuffers::Offset<wire::AreaCandidateRow>> candidates;
    std::vector<flatbuffers::Offset<wire::AreaLinkRow>> links;
    std::vector<flatbuffers::Offset<wire::AreaChoice>> choices;
    for(int i=0;i<(overflow?129:128) && family<5;++i) {
      auto text=caption();
      if(family==0){auto key=std::to_string(i);key.resize(64,'k');settings.push_back(wire::CreateAreaSettingRow(b,b.CreateString(key),i,text,4,3,true));}
      if(family==1)locations.push_back(wire::CreateAreaLocationRow(b,i,text,5,caption()));
      if(family==2)candidates.push_back(wire::CreateAreaCandidateRow(b,i,text,caption(),1,7,true,true,15));
      if(family==3)links.push_back(wire::CreateAreaLinkRow(b,i,wire::AreaKind::Workshop,2,text));
      if(family==4)choices.push_back(wire::CreateAreaChoice(b,i,text,caption()));
    }
    auto as=b.CreateVector(records);auto ss=b.CreateVector(settings);auto ls=b.CreateVector(locations);
    auto cs=b.CreateVector(candidates);auto ks=b.CreateVector(links);auto os=b.CreateVector(choices);
    auto query=b.CreateString(family==5 && overflow?"x":"");
    wire::AreaStateBuilder area(b);area.add_areas(as);area.add_settings(ss);area.add_locations(ls);
    area.add_candidates(cs);area.add_links(ks);area.add_choices(os);area.add_query(query);
    auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    flatbuffers::Verifier verifier(b.GetBufferPointer(),b.GetSize());REQUIRE(verifier.VerifyBuffer<wire::ManagementState>(nullptr));
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    auto error=wire::validateManagementState(*state);
    if(overflow)CHECK(error.value_or("")== (family==5?"area response exceeds bounded payload":"area response too large"));
    else {
      REQUIRE_FALSE(error);CHECK(b.GetSize()<wire::kManagementCapacity);
      const auto decoded=codec::decodeArea(state->area());
      CHECK(decoded.areas.size()==records.size());
      if(!decoded.areas.empty())CHECK(decoded.areas[0].extents.size()==size_t(family==5?512:32768));
      CHECK(decoded.settings.size()==settings.size());CHECK(decoded.locations.size()==locations.size());
      CHECK(decoded.candidates.size()==candidates.size());CHECK(decoded.links.size()==links.size());CHECK(decoded.choices.size()==choices.size());
      std::cout<<"AREA_PAGE_BYTES family="<<family<<" bytes="<<b.GetSize()<<'\n';
    }
  }
}


TEST_CASE("area validator checks the complete action operation matrix") {
  // The table is the approved semantic matrix, independent of implementation.
  const int actionFor[]{0,9,11,11,11,0,9,11,11,11,9,11,11,11,14,13};
  for(int action=7;action<=14;++action)for(int op=0;op<=15;++op) {
    CAPTURE(action);CAPTURE(op);wm::ManagementRequest request;
    request.action=wm::ManagementAction(action);auto& a=request.area;
    a.id=7;a.operation=wm::AreaOperation(op);a.expectedRevision=1;
    a.kind=op==15?wm::AreaKind::Workshop:((op>=6 && op<=9) || op==11 || op==12 || op==14)?wm::AreaKind::Zone:wm::AreaKind::Stockpile;
    if(op==0 && action==13)a.linkId=8;
    if(op==2){a.scope=1;a.value=1;a.rowKey="row";}
    if(op==3)a.preset=1;
    if(op==5){a.paintMode=1;a.paintZ=1;a.spans={{1,1,1}};}
    if(op==7)a.locationId=-1;
    if(op==8){a.locationKind=4;a.profession=0;}
    if(op==9)a.zoneSettings.pondMode=1;
    if(op==11){a.unitId=0;a.assign=0;}
    if(op==12){a.squadId=0;a.squadUse=0;}
    if(op==13)a.organic=0;
    if(op==14)a.candidateKind=1;
    if(op==15)a.linkId=8;
    const bool allowed=op==0 || (op==5?(action==10 || action==11):action==actionFor[op]);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        (allowed?"":"Area operation is not valid for this action"));
    if(allowed) {
      a.kind=op==15?wm::AreaKind::Stockpile:wm::AreaKind::Workshop;
      flatbuffers::FlatBufferBuilder wrong;codec::encodeRequest(wrong,request,1,2,3);
      CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(wrong.GetBufferPointer())).value_or("")==
          "Workshop kind is only valid for workshop links");
    }
  }
}

TEST_CASE("area appended fields reject legacy operations and empty values stay absent") {
  using Edit=void(*)(wm::AreaRequest&);
  const std::pair<const char*,Edit> fields[]{
    {"expected_list_revision",[](auto& a){a.expectedListRevision=1;}},
    {"list_key",[](auto& a){a.listKey="x";}},{"row_key",[](auto& a){a.rowKey="x";}},
    {"scope",[](auto& a){a.scope=1;}},{"value",[](auto& a){a.value=1;}},
    {"preset",[](auto& a){a.preset=1;}},{"name",[](auto& a){a.name="x";}},
    {"spans",[](auto& a){a.spans={{1,1,1}};}},{"paint_mode",[](auto& a){a.paintMode=1;}},
    {"paint_z",[](auto& a){a.paintZ=0;}},{"location_id",[](auto& a){a.locationId=-1;}},
    {"location_kind",[](auto& a){a.locationKind=1;}},{"profession",[](auto& a){a.profession=0;}},
    {"deity_kind",[](auto& a){a.deityKind=1;}},{"deity_id",[](auto& a){a.deityId=0;}},
    {"zone_settings",[](auto& a){a.zoneSettings.pondMode=1;}},{"unit_id",[](auto& a){a.unitId=0;}},
    {"assign",[](auto& a){a.assign=0;}},{"squad_id",[](auto& a){a.squadId=0;}},
    {"squad_use",[](auto& a){a.squadUse=0;}},{"organic",[](auto& a){a.organic=0;}},
    {"inorganic",[](auto& a){a.inorganic=0;}},{"candidate_kind",[](auto& a){a.candidateKind=1;}},
    {"sort",[](auto& a){a.sort=1;}},{"sort_descending",[](auto& a){a.sortDescending=true;}}
  };
  for(const auto& [name,edit]:fields) {
    CAPTURE(name);wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;request.area.id=7;
    flatbuffers::FlatBufferBuilder empty;codec::encodeRequest(empty,request,1,2,3);
    CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(empty.GetBufferPointer())));
    edit(request.area);flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        std::string("Field ")+name+" does not belong to this operation");
  }
}


TEST_CASE("area operations refuse each legacy field before producer dispatch") {
  for(int field=0;field<15;++field) {
    CAPTURE(field);flatbuffers::FlatBufferBuilder b;wire::TilePos origin(0,0,0);
    wire::AreaRequestBuilder area(b);area.add_operation(wire::AreaOperation::Rename);area.add_id(7);area.add_expected_revision(1);
    switch(field) {
      case 0:area.add_origin(&origin);break;case 1:area.add_width(2);break;case 2:area.add_height(2);break;
      case 3:area.add_zone_type(0);break;case 4:area.add_categories(1);break;case 5:area.add_changed_categories(1);break;
      case 6:area.add_barrels(0);break;case 7:area.add_bins(0);break;case 8:area.add_wheelbarrows(0);break;
      case 9:area.add_links_only(0);break;case 10:area.add_active(0);break;case 11:area.add_owner_id(-1);break;
      case 12:area.add_link_id(8);break;case 13:area.add_give(false);break;case 14:area.add_unlink(true);break;
    }
    b.Finish(area.Finish());
    CHECK(wire::validateAreaOperation(wire::ManagementAction::AreaUpdate,*flatbuffers::GetRoot<wire::AreaRequest>(b.GetBufferPointer())).value_or("")==
        "Legacy area fields cannot be combined with an operation");
  }
}

TEST_CASE("area required selectors distinguish absent sentinels from meaningful zero") {
  for(int field=0;field<6;++field)for(bool absent:{false,true}) {
    CAPTURE(field);CAPTURE(absent);wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.id=7;a.expectedRevision=1;a.kind=wm::AreaKind::Zone;
    const char* message="";
    if(field<2) {
      a.operation=wm::AreaOperation::AssignUnits;a.unitId=0;a.assign=0;
      if(absent){if(field==0)a.unitId=-1;else a.assign=-1;message="invalid area unit assignment";}
    } else if(field<4) {
      a.operation=wm::AreaOperation::SquadUse;a.squadId=0;a.squadUse=0;
      if(absent){if(field==2)a.squadId=-1;else a.squadUse=-1;message="invalid area squad use";}
    } else if(field==4) {
      a.operation=wm::AreaOperation::LocationCreate;a.locationKind=4;a.profession=absent?-1:0;
      if(absent)message="invalid area location creation";
    } else {
      a.operation=wm::AreaOperation::LocationCreate;a.locationKind=2;a.deityKind=2;a.deityId=absent?-1:0;
      if(absent)message="invalid area location creation";
    }
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==message);
  }
  for(int deityKind:{-1,0,1,2,3,4}) {
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.id=7;a.expectedRevision=1;a.kind=wm::AreaKind::Zone;
    a.operation=wm::AreaOperation::LocationCreate;a.locationKind=2;a.deityKind=int8_t(deityKind);a.deityId=deityKind>=2?0:-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        (deityKind>=1 && deityKind<=3?"":"invalid area location creation"));
  }
}


TEST_CASE("area validation stages reject malformed selectors fields identities and sizes") {
  const char* errors[]{"Unsupported area operation","Area operation is not valid for this action",
    "Workshop kind is only valid for workshop links","Area kind is not valid for this operation",
    "Legacy area fields cannot be combined with an operation","Field organic does not belong to this operation",
    "area id required","area name too long","invalid area revision"};
  for(int stage=0;stage<9;++stage) {
    CAPTURE(stage);flatbuffers::FlatBufferBuilder b;
    const auto name=b.CreateString(stage==7?std::string(513,'x'):"");
    wire::AreaRequestBuilder area(b);area.add_operation(stage==0?wire::AreaOperation(int(wire::AreaOperation::MAX)+1):stage==3?wire::AreaOperation::Preset:wire::AreaOperation::Rename);
    area.add_id(stage==6?-1:7);area.add_expected_revision(stage==8?uint64_t(INT64_MAX)+1:1);area.add_name(name);
    if(stage==2)area.add_kind(wire::AreaKind::Workshop);
    if(stage==3){area.add_kind(wire::AreaKind::Zone);area.add_preset(1);}
    if(stage==4)area.add_width(2);
    if(stage==5)area.add_organic(0);
    b.Finish(area.Finish());
    CHECK(wire::validateAreaOperation(stage==1?wire::ManagementAction::AreaInspect:wire::ManagementAction::AreaUpdate,
        *flatbuffers::GetRoot<wire::AreaRequest>(b.GetBufferPointer())).value_or("")==errors[stage]);
  }
}

TEST_CASE("Location staff transport preserves duplicates and unresolved holders and rejects bad identities") {
  for(int mode=0;mode<8;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto names=wire::CreateLocationStaffNames(b,b.CreateString(""),b.CreateString("Fixture holder"),1,INT32_MAX);
    const auto row=wire::CreateLocationStaffRow(b,mode==1?2:0,mode==2?-1:17,mode==3?2:7,-2,INT32_MAX,mode==4?1:0,651,INT32_MAX,-1,-1,-1,mode==0?names:0);
    const auto staff=wire::CreateLocationStaffSnapshot(b,b.CreateVector(std::vector<flatbuffers::Offset<wire::LocationStaffRow>>{row,row}),
        b.CreateVector(std::vector<int32_t>{8,mode==5?8:mode==6?1:9}));
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<10;++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto name=b.CreateString("Fixture");const auto quantities=b.CreateVector(supplies);
    wire::LocationDetailsBuilder detail(b);detail.add_site_id(651);detail.add_id(0);detail.add_kind(5);detail.add_name(name);
    detail.add_revision(1);detail.add_access(2);detail.add_tier(0);detail.add_supplies(quantities);
    if(mode!=7)detail.add_staff(staff);
    const auto d=detail.Finish();
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::LocationDetails);area.add_location_details(d);
    const auto a=area.Finish();b.Finish(a);
    const auto* encoded=flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateLocationDetails(*encoded->location_details()))==(mode>=1 && mode<=6));
    if(mode==0 || mode>=7) {
      const auto decoded=codec::decodeArea(encoded);REQUIRE(decoded.locationDetails);
      if(mode==7)CHECK_FALSE(decoded.locationDetails->staff);
      else {
        REQUIRE(decoded.locationDetails->staff);const auto& v=*decoded.locationDetails->staff;
        REQUIRE(v.rows.size()==2);
        if(mode==0) { REQUIRE(v.rows[0].names);CHECK(v.rows[0].names->holderName=="Fixture holder");CHECK(v.rows[0].names->positionName.empty());CHECK(v.rows[0].names->holderKind==1);CHECK(v.rows[0].names->holderId==INT32_MAX); }
        CHECK(v.rows[0].occupationId==17);CHECK(v.rows[1].occupationId==17);
        CHECK(v.rows[0].histfigId==-2);CHECK(v.rows[0].unitId==INT32_MAX);CHECK(v.rows[0].groupId==INT32_MAX);
        CHECK(v.missingRoles==std::vector<int32_t>{8,9});
      }
    }
  }
}

TEST_CASE("Location entry requires a mutation action, exact receipt and owned identities") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  base.area.kind=wm::AreaKind::Zone;base.area.operation=wm::AreaOperation::LocationOpen;
  base.area.locationSiteId=651;base.area.locationId=0;base.area.expectedRevision=17;
  for(int mode=0;mode<8;++mode) {
    auto r=base;
    if(mode==1)r.action=wm::ManagementAction::AreaInspect;
    if(mode==2)r.area.expectedRevision=0;
    if(mode==3)r.area.locationSiteId=-1;
    if(mode==4)r.area.locationId=-1;
    if(mode==5)r.area.id=23;
    if(mode==6)r.area.query="foreign";
    if(mode==7)r.area.cursor=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())))==(mode!=0));
  }
}
TEST_CASE("Location access requests own an exact receipt and native mode") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  base.area.kind=wm::AreaKind::Zone;base.area.operation=wm::AreaOperation::LocationAccess;
  base.area.locationSiteId=651;base.area.locationId=0;base.area.expectedRevision=9007199254740993ULL;
  for(int mode=0;mode<17;++mode) {
    auto r=base;r.area.value=mode<4?mode:0;
    if(mode==4)r.action=wm::ManagementAction::AreaInspect;
    if(mode==5)r.area.expectedRevision=0;
    if(mode==6)r.area.expectedRevision=uint64_t(INT64_MAX)+1;
    if(mode==7)r.area.value=4;
    if(mode==8)r.area.locationSiteId=-1;
    if(mode==9)r.area.locationId=-1;
    if(mode==10)r.area.id=23;
    if(mode==11)r.area.query="foreign";
    if(mode==12)r.area.cursor=1;
    if(mode==13)r.area.kind=wm::AreaKind::Stockpile;
    if(mode==14)r.area.scope=1;
    if(mode==15)r.area.expectedListRevision=1;
    if(mode==16)r.area.locationKind=2;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=4));
    if(mode<4){CHECK(encoded->area()->value()==mode);CHECK(encoded->area()->expected_revision()==9007199254740993ULL);}
  }
}
TEST_CASE("Location edit outcomes require matching action operation status and snapshot") {
  for(auto operation:{wire::AreaOperation::LocationAccess,wire::AreaOperation::LocationStaffEdit})
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<10;++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto details=wire::CreateLocationDetails(b,651,0,2,b.CreateString("Synthetic temple"),17,2,false,false,false,-1,0,0,0,false,b.CreateVector(supplies));
    wire::AreaStateBuilder area(b);
    area.add_operation(mode==7?wire::AreaOperation::LocationDetails:operation);
    const auto outcome=mode<=4?mode:1;
    area.add_location_edit_outcome(static_cast<wire::LocationEditOutcome>(mode==10?5:outcome));
    if(mode==1 || mode>=5)area.add_location_details(details);
    if(mode==8)area.add_location_entry_outcome(wire::LocationEntryOutcome::Completed);
    auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(2);
    state.add_action(mode==6?wire::ManagementAction::AreaInspect:wire::ManagementAction::AreaUpdate);
    state.add_status(mode==1 || (mode>=5 && mode!=9)?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);state.add_area(a);
    b.Finish(state.Finish());const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*root))==(mode==0 || mode>=6));
    if(mode>=1 && mode<=5)CHECK(int(codec::decodeArea(root->area()).locationEditOutcome)==outcome);
  }
}
TEST_CASE("Location entry failure outcomes survive decoding without claiming success") {
  for(int outcome=0;outcome<=5;++outcome) {
    flatbuffers::FlatBufferBuilder b;
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::LocationOpen);
    area.add_location_entry_outcome(static_cast<wire::LocationEntryOutcome>(outcome));
    auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(2);
    state.add_action(wire::ManagementAction::AreaUpdate);state.add_status(wire::ManagementStatus::Rejected);state.add_area(a);
    b.Finish(state.Finish());const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(outcome);CHECK(bool(wire::validateManagementState(*root))==(outcome<2 || outcome>4));
    if(outcome>=2 && outcome<=4)CHECK(int(codec::decodeArea(root->area()).locationEntryOutcome)==outcome);
  }
}

TEST_CASE("Details affiliation validates ownership and preserves legacy unknown") {
  for(int mode=0;mode<19;++mode) {
    flatbuffers::FlatBufferBuilder b;
    uint8_t kind=mode==1?1:mode==2?2:mode==3?3:4;
    int32_t id=mode==1 || mode==4?-1:383,count=mode==1 || mode==4?0:53,workers=mode>=4?12:-1;
    std::string name=mode==1 || mode==4?"":"Synthetic affiliation";
    if(mode==7)count=-1;
    if(mode==8)workers=-1;
    if(mode==9)kind=0;
    if(mode==10)name=std::string(513,'x');
    if(mode==11)id=-2;
    if(mode==12){kind=1;id=-1;count=1;workers=-1;name="";}
    if(mode==13){kind=1;id=-1;count=0;workers=0;name="";}
    if(mode==14){id=-1;name="Unexpected absent guild name";count=0;}
    if(mode==15){id=-1;name="";count=1;}
    if(mode==16){kind=2;workers=-1;id=-1;}
    if(mode==17){kind=3;workers=0;}
    const auto text=b.CreateString(name);
    const auto affiliation=wire::CreateLocationAffiliation(b,kind,id,mode==18?0:text,count,workers);
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> quantities;
    for(uint8_t i=0;i<10;++i)quantities.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto supplies=b.CreateVector(quantities);const auto title=b.CreateString("Synthetic location");
    wire::LocationDetailsBuilder builder(b);
    builder.add_site_id(651);builder.add_id(0);builder.add_kind(mode==6?5:kind==4?4:2);
    builder.add_name(title);builder.add_revision(1);builder.add_tier(0);builder.add_access(2);builder.add_supplies(supplies);
    if(mode!=0)builder.add_affiliation(affiliation);
    const auto details=builder.Finish();wire::AreaStateBuilder area(b);area.add_location_details(details);
    b.Finish(area.Finish());const auto* encoded=flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateLocationDetails(*encoded->location_details()))==(mode>=6));
    if(mode<6) {
      const auto model=codec::decodeArea(encoded);REQUIRE(model.locationDetails);
      if(mode==0)CHECK_FALSE(model.locationDetails->affiliation);
      else {REQUIRE(model.locationDetails->affiliation);const auto& actual=*model.locationDetails->affiliation;
        CHECK(actual.kind==kind);CHECK(actual.id==id);CHECK(actual.name==name);CHECK(actual.count==count);CHECK(actual.workers==workers);}
    }
  }
}

TEST_CASE("Connected Track accepts a group per tile within command capacity") {
  for(int count:{17,16384}) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::Place;r.definition="Construction:Track";
    r.x=1;r.y=1;r.z=1;r.connectedTrackDestination=wm::TilePos{17,1,1};
    for(int i=0;i<count;++i)r.selections.push_back({0,0,-1,0,i,1,42,std::vector<int32_t>{i}});
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    CHECK(b.GetSize()<wire::kManagementCommandCapacity);
    CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
  }
}

TEST_CASE("Reports tab requests preserve selectors and reject ambiguous cursors") {
  for(int mode=0;mode<7;++mode) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;
    q.report.view=wm::ReportView::Tab;q.report.tab=wm::ReportTab::World;q.report.afterId=0;q.report.expectedListRevision=17;
    if(mode==1)q.report.beforeId=10;
    if(mode==2)q.report.fromEnd=true;
    if(mode==3)q.report.tab=wm::ReportTab::Combat;
    if(mode==4)q.report.view=wm::ReportView::UnitLog;
    if(mode==5)q.action=wm::ManagementAction::ReportInspect;
    if(mode==6)q.report.query="fixture";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*request).has_value()==(mode!=0));
    CHECK(request->report()->after_id()==0);CHECK(request->report()->view()==wire::ReportView(q.report.view));
  }
}
TEST_CASE("Reports tab replies retain native row metadata and enforce page shape") {
  for(int mode=0;mode<9;++mode) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::ReportInfo>> rows;
    for(int i=0;i<(mode==1?65:64);++i) {
      rows.push_back(wire::CreateReportInfo(b,i,b.CreateString("MIGRANT_ARRIVAL"),b.CreateString("Fixture"),106,0,0,false,true,
        -1,mode==5?-1:50,mode==5?-1:165,-1,-1,-1,mode!=5,false,wire::ReportTab::General,mode==4?16:3,true,
        wire::ReportZoom::Unit,wire::ReportZoom::None,true,false,mode==6?-2:17));
    }
    std::vector<uint32_t> counts(mode==2?24:25,0);counts[0]=counts[1]=uint32_t(rows.size());
    auto report=wire::CreateReportState(b,b.CreateVector(rows),-1,false,{},wire::ReportView::Tab,
      mode==3?wire::ReportTab(26):wire::ReportTab::General,0,false,b.CreateVector(counts),uint32_t(rows.size()),mode==7?-2:-1,0,true,-1,-1,0,0,mode==8?0:17);
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_world_epoch(7);
    root.add_action(wire::ManagementAction::ReportList);root.add_status(wire::ManagementStatus::Ok);root.add_report(report);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0) {
      const auto decoded=codec::decodeReport(state->report());
      CHECK(decoded.view==wm::ReportView::Tab);CHECK(decoded.tab==wm::ReportTab::General);CHECK(decoded.total==64);
      REQUIRE(decoded.reports.size()==64);const auto& row=decoded.reports[0];
      CHECK(row.x==-1);CHECK(row.positionVisible);CHECK(row.positionHidden);CHECK(row.color==3);CHECK(row.bright);
      CHECK(row.zoomType==wm::ReportZoom::Unit);CHECK(row.zoomType2==wm::ReportZoom::None);CHECK(row.speakerId==17);
    }
  }
}

TEST_CASE("Report unit requests preserve exact revision and reject foreign selectors") {
 for(int mode=0;mode<8;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::UnitList;
  q.report.unitCategory=1;q.report.cursor=64;q.report.expectedListRevision=INT64_MAX;
  if(mode==1)q.report.unitCategory=-1;
  if(mode==2)q.report.afterId=0;
  if(mode==3)q.report.tab=wm::ReportTab::Combat;
  if(mode==4)q.report.view=wm::ReportView::Entries;
  if(mode>=5){q.report.view=wm::ReportView::UnitLog;q.report.unitId=17;q.report.cursor=0;q.report.expectedListRevision=0;}
  if(mode==6)q.report.unitId=-1;
  if(mode==7)q.report.cursor=1;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=5));
  CHECK(r->report()->expected_list_revision()==q.report.expectedListRevision);
 }
}
TEST_CASE("Report unit rows decode names counts and signed-safe revision") {
 for(int mode=0;mode<5;++mode) {
  flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::ReportUnitInfo>> units;
  units.push_back(wire::CreateReportUnitInfo(b,17,mode==1?3:1,b.CreateString("Fixture profession"),b.CreateString(mode==2?std::string(513,'x'):"Fixture name"),true,999,b.CreateString("")));
  const auto encodedUnits=b.CreateVector(units);wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::UnitList);report.add_unit_category(1);
  report.add_units(encodedUnits);report.add_total(1);report.add_list_revision(mode==3?0:INT64_MAX);report.add_next_cursor(mode==4?2:0);
  const auto r=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportList);state.add_report(r);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){const auto decoded=codec::decodeReport(root->report());REQUIRE(decoded.units.size()==1);CHECK(decoded.units[0].unitId==17);CHECK(decoded.units[0].dead);CHECK(decoded.units[0].logCount==999);CHECK(decoded.listRevision==INT64_MAX);}
 }
}

TEST_CASE("Entries preserves duplicate references and rejects foreign fields") {
 for(int mode=0;mode<6;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Entries;
  q.report.ids={41,0,41};q.report.units={{17,1},{17,1}};
  if(mode==1)q.report.ids[0]=-1;
  if(mode==2)q.report.units[0].category=3;
  if(mode==3)q.report.ids.resize(65,0);
  if(mode==4)q.report.unitId=17;
  if(mode==5)q.action=wm::ManagementAction::ReportList;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0));
  if(mode==0){CHECK(r->report()->ids()->Get(2)==41);CHECK(r->report()->units()->size()==2);}
 }
}
TEST_CASE("Entries replies allow native repeated rows and retain missing IDs") {
 for(int mode=0;mode<3;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto row=wire::CreateReportInfo(b,41,b.CreateString("Fixture"),b.CreateString("Fixture"),106,1);
  auto unit=wire::CreateReportUnitInfo(b,17,1,b.CreateString("Fixture"),b.CreateString("Name"),false,2,b.CreateString(""));
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>{row,row});
  auto units=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportUnitInfo>>{unit,unit});
  auto missing=b.CreateVector(std::vector<int32_t>{mode==2?-1:999,999});
  wire::ReportStateBuilder report(b);report.add_view(mode==1?wire::ReportView::Flat:wire::ReportView::Entries);report.add_reports(rows);report.add_units(units);report.add_missing_ids(missing);
  auto value=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportInspect);state.add_report(value);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){auto decoded=codec::decodeReport(root->report());CHECK(decoded.reports.size()==2);CHECK(decoded.units.size()==2);CHECK(decoded.missingIds==std::vector<int32_t>{999,999});}
 }
}

TEST_CASE("Full report text requests require snapshot cursors and reject foreign selectors") {
 for(int mode=0;mode<12;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=7;
  q.report.cursor=16383;q.report.expectedListRevision=INT64_MAX;
  if(mode==1)q.report.expectedListRevision=0;
  if(mode==2)q.report.cursor=33554433;
  if(mode==3)q.report.unitId=7;
  if(mode==4)q.report.tab=wm::ReportTab::Combat;
  if(mode==5)q.report.ids={7};
  if(mode==6)q.action=wm::ManagementAction::ReportList;
  if(mode==7)q.report.id=-1;
  if(mode==8)q.report.announcementsOnly=false;
  if(mode==9){q.report.cursor=0;q.report.expectedListRevision=0;}
  if(mode>=10)q.report.tab=wm::ReportTab::All;
  if(mode==11)q.report.expectedListRevision=0;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=9 && mode!=10));
 }
}
TEST_CASE("Full report text replies enforce byte accounting and completeness") {
 for(int mode=0;mode<9;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("tail");auto category=b.CreateString("Fixture");
  wire::ReportInfoBuilder row(b);row.add_id(7);row.add_text(text);row.add_category(category);row.add_text_complete(mode==4);
  auto value=row.Finish();auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>(mode==5?2:1,value));
  wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::Text);report.add_reports(rows);
  report.add_cursor(mode==1?101:96);report.add_total(mode==2?33554433:100);
  report.add_list_revision(mode==3?0:INT64_MAX);report.add_next_cursor(mode==6?100:0);
  if(mode==7)report.add_unit_id(7);
  if(mode==8)report.add_tab(wire::ReportTab::Combat);
  auto r=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportInspect);state.add_report(r);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){const auto decoded=codec::decodeReport(root->report());CHECK(decoded.view==wm::ReportView::Text);CHECK(decoded.cursor==96);CHECK(decoded.total==100);CHECK(decoded.listRevision==INT64_MAX);}
 }
}

TEST_CASE("Retained unit-log refresh and text selectors are explicit") {
 for(int mode=0;mode<10;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::UnitLog;
  q.report.unitId=17;q.report.unitCategory=1;q.report.expectedListRevision=71;q.report.afterId=0;q.report.refresh=true;
  if(mode==1)q.report.expectedListRevision=0;
  if(mode==2){q.report.afterId=-1;q.report.fromEnd=true;}
  if(mode==3){q.report.afterId=-1;q.report.beforeId=4;}
  if(mode==4)q.report.view=wm::ReportView::UnitList;
  if(mode>=5){q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=5;q.report.afterId=-1;q.report.refresh=false;}
  if(mode==6)q.report.expectedListRevision=0;
  if(mode==7)q.report.tab=wm::ReportTab::All;
  if(mode==8)q.report.unitCategory=-1;
  if(mode==9)q.report.refresh=true;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=5));
  CHECK(r->report()->refresh()==q.report.refresh);
 }
}

TEST_CASE("Alert Group requests separate source selection from retained Text owners") {
 for(int mode=0;mode<14;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::Group;
  q.report.notificationCategory=20;
  if(mode==1){q.report.notificationCategory=-1;q.report.alertButton=true;}
  if(mode==2)q.report.notificationCategory=-1;
  if(mode==3)q.report.alertButton=true;
  if(mode==4)q.report.cursor=1;
  if(mode==5){q.report.cursor=64;q.report.expectedListRevision=17;}
  if(mode>=6){q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=7;q.report.expectedListRevision=17;}
  if(mode==7)q.report.expectedListRevision=0;
  if(mode==8)q.report.tab=wm::ReportTab::All;
  if(mode==9){q.report.unitId=17;q.report.unitCategory=1;}
  if(mode==10)q.report.notificationCategory=37;
  if(mode==11)q.report.refresh=true;
  if(mode==12){q.report.view=wm::ReportView::Flat;q.report.expectedListRevision=0;}
  if(mode==13)q.report.ids={7};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=1 && mode!=5 && mode!=6));
  CHECK(r->report()->notification_category()==q.report.notificationCategory);
  CHECK(r->report()->alert_button()==q.report.alertButton);
 }
}
TEST_CASE("Alert Group pages preserve duplicates and enforce exact cursor progress") {
 for(int mode=0;mode<9;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto row=wire::CreateReportInfo(b,41,b.CreateString("Fixture"),b.CreateString("Fixture"),106,1);
  auto unit=wire::CreateReportUnitInfo(b,17,1,b.CreateString("Fixture"),b.CreateString("Name"),false,2,b.CreateString(""));
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>{row,row});
  auto units=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportUnitInfo>>{unit,unit});
  wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::Group);report.add_notification_category(mode==1?-1:20);
  report.add_reports(rows);report.add_units(units);report.add_total(mode==2?3:300);report.add_cursor(0);
  report.add_next_cursor(mode==3?5:4);report.add_list_revision(mode==4?0:17);
  if(mode==5)report.add_alert_button(true);
  if(mode==6)report.add_tab(wire::ReportTab::All);
  if(mode==7)report.add_unit_id(17);
  if(mode==8)report.add_total(65537);
  auto value=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportList);state.add_report(value);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){auto decoded=codec::decodeReport(root->report());CHECK(decoded.notificationCategory==20);CHECK_FALSE(decoded.alertButton);CHECK(decoded.reports.size()==2);CHECK(decoded.units.size()==2);}
 }
}
