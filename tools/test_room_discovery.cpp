#include "doctest.h"
#include "../bridge/plugin/room_discovery.h"
#include "../bridge/plugin/room_plan.h"
namespace area=df3d_area;

TEST_CASE("native Floored occupancy connects rooms across underlying boundary shapes") {
  // Native paired creation/read probes: paint-native-occupancy-shapes-050121/
  // floored-multi.json. Separator (173,58,164), seed (172,57,164).
  using S=area::RoomShape;using O=area::RoomOccupancy;using L=area::RoomLiquid;
  struct Sample {S shape;L liquid;uint8_t depth;bool joined;};
  const Sample samples[]={{S::Empty,L::None,0,true},{S::Wall,L::None,0,true},
    {S::Fortification,L::None,0,true},{S::Wall,L::None,0,true}, // TreeCapInterior is WALL.
    {S::Empty,L::Water,1,true},{S::Empty,L::Water,7,false},{S::Empty,L::Magma,1,false}};
  for(const auto& s:samples) {
    INFO("shape=",int(s.shape)," liquid=",int(s.liquid)," depth=",int(s.depth));
    std::vector<area::RoomCell> cells(45,area::RoomCell::Boundary);
    for(int y=1;y<4;++y)for(int x=1;x<8;++x)
      if(x!=4)cells[size_t(y)*9+x]=area::RoomCell::Open;
    cells[2*9+4]=area::classifyRoomCell(s.shape,O::Floored,s.liquid,s.depth,false);
    const auto actual=area::traverseRoom(cells,9,5,3,1);
    REQUIRE(actual.status==area::RoomTraversalStatus::Complete);
    std::vector<uint8_t> expected(45,0);
    for(int y=0;y<5;++y)for(int x=0;x<(s.joined?9:5);++x)expected[size_t(y)*9+x]=1;
    CHECK(actual.reached==expected);
  }
}

namespace {
area::RoomFootprint capturedRectangle(int32_t x,int32_t y,int32_t z,int32_t w,int32_t h) {
  return {{x,y,w,h},z,std::vector<uint8_t>(size_t(w)*h,1),true};
}
}
TEST_CASE("room plans match native shared furniture and bed selection semantics") {
  // Native exact rectangular masks: room-seed-live-012537 Office-group,
  // DiningHall-group, coffins-both; paint-native-rooms-001424 east_open,
  // two_rooms and two_unused_rooms. Discovery itself is independently tested.
  using F=area::RoomFurniture;
  for(const auto kind:{F::Chair,F::Table,F::Coffin}) {
    const bool coffin=kind==F::Coffin,chair=kind==F::Chair;
    const int32_t x=coffin?92:123,y=coffin?124:(chair?90:89);
    std::vector<area::RoomSeed> seeds;
    if(coffin)seeds={{220,93,124,165,kind,true,false},{1613,92,124,165,kind,true,false}};
    else for(int32_t i=0;i<3;++i)seeds.push_back({chair?(i==2?69:65+i):62+i,x+i,y,165,kind,true,false});
    const auto footprint=coffin?capturedRectangle(91,122,165,5,5):capturedRectangle(121,87,165,7,7);
    int discoveries=0;
    const auto plan=area::planRooms(seeds,kind,{x,y,coffin?2:3,1},165,[&](const area::RoomSeed&) {
      ++discoveries;return area::RoomDiscovery{area::RoomTraversalStatus::Complete,footprint};
    });
    REQUIRE(plan.status==area::RoomPlanStatus::Complete);
    REQUIRE(plan.rooms.size()==1);
    CHECK(discoveries==1);CHECK(plan.rooms[0].seedId==seeds.front().id);
    CHECK_FALSE(plan.rooms[0].dormitory);CHECK(area::sameRoom(plan.rooms[0].footprint,footprint));
    CHECK(plan.rejectedInUse==0);CHECK(plan.rejectedUnenclosed==0);
  }
  std::vector<area::RoomSeed> beds{{1183,176,57,164,F::Bed,true,true},{1310,172,57,164,F::Bed,true,false}};
  const auto merged=capturedRectangle(169,56,164,9,5);
  auto plan=area::planRooms(beds,F::Bed,{172,57,1,1},164,[&](const area::RoomSeed&) {
    return area::RoomDiscovery{area::RoomTraversalStatus::Complete,merged};
  });
  REQUIRE(plan.rooms.size()==1);CHECK(plan.rooms[0].dormitory);
  CHECK(plan.rejectedInUse==0);CHECK(plan.rooms[0].seedId==1310);
  auto split=[](const area::RoomSeed& seed) {
    return area::RoomDiscovery{area::RoomTraversalStatus::Complete,
      capturedRectangle(seed.id==1183?173:169,56,164,5,5)};
  };
  plan=area::planRooms(beds,F::Bed,{171,57,7,1},164,split);
  REQUIRE(plan.rooms.size()==1);CHECK_FALSE(plan.rooms[0].dormitory);
  CHECK(plan.rejectedInUse==1);CHECK(plan.rooms[0].seedId==1310);
  beds[0].inUse=false;
  plan=area::planRooms(beds,F::Bed,{172,57,5,1},164,split);
  REQUIRE(plan.rooms.size()==2);
  CHECK(plan.rooms[0].seedId==1183);CHECK(plan.rooms[1].seedId==1310);
  CHECK_FALSE(plan.rooms[0].dormitory);CHECK_FALSE(plan.rooms[1].dormitory);
  CHECK(plan.rejectedInUse==0);
}

