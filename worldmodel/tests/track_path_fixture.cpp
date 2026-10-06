#include "wm/track_path.h"
#include <algorithm>
#include <iostream>
#include <limits>
#include <map>
#include <set>
#include <utility>
#include <string>
#include <tuple>

int main(int argc, char** argv) {
  if (argc==2 && std::string(argv[1])=="--site-route") {
    wm::TilePos start,goal,probe; int shape,occupancy,depth; bool loaded,hidden,magma;
    while (std::cin>>start.x>>start.y>>goal.x>>goal.y>>probe.x>>probe.y>>shape>>occupancy>>loaded>>hidden>>depth>>magma) {
      start.z=goal.z=probe.z=0;
      if (shape<0 || shape>255 || occupancy<0 || occupancy>255 || depth<0 || depth>255) return 2;
      const wm::TrackSiteFacts facts{static_cast<wm::TileShape>(shape),static_cast<wm::TrackSiteOccupancy>(occupancy),loaded,hidden,uint8_t(depth),magma};
      const auto result=wm::routeTrackConstruction(start,goal,{-7,-7,0},{7,7,0},[&](wm::TilePos p){
        const auto f=p==probe ? facts : wm::TrackSiteFacts{wm::TileShape::Floor,wm::TrackSiteOccupancy::None,true};
        return wm::TrackRoutingTile{f,false,f.shape==wm::TileShape::Wall || f.shape==wm::TileShape::Fortification,f.shape==wm::TileShape::Empty,f.shape==wm::TileShape::Ramp,true};
      });
      if (result.status==wm::TrackPathStatus::UnverifiedTerrain) { std::cout<<"unverified\n"; continue; }
      std::cout<<int(result.status)<<' '<<result.tiles.size();
      for (auto p:result.tiles) std::cout<<' '<<p.x<<' '<<p.y<<' '<<p.z;
      std::cout<<'\n';
    }
    return 0;
  }
  if (argc==2 && std::string(argv[1])=="--route3d") {
    wm::TilePos start,goal; int count;
    while (std::cin>>start.x>>start.y>>start.z>>goal.x>>goal.y>>goal.z>>count) {
      if (count<0 || count>675) return 2;
      std::map<std::tuple<int,int,int>,int> shapes;
      for (int i=0;i<count;++i) {
        int x,y,z,kind;if (!(std::cin>>x>>y>>z>>kind)) return 2;
        shapes[{x,y,z}]=kind;
      }
      const auto lookup=[&](wm::TilePos p) {
        if (p.x < -7 || p.x>7 || p.y < -7 || p.y>7 || p.z < -1 || p.z>1) return wm::TrackRoutingTile{};
        const auto it=shapes.find({p.x,p.y,p.z}); const int kind=it==shapes.end()?0:it->second;
        const wm::TileShape kinds[]={wm::TileShape::Floor,wm::TileShape::Ramp,wm::TileShape::RampTop,wm::TileShape::Wall,wm::TileShape::Empty};
        return wm::TrackRoutingTile{{kind>=0 && kind<5 ? kinds[kind] : wm::TileShape::Unknown,wm::TrackSiteOccupancy::None,true},false,kind==3,kind==4,kind==1,true};
      };
      const auto result=wm::routeTrackConstruction(start,goal,{-7,-7,-1},{7,7,1},lookup);
      std::cout<<int(result.status)<<' '<<result.tiles.size();
      for (auto p:result.tiles)std::cout<<' '<<p.x<<' '<<p.y<<' '<<p.z;
      std::cout<<'\n';
    }
    return 0;
  }
  if (argc==2 && (std::string(argv[1])=="--pending-plan" || std::string(argv[1])=="--ramp-plan")) {
    const bool rampMode=std::string(argv[1])=="--ramp-plan";
    int count, jobs, builtCount;
    while (std::cin>>count>>jobs>>builtCount) {
      if (count<0 || count>1024 || jobs<0 || jobs>1024 || builtCount<0 || builtCount>1024) return 2;
      std::vector<wm::TilePos> path(count);
      std::vector<wm::PendingTrack> existing(jobs);
      std::set<std::tuple<int,int,int>> ramps;
      for (auto& p : path) {
        if (!(std::cin>>p.x>>p.y>>p.z)) return 2;
        bool ramp=false; if (rampMode && !(std::cin>>ramp)) return 2;
        if (ramp) ramps.emplace(p.x,p.y,p.z);
      }
      for (auto& job : existing) {
        int mask;
        if (!(std::cin>>job.position.x>>job.position.y>>job.position.z>>job.buildingId>>mask) || mask<0 || mask>255) return 2;
        job.connections=uint8_t(mask);
        if (rampMode && !(std::cin>>job.ramp)) return 2;
      }
      std::vector<wm::TrackTerrain> completed(builtCount);
      for (auto& tile : completed) {
        int mask, kind;
        if (!(std::cin>>tile.position.x>>tile.position.y>>tile.position.z>>mask>>kind) || mask<0 || mask>255) return 2;
        tile.connections=uint8_t(mask);
        tile.kind=static_cast<wm::TrackTerrainKind>(kind);
        if (rampMode && !(std::cin>>tile.ramp)) return 2;
      }
      const auto plan=wm::planTrackConstruction(path,existing,completed,[&](wm::TilePos p){return ramps.contains({p.x,p.y,p.z});});
      if (!plan) { std::cout<<"invalid\n"; continue; }
      std::cout<<plan->newPieceCount;
      for (const auto& p : plan->pieces) {
        std::cout<<' '<<int(p.action)<<' '<<p.buildingId<<' '<<int(p.expectedConnections)<<' '<<int(p.connections)<<' '<<int(p.expectedTerrainConnections)<<' '<<int(p.expectedTerrainKind);
        if (rampMode) std::cout<<' '<<p.ramp<<' '<<p.expectedJobRamp<<' '<<p.expectedTerrainRamp;
      }
      std::cout<<'\n';
    }
    return 0;
  }
  if (argc==2 && std::string(argv[1])=="--pieces") {
    int count;
    while (std::cin>>count) {
      if (count<0 || count>1024) return 2;
      std::vector<wm::TilePos> path;
      std::set<std::tuple<int,int,int>> ramps;
      for (int i=0; i<count; ++i) {
        wm::TilePos p; int ramp;
        if (!(std::cin>>p.x>>p.y>>p.z>>ramp)) return 2;
        path.push_back(p); if (ramp) ramps.emplace(p.x,p.y,p.z);
      }
      auto pieces=wm::trackPathPieces(path,[&](wm::TilePos p){return ramps.contains({p.x,p.y,p.z});});
      if (!pieces) { std::cout<<"invalid\n"; continue; }
      std::cout<<pieces->size();
      for (const auto& piece : *pieces) std::cout<<' '<<int(piece.connections)<<' '<<piece.ramp;
      std::cout<<'\n';
    }
    return 0;
  }
  const auto open = [](wm::TilePos) { return true; };
  using Status = wm::TrackPathStatus;
  const auto missing=[](wm::TilePos){return wm::TrackRoutingTile{};};
  if (wm::routeTrackConstruction({0,0,0},{1,0,0},{0,0,0},{1,0,0},missing).status!=Status::UnverifiedTerrain) return 3;
  if (wm::routeTrackConstruction({0,0,0},{2,0,0},{0,0,0},{1,0,0},missing).status!=Status::InvalidInput) return 3;
  std::map<std::tuple<int,int,int>,int> samples;
  const auto snapshot=[&](wm::TilePos p) {
    ++samples[{p.x,p.y,p.z}];
    return wm::TrackRoutingTile{{wm::TileShape::Floor,wm::TrackSiteOccupancy::None,true},{},false,false};
  };
  if (wm::routeTrackConstruction({0,0,0},{2,0,0},{0,0,0},{2,0,0},snapshot).status!=Status::Found) return 3;
  for (const auto& [key,count] : samples) if (count!=1) return 3;
  // A known detour cannot establish native route ordering if an explored tile
  // could instead be traversable once its missing facts arrive.
  const auto partial=[](wm::TilePos p) {
    if (p==wm::TilePos{1,0,0}) return wm::TrackRoutingTile{};
    return wm::TrackRoutingTile{{wm::TileShape::Floor,wm::TrackSiteOccupancy::None,true},false,false,false};
  };
  const auto uncertain=wm::routeTrackConstruction({0,0,0},{2,0,0},{0,-1,0},{2,1,0},partial);
  if (uncertain.status!=Status::UnverifiedTerrain || !uncertain.tiles.empty()) return 3;
  for (int clearance=0;clearance<3;++clearance) {
    const auto rampSnapshot=[&](wm::TilePos p) {
      using Shape=wm::TileShape;
      const auto shape=p.z==0 ? (p.x==0?Shape::Ramp:Shape::Wall) : (p.x==0?Shape::RampTop:Shape::Floor);
      return wm::TrackRoutingTile{{shape,wm::TrackSiteOccupancy::None,true},
          clearance==0 ? std::optional<bool>{} : std::optional<bool>{clearance==2},shape==Shape::Wall,false,shape==Shape::Ramp};
    };
    const auto route=wm::routeTrackConstruction({0,0,0},{1,0,1},{0,0,0},{1,0,1},rampSnapshot);
    const auto expected=clearance==0?Status::UnverifiedTerrain:clearance==1?Status::Found:Status::NoPath;
    if (route.status!=expected || (clearance!=1 && !route.tiles.empty())) return 3;
  }
  // Display Wall is insufficient: brook beds share that display shape. Native
  // support false and unknown must differ from a verified supporting wall.
  for (int support=0;support<3;++support) {
    const auto snapshot=[&](wm::TilePos p) {
      using Shape=wm::TileShape;
      const auto shape=p.z==0 ? (p.x==0?Shape::Ramp:Shape::Wall) : (p.x==0?Shape::RampTop:Shape::Floor);
      const std::optional<bool> fact=support==0 ? std::optional<bool>{} : std::optional<bool>{support==2};
      return wm::TrackRoutingTile{{shape,wm::TrackSiteOccupancy::None,true},false,fact,false,shape==Shape::Ramp};
    };
    const auto route=wm::routeTrackConstruction({0,0,0},{1,0,1},{0,0,0},{1,0,1},snapshot);
    if (route.status!=(support==0?Status::UnverifiedTerrain:support==1?Status::NoPath:Status::Found)) return 3;
  }
  // Nominal RAMP can be a root/trunk slope excluded by native movement.
  // An absent classification must remain unknown rather than becoming a route.
  for (int nativeRamp=0;nativeRamp<3;++nativeRamp) {
    const auto snapshot=[&](wm::TilePos p) {
      using Shape=wm::TileShape;
      const auto shape=p.z==0 ? (p.x==0?Shape::Ramp:Shape::Wall) : (p.x==0?Shape::RampTop:Shape::Floor);
      const std::optional<bool> ramp=nativeRamp==0 ? std::optional<bool>{} : std::optional<bool>{nativeRamp==2};
      return wm::TrackRoutingTile{{shape,wm::TrackSiteOccupancy::None,true},false,shape==Shape::Wall,false,ramp};
    };
    const auto route=wm::routeTrackConstruction({0,0,0},{1,0,1},{0,0,0},{1,0,1},snapshot);
    if (route.status!=(nativeRamp==0?Status::UnverifiedTerrain:nativeRamp==1?Status::NoPath:Status::Found)) return 3;
  }
  // Native elevation eligibility uses nonzero source walkability, except at
  // the draft's starting tile. Same-z and destination facts do not gate it.
  for (int state=0;state<3;++state) {
    const std::optional<bool> walkable=state==0 ? std::optional<bool>{} : std::optional<bool>{state==2};
    const auto snapshot=[&](wm::TilePos p) {
      using Shape=wm::TileShape;
      const auto shape=p.z==0 ? (p.x==0?Shape::Floor:p.x==1?Shape::Ramp:Shape::Wall)
          : (p.x==1?Shape::RampTop:p.x>=2?Shape::Floor:Shape::Wall);
      return wm::TrackRoutingTile{{shape,wm::TrackSiteOccupancy::None,true},false,
          shape==Shape::Wall,false,shape==Shape::Ramp,walkable};
    };
    const auto expected=state==0?Status::UnverifiedTerrain:state==1?Status::NoPath:Status::Found;
    if (wm::routeTrackConstruction({0,0,0},{2,0,1},{0,0,0},{3,0,1},snapshot).status!=expected) return 3;
    if (wm::routeTrackConstruction({3,0,1},{0,0,0},{0,0,0},{3,0,1},snapshot).status!=expected) return 3;
    for (const auto endpoints : {std::pair{wm::TilePos{1,0,0},wm::TilePos{2,0,1}},
                                 std::pair{wm::TilePos{2,0,1},wm::TilePos{0,0,0}}}) {
      if (wm::routeTrackConstruction(endpoints.first,endpoints.second,{0,0,0},{3,0,1},snapshot).status!=Status::Found) return 3;
    }
  }
  const auto excludedRamp=[](wm::TilePos p) {
    return wm::TrackMovementFacts{p.z==0?wm::TileShape::Ramp:wm::TileShape::RampTop,true,false,false,false,false};
  };
  if (wm::trackLinkedTile({0,0,0},excludedRamp) || wm::trackLinkedTile({0,0,1},excludedRamp)) return 3;
  if (wm::routeFlatTrackPath({0,0,0},{1,0,1},{-2,-2,0},{2,2,1},open).status != Status::InvalidInput) return 3;
  if (wm::routeFlatTrackPath({0,0,0},{3,0,0},{-2,-2,0},{2,2,0},open).status != Status::InvalidInput) return 3;
  if (wm::routeFlatTrackPath({0,0,0},{1,0,0},{-2,-2,0},{2,2,0},{}).status != Status::InvalidInput) return 3;
  const auto isolated = wm::routeFlatTrackPath({0,0,0},{2,0,0},{0,0,0},{2,0,0},
      [](wm::TilePos p) { return p.x != 1; });
  if (isolated.status != Status::NoPath || !isolated.tiles.empty()) return 3;
  const auto high = std::numeric_limits<int32_t>::max();
  const auto low = std::numeric_limits<int32_t>::min();
  int lookups=0;
  const auto boundaryFacts=[&](wm::TilePos p) {
    ++lookups;
    return wm::TrackMovementFacts{p.z==high?wm::TileShape::Ramp:wm::TileShape::RampTop,true,false,false,false,p.z==high};
  };
  if (wm::trackLinkedTile({0,0,high},boundaryFacts) || lookups!=1) return 3;
  lookups=0;
  if (wm::trackLinkedTile({0,0,low},boundaryFacts) || lookups!=1) return 3;
  if (wm::trackLinkedTile({0,0,0},{}) || wm::trackMovementConnected({0,0,0},{1,0,0},{})) return 3;
  const auto absent=[](wm::TilePos){return wm::TrackMovementFacts{};};
  if (wm::trackMovementConnected({0,0,0},{1,0,0},absent) || wm::trackLinkedTile({0,0,0},absent)) return 3;
  // Coordinate-boundary regression: no arithmetic may overflow before lookup.
  for (auto level : {low,high-1}) {
    const auto rampFacts=[&](wm::TilePos p) {
      using Shape=wm::TileShape;
      return wm::TrackMovementFacts{p.z==level ? (p.x==0?Shape::Ramp:Shape::Wall)
                                                            : (p.x==0?Shape::RampTop:Shape::Floor),true,false,p.x==1 && p.z==level,false,p.x==0 && p.z==level};
    };
    const wm::TilePos a{0,0,level},b{1,0,level+1},top{0,0,level+1};
    if (!wm::trackMovementConnected(a,b,rampFacts) || !wm::trackMovementConnected(b,a,rampFacts)) return 3;
    if (wm::trackLinkedTile(a,rampFacts)!=top || wm::trackLinkedTile(top,rampFacts)!=a) return 3;
    if (wm::trackMovementConnected(a,top,rampFacts) || wm::trackMovementConnected(a,{1,1,level},rampFacts)) return 3;
  }
  const wm::TilePos raisedStart{0,0,high-1},raisedGoal{1,0,high};
  const auto directed=[&](wm::TilePos a,wm::TilePos b){return a==raisedStart && b==raisedGoal;};
  const auto raised=wm::routeTrackPath(raisedStart,raisedGoal,{0,0,high-1},{1,0,high},{open,directed,{}});
  if (raised.status!=Status::Found || raised.tiles!=std::vector<wm::TilePos>{raisedStart,raisedGoal}) return 3;
  if (wm::routeTrackPath(raisedStart,raisedGoal,{0,0,high-1},{1,0,high},{open,{},{}}).status!=Status::InvalidInput) return 3;
  const auto edge = wm::routeFlatTrackPath({high,0,0},{high-1,0,0},
      {high-1,0,0},{high,0,0},open);
  if (edge.status != Status::Found || edge.tiles != std::vector<wm::TilePos>{{high,0,0},{high-1,0,0}}) return 3;
  int x, y, count;
  while (std::cin >> x >> y >> count) {
    if (count < 0 || count > 225) return 2;
    std::set<std::pair<int, int>> walls;
    for (int i = 0, a, b; i < count; ++i) {
      if (!(std::cin >> a >> b)) return 2;
      walls.emplace(a, b);
    }
    const auto result = wm::routeFlatTrackPath({0,0,0}, {x,y,0}, {-7,-7,0}, {7,7,0},
        [&](wm::TilePos p) { return !walls.contains({p.x,p.y}); });
    std::cout << int(result.status) << ' ' << result.tiles.size();
    for (auto p : result.tiles) std::cout << ' ' << p.x << ' ' << p.y << ' ' << p.z;
    std::cout << '\n';
  }
}