TEST_CASE("room planning distinguishes holes elevation rejection and unknown observations") {
  using F=area::RoomFurniture;
  std::vector<area::RoomSeed> seeds{{1,11,11,5,F::Bed,true,false},{2,13,11,5,F::Bed,true,false},
                                   {3,11,11,6,F::Bed,true,false}};
  auto first=capturedRectangle(10,10,5,5,3);first.extents[8]=0;
  auto plan=area::planRooms(seeds,F::Bed,{10,10,5,3},5,[&](const area::RoomSeed& seed) {
    return seed.id==1?area::RoomDiscovery{area::RoomTraversalStatus::Complete,first}:
      area::RoomDiscovery{area::RoomTraversalStatus::Unenclosed,{}};
  });
  REQUIRE(plan.rooms.size()==1);CHECK_FALSE(plan.rooms[0].dormitory);
  CHECK(plan.rejectedUnenclosed==1);CHECK(plan.rejectedInUse==0);
  plan=area::planRooms(seeds,F::Bed,{10,10,5,3},5,[&](const area::RoomSeed& seed) {
    return seed.id==1?area::RoomDiscovery{area::RoomTraversalStatus::Complete,first}:
      area::RoomDiscovery{area::RoomTraversalStatus::Incomplete,{}};
  });
  CHECK(plan.status==area::RoomPlanStatus::Incomplete);CHECK(plan.rooms.empty());
  CHECK(plan.rejectedUnenclosed==0);
  CHECK(area::planRooms(seeds,F::None,{10,10,5,3},5,[](const auto&){return area::RoomDiscovery{};}).status==area::RoomPlanStatus::Invalid);
}

TEST_CASE("room collision requires shared enabled native open cells") {
  auto room=capturedRectangle(169,56,164,5,5);
  const area::Bounds floor{170,58,1,1},wall{169,56,1,1};
  auto enabled=[](int32_t,int32_t){return true;};
  auto open=[](int32_t,int32_t,int32_t){return area::RoomCell::Open;};
  auto boundary=[](int32_t,int32_t,int32_t){return area::RoomCell::Boundary;};
  auto unknown=[](int32_t,int32_t,int32_t){return area::RoomCell::Unobserved;};
  CHECK(area::roomCollision(room,floor,164,enabled,open)==area::RoomCollision::Overlap);
  CHECK(area::roomCollision(room,wall,164,enabled,boundary)==area::RoomCollision::None);
  CHECK(area::roomCollision(room,floor,163,enabled,open)==area::RoomCollision::None);
  CHECK(area::roomCollision(room,floor,164,[](int32_t,int32_t){return false;},open)==area::RoomCollision::None);
  room.extents[11]=0;
  CHECK(area::roomCollision(room,floor,164,enabled,open)==area::RoomCollision::None);
  room.extents[11]=1;
  CHECK(area::roomCollision(room,floor,164,enabled,unknown)==area::RoomCollision::Unknown);
  // Native collision-shape-results.json: the 20 shapes' overlap outcomes.
  for(int i=0;i<int(area::RoomShape::Unknown);++i) {
    const auto shape=static_cast<area::RoomShape>(i);
    const bool collides=shape==area::RoomShape::Floor || shape==area::RoomShape::Boulder ||
      shape==area::RoomShape::Pebbles || shape==area::RoomShape::StairUp ||
      shape==area::RoomShape::StairDown || shape==area::RoomShape::StairUpDown ||
      shape==area::RoomShape::Ramp || shape==area::RoomShape::BrookTop ||
      shape==area::RoomShape::Branch || shape==area::RoomShape::Twig ||
      shape==area::RoomShape::Sapling || shape==area::RoomShape::Shrub;
    const auto result=area::roomCollision(room,floor,164,enabled,[&](int32_t,int32_t,int32_t) {
      return area::classifyRoomCell(shape,area::RoomOccupancy::None,area::RoomLiquid::None,0,false);
    });
    CHECK(result==(collides?area::RoomCollision::Overlap:area::RoomCollision::None));
  }
}

// DF53.16 Multi captures 2026-09-29: room-limits-002445 and room-cap-003442.
// Semantic excerpts of35 native probes, including exact successful extents and
// native enclosure rejections. Boundary lists include retained doors and fixture
// obstacles; expected holes/status come from native results, not this helper.
// Raw evidence: build/notes/pm/runs/04-U/paint-native-room-{limits,cap}-*/.
TEST_CASE("room traversal matches native masks and enclosure decisions") {
  struct Sample {const char* name;uint32_t w,h,x,y;bool success;std::vector<size_t> boundaries,holes;};
  const std::vector<Sample> samples{
    {"asym30",30,5,27,2,false,{52,56},{}},
    {"both20",40,43,21,21,false,{312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"both21",41,43,22,21,false,{320,345,349,353,357,427,431,435,439,648,755,759,763,767,837,841,845,849,976,1165,1169,1173,1177,1181,1247,1251,1255,1259,1345,1509,1571,1575,1579,1583,1587,1597,1653,1657,1661,1665,1669,1679},{}},
    {"left20",24,5,21,2,true,{40,44},{}},
    {"left21",25,5,22,2,false,{42,46},{}},
    {"radius_10",21,21,10,10,true,{152,156,160,164,194,198,202,206,362,366,370,374,404,408,412,416},{}},
    {"radius_12",25,25,12,12,true,{32,36,40,44,173,232,236,240,244,282,286,290,294,373,482,486,490,494,498,532,536,540,544,598},{624}},
    {"radius_15",31,31,15,15,true,{57,72,76,80,84,134,138,142,146,305,382,386,390,394,444,448,452,456,553,692,696,700,704,708,754,758,762,766,832},{}},
    {"radius_16",33,33,16,16,true,{93,110,114,118,122,176,180,184,188,357,440,444,448,452,506,510,514,518,621,770,774,778,782,786,836,840,844,848,918,1050},{}},
    {"radius_17",35,35,17,17,true,{133,152,156,160,164,222,226,230,234,413,502,506,510,514,572,576,580,584,693,852,856,860,864,868,922,926,930,934,1008,1148},{}},
    {"radius_18",37,37,18,18,true,{177,198,202,206,210,272,276,280,284,473,568,572,576,580,642,646,650,654,769,938,942,946,950,954,1012,1016,1020,1024,1102,1250,1304,1308,1312,1316,1320,1330},{1368}},
    {"radius_19",39,39,20,19,true,{226,249,253,257,261,327,331,335,339,538,639,643,647,651,717,721,725,729,850,1029,1033,1037,1041,1045,1107,1111,1115,1119,1201,1357,1415,1419,1423,1427,1431,1441},{}},
    {"radius_2",5,5,2,2,true,{6},{0}},
    {"radius_20",41,41,22,20,false,{279,304,308,312,316,386,390,394,398,607,714,718,722,726,796,800,804,808,935,1124,1128,1132,1136,1140,1206,1210,1214,1218,1304,1468,1530,1534,1538,1542,1546,1556,1612,1616,1620,1624,1628,1638},{}},
    {"radius_30",61,61,42,30,false,{1029,1074,1078,1082,1086,1196,1200,1204,1208,1517,1684,1688,1692,1696,1806,1810,1814,1818,2005,2294,2298,2302,2306,2310,2416,2420,2424,2428,2554,2798,2900,2904,2908,2912,2916,2926,3022,3026,3030,3034,3038,3048,3164},{}},
    {"radius_4",9,9,4,4,true,{12,16,30,34},{8}},
    {"radius_40",81,81,62,40,false,{2179,2244,2248,2252,2256,2406,2410,2414,2418,2827,3054,3058,3062,3066,3216,3220,3224,3228,3335,3475,3659,3864,3868,3872,3876,3880,3983,4026,4030,4034,4038,4204,4307,4528,4631,4670,4674,4678,4682,4686,4696,4832,4836,4840,4844,4848,4858,4955,5014,5279,5940,5944,5948,5952,5956,5960,5964,5968,5972,5976,6102,6106,6110,6114,6118,6122,6126,6130,6134,6138},{}},
    {"radius_50",101,101,82,50,false,{3729,3814,3818,3822,3826,4016,4020,4024,4028,4537,4824,4828,4832,4836,5026,5030,5034,5038,5185,5345,5589,5834,5838,5842,5846,5850,5993,6036,6040,6044,6048,6254,6397,6658,6801,6840,6844,6848,6852,6856,6866,7042,7046,7050,7054,7058,7068,7205,7264,7609,8430,8434,8438,8442,8446,8450,8454,8458,8462,8466,8632,8636,8640,8644,8648,8652,8656,8660,8664,8668,9440,9444,9448,9452,9456,9460,9464,9468,9472,9476},{}},
    {"radius_55",111,111,92,55,false,{4654,4749,4753,4757,4761,4971,4975,4979,4983,5542,5859,5863,5867,5871,6081,6085,6089,6093,6260,6430,6704,6969,6973,6977,6981,6985,7148,7191,7195,7199,7203,7429,7592,7873,8036,8075,8079,8083,8087,8091,8101,8297,8301,8305,8309,8313,8323,8480,8539,8924,9825,9829,9833,9837,9841,9845,9849,9853,9857,9861,10047,10051,10055,10059,10063,10067,10071,10075,10079,10083,10935,10939,10943,10947,10951,10955,10959,10963,10967,10971},{}},
    {"radius_6",13,13,6,6,true,{40,44,48,66,70,74},{}},
    {"radius_8",17,17,8,8,true,{88,92,96,100,122,126,130,134,258,262,266,270},{288}},
    {"tall40",5,40,2,19,true,{31,41,81,91,131,141,181,191},{195}},
    {"tall41",5,41,2,20,true,{36,46,86,96,136,146,186,196},{200}},
    {"tall43",5,43,2,21,true,{41,51,91,101,141,151,191,201},{}},
    {"tall45",5,45,2,22,false,{46,56,96,106,146,156,196,206},{}},
    {"wide40",40,5,21,2,true,{56,60,64,68},{}},
    {"broad",40,43,21,21,false,{312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"detour",39,43,20,21,false,{304,327,331,335,339,405,409,413,417,616,717,721,725,729,795,799,800,801,803,807,928,1107,1111,1115,1119,1123,1185,1189,1193,1197,1279,1435,1493,1497,1501,1505,1509,1519,1571,1575,1579,1583,1587,1597},{}},
    {"narrow_broad",39,43,20,21,true,{304,327,331,335,339,405,409,413,417,616,717,721,725,729,795,799,803,807,928,1107,1111,1115,1119,1123,1185,1189,1193,1197,1279,1435,1493,1497,1501,1505,1509,1519,1571,1575,1579,1583,1587,1597},{}},
    {"obstacles_10",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"obstacles_16",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,184,186,188,190,192,194,312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"obstacles_17",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,184,186,188,190,192,194,244,312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"obstacles_20",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,184,186,188,190,192,194,244,246,248,250,312,336,340,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"obstacles_40",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,184,186,188,190,192,194,244,246,248,250,252,254,256,258,260,262,264,266,268,270,272,274,312,324,326,328,330,332,334,336,338,340,342,344,348,416,420,424,428,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
    {"obstacles_80",40,43,21,21,false,{164,166,168,170,172,174,176,178,180,182,184,186,188,190,192,194,244,246,248,250,252,254,256,258,260,262,264,266,268,270,272,274,312,324,326,328,330,332,334,336,338,340,342,344,346,348,350,352,354,404,406,408,410,412,414,416,418,420,422,424,426,428,430,432,434,484,486,488,490,492,494,496,498,500,502,504,506,508,510,512,514,564,566,568,570,572,574,576,578,632,736,740,744,748,816,820,824,828,952,1136,1140,1144,1148,1152,1216,1220,1224,1228,1312,1472,1532,1536,1540,1544,1548,1558,1612,1616,1620,1624,1628,1638},{}},
  };
  for(const auto& s:samples) {
    INFO(s.name);
    std::vector<area::RoomCell> cells(size_t(s.w)*s.h,area::RoomCell::Open);
    for(uint32_t y=0;y<s.h;++y)for(uint32_t x=0;x<s.w;++x)
      if(!x || !y || x+1==s.w || y+1==s.h)cells[size_t(y)*s.w+x]=area::RoomCell::Boundary;
    for(auto index:s.boundaries)cells[index]=area::RoomCell::Boundary;
    const auto result=area::traverseRoom(cells,s.w,s.h,s.x,s.y);
    CHECK(result.status==(s.success?area::RoomTraversalStatus::Complete:area::RoomTraversalStatus::Unenclosed));
    if(s.success) {
      std::vector<uint8_t> expected(cells.size(),1);
      for(auto index:s.holes)expected[index]=0;
      CHECK(result.reached==expected);
    }
  }
}

TEST_CASE("room traversal cannot certify an observation gap or open window edge") {
  std::vector<area::RoomCell> cells(9,area::RoomCell::Boundary);
  cells[4]=area::RoomCell::Open;cells[0]=area::RoomCell::Unobserved;
  auto r=area::traverseRoom(cells,3,3,1,1);
  CHECK(r.status==area::RoomTraversalStatus::Incomplete);
  CHECK(r.reached[0]==0);
  cells[0]=area::RoomCell::Open;
  CHECK(area::traverseRoom(cells,3,3,1,1).status==area::RoomTraversalStatus::Incomplete);
  CHECK(area::traverseRoom(cells,3,3,2,2).status==area::RoomTraversalStatus::Invalid);
  CHECK(area::traverseRoom(cells,2,3,1,1).status==area::RoomTraversalStatus::Invalid);
  CHECK(area::traverseRoom({},0,0,0,0).status==area::RoomTraversalStatus::Invalid);
}

// Exact native partition masks from room-shapes004402 (DF53.16), including
// terrain shapes, isolated occupancy flags, liquids and controlled door states.
TEST_CASE("room classification and traversal match native partition probes") {
  using S=area::RoomShape;using O=area::RoomOccupancy;using L=area::RoomLiquid;
  struct Sample {const char* name;S shape;O occupancy;L liquid;uint8_t depth;size_t point;
    std::vector<size_t> walls,doors;const char* expected;};
  const std::vector<Sample> samples{
    {"door_closed_dynamic",S::Floor,O::Dynamic,L::None,0,30,{0,1,2,3,4,5,6,7,8,9,12,17,18,21,26,27,35,36,39,44,45,48,53,54,57,62,63,66,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"000111110000111111000111111000111111000111111000111111000111111000111111000111111"},
    {"door_open_dynamic",S::Floor,O::Dynamic,L::None,0,30,{0,1,2,3,4,5,6,7,8,9,12,17,18,21,26,27,35,36,39,44,45,48,53,54,57,62,63,66,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"000111110000111111000111111000111111000111111000111111000111111000111111000111111"},
    {"door_open_none",S::Floor,O::None,L::None,0,30,{0,1,2,3,4,5,6,7,8,9,12,17,18,21,26,27,35,36,39,44,45,48,53,54,57,62,63,66,71,72,73,74,75,76,77,78,79,80},{12,16,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"door_open_passable",S::Floor,O::Passable,L::None,0,30,{0,1,2,3,4,5,6,7,8,9,12,17,18,21,26,27,35,36,39,44,45,48,53,54,57,62,63,66,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"000111110000111111000111111000111111000111111000111111000111111000111111000111111"},
    {"liquid_magma_1",S::Floor,O::None,L::Magma,1,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"liquid_magma_4",S::Floor,O::None,L::Magma,4,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"liquid_magma_7",S::Floor,O::None,L::Magma,7,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"liquid_water_1",S::Floor,O::None,L::Water,1,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"liquid_water_4",S::Floor,O::None,L::Water,4,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"liquid_water_5",S::Floor,O::None,L::Water,5,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"liquid_water_6",S::Floor,O::None,L::Water,6,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"liquid_water_7",S::Floor,O::None,L::Water,7,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"occ_dynamic",S::Floor,O::Dynamic,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"occ_floored",S::Floor,O::Floored,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"occ_impassable",S::Floor,O::Impassable,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"occ_none",S::Floor,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"occ_obstacle",S::Floor,O::Obstacle,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"occ_passable",S::Floor,O::Passable,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"occ_planned",S::Floor,O::Planned,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"occ_well",S::Floor,O::Well,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_boulder",S::Boulder,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_branch",S::Branch,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_brook_bed",S::BrookBed,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_brook_top",S::BrookTop,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_empty",S::Empty,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_endless_pit",S::EndlessPit,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_floor",S::Floor,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_fortification",S::Fortification,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_none",S::None,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_pebbles",S::Pebbles,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_ramp",S::Ramp,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_ramp_top",S::RampTop,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_sapling",S::Sapling,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_shrub",S::Shrub,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_stair_down",S::StairDown,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_stair_up",S::StairUp,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_stair_updown",S::StairUpDown,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_trunk_branch",S::TrunkBranch,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
    {"shape_twig",S::Twig,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"shape_wall",S::Wall,O::None,L::None,0,41,{0,1,2,3,4,5,6,7,8,9,14,17,18,23,26,27,32,35,36,41,44,45,50,53,54,59,62,63,68,71,72,73,74,75,76,77,78,79,80},{12,16,30,34},"111111000111111000111111000111111000111111000111111000111111000111111000111111000"},
  };
  for(const auto& s:samples) {
    INFO(s.name);
    std::vector<area::RoomCell> cells(81);
    for(size_t i=0;i<cells.size();++i) {
      const bool door=std::find(s.doors.begin(),s.doors.end(),i)!=s.doors.end();
      auto shape=std::find(s.walls.begin(),s.walls.end(),i)!=s.walls.end()?S::Wall:S::Floor;
      if(i==s.point)shape=s.shape;
      cells[i]=area::classifyRoomCell(shape,i==s.point?s.occupancy:(door?O::Dynamic:O::None),
          i==s.point?s.liquid:L::None,i==s.point?s.depth:0,door);
    }
    const auto r=area::traverseRoom(cells,9,9,4,4);
    CHECK(r.status==area::RoomTraversalStatus::Complete);
    REQUIRE(r.reached.size()==81);
    for(size_t i=0;i<81;++i)CHECK(r.reached[i]==uint8_t(s.expected[i]-'0'));
  }
}
TEST_CASE("unknown or inconsistent room facts cannot classify as observed terrain") {
  using S=area::RoomShape;using O=area::RoomOccupancy;using L=area::RoomLiquid;
  CHECK(area::classifyRoomCell(S::Unknown,O::None,L::None,0,false)==area::RoomCell::Unobserved);
  CHECK(area::classifyRoomCell(S::Floor,O::None,L::None,0,false,false)==area::RoomCell::Unobserved);
  CHECK(area::classifyRoomCell(S::Floor,O::None,L::Water,0,false)==area::RoomCell::Unobserved);
  CHECK(area::classifyRoomCell(S::Floor,O::None,L::None,1,false)==area::RoomCell::Unobserved);
  CHECK(area::classifyRoomCell(S::Floor,O::None,L::Water,8,false)==area::RoomCell::Unobserved);
}

// Native reader010036: deduplicated real observation windows and independently
// created native zone bounds/masks. RLE spans encode the captured reader output.
TEST_CASE("room compaction preserves native bounds masks and elevation") {
  struct Sample {const char* name;int32_t x,y,z;uint32_t w,h;area::Bounds expected;
    std::vector<std::pair<size_t,size_t>> spans;const char* mask;};
  const std::vector<Sample> samples{
    {"door_closed_dynamic",151,36,164,43,43,{171,53,6,9},{{751,5},{794,6},{837,6},{880,6},{923,6},{966,6},{1009,6},{1052,6},{1095,6}},"111110111111111111111111111111111111111111111111111111"},
    {"door_open_none",151,36,164,43,43,{168,53,9,9},{{748,8},{791,9},{834,9},{877,9},{920,9},{963,9},{1006,9},{1049,9},{1092,9}},"111111110111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"left20",151,36,164,43,43,{151,55,24,5},{{817,24},{860,24},{903,24},{946,24},{989,24}},"111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"liquid_magma_1",151,36,164,43,43,{168,53,6,9},{{748,6},{791,6},{834,6},{877,6},{920,6},{963,6},{1006,6},{1049,6},{1092,6}},"111111111111111111111111111111111111111111111111111111"},
    {"narrow_broad",151,36,164,43,43,{152,36,39,43},{{1,39},{44,39},{87,39},{130,39},{173,39},{216,39},{259,39},{302,39},{345,39},{388,39},{431,39},{474,39},{517,39},{560,39},{603,39},{646,39},{689,39},{732,39},{775,39},{818,39},{861,39},{904,39},{947,39},{990,39},{1033,39},{1076,39},{1119,39},{1162,39},{1205,39},{1248,39},{1291,39},{1334,39},{1377,39},{1420,39},{1463,39},{1506,39},{1549,39},{1592,39},{1635,39},{1678,39},{1721,39},{1764,39},{1807,39}},"111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"},
    {"source_bed",151,36,164,43,43,{169,56,5,5},{{878,5},{921,5},{964,5},{1007,5},{1050,5}},"1111111111111111111111111"},
    {"tall43",151,36,164,43,43,{170,36,5,43},{{19,5},{62,5},{105,5},{148,5},{191,5},{234,5},{277,5},{320,5},{363,5},{406,5},{449,5},{492,5},{535,5},{578,5},{621,5},{664,5},{707,5},{750,5},{793,5},{836,5},{879,5},{922,5},{965,5},{1008,5},{1051,5},{1094,5},{1137,5},{1180,5},{1223,5},{1266,5},{1309,5},{1352,5},{1395,5},{1438,5},{1481,5},{1524,5},{1567,5},{1610,5},{1653,5},{1696,5},{1739,5},{1782,5},{1825,5}},"11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"},
  };
  for(const auto& s:samples) {
    INFO(s.name);
    area::RoomTraversal t;t.status=area::RoomTraversalStatus::Complete;
    t.reached.assign(size_t(s.w)*s.h,0);
    for(auto span:s.spans)std::fill_n(t.reached.begin()+span.first,span.second,1);
    const auto result=area::compactRoom(s.x,s.y,s.z,s.w,s.h,t);
    REQUIRE(result.valid);
    CHECK(result.bounds.x==s.expected.x);CHECK(result.bounds.y==s.expected.y);
    CHECK(result.bounds.width==s.expected.width);CHECK(result.bounds.height==s.expected.height);
    REQUIRE(result.extents.size()==size_t(s.expected.width)*s.expected.height);
    for(size_t i=0;i<result.extents.size();++i) {
      CHECK(result.extents[i]==uint8_t(s.mask[i]-'0'));
      CHECK(result.contains(s.expected.x+int32_t(i%s.expected.width),s.expected.y+int32_t(i/s.expected.width),s.z)==(s.mask[i]=='1'));
    }
    CHECK_FALSE(result.contains(s.expected.x,s.expected.y,s.z+1));
    auto other=result;CHECK(area::sameRoom(result,other));
    other.z++;CHECK_FALSE(area::sameRoom(result,other));
    other=result;other.extents[0]^=1;CHECK_FALSE(area::sameRoom(result,other));
    t.status=area::RoomTraversalStatus::Incomplete;
    CHECK_FALSE(area::compactRoom(s.x,s.y,s.z,s.w,s.h,t).valid);
    t.status=area::RoomTraversalStatus::Unenclosed;
    CHECK_FALSE(area::compactRoom(s.x,s.y,s.z,s.w,s.h,t).valid);
  }
}
