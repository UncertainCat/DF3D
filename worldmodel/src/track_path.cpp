#include "wm/track_path.h"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <limits>
#include <map>
#include <set>
#include <utility>
#include <tuple>

namespace wm {
bool trackMovementConnected(TilePos from, TilePos to, const TrackMovementLookup& lookup) {
  const auto dx=int64_t(to.x)-from.x,dy=int64_t(to.y)-from.y,dz=int64_t(to.z)-from.z;
  if (!lookup || std::abs(dx)+std::abs(dy)!=1 || std::abs(dz)>1) return false;
  const auto a=lookup(from),b=lookup(to);
  if (!a.loaded || !b.loaded) return false;
  if (dz==0) return true; // Site eligibility is checked separately by the search.
  const auto ramp=dz>0 ? a : b;
  const auto upper=lookup(dz>0 ? TilePos{from.x,from.y,to.z} : TilePos{to.x,to.y,from.z});
  const auto support=lookup(dz>0 ? TilePos{to.x,to.y,from.z} : TilePos{from.x,from.y,to.z});
  return ramp.movementRamp && upper.loaded && support.loaded &&
      !upper.clearanceBlocked &&
      (upper.shape==TileShape::RampTop || (dz>0 && upper.open)) && support.support;
}

std::optional<TilePos> trackLinkedTile(TilePos position, const TrackMovementLookup& lookup) {
  if (!lookup) return std::nullopt;
  const auto here=lookup(position);
  if (!here.loaded) return std::nullopt;
  const bool ramp=here.movementRamp;
  if (ramp) {
    if (position.z==std::numeric_limits<int32_t>::max()) return std::nullopt;
  } else if (here.shape==TileShape::RampTop || here.open) {
    if (position.z==std::numeric_limits<int32_t>::min()) return std::nullopt;
  } else return std::nullopt;
  const TilePos partner{position.x,position.y,position.z+(ramp?1:-1)};
  const auto other=lookup(partner);
  if (!other.loaded) return std::nullopt;
  if (ramp ? (other.shape==TileShape::RampTop || other.open)
           : other.movementRamp) return partner;
  return std::nullopt;
}

TrackTileEligibility trackSiteEligibility(const TrackSiteFacts& facts, bool endpoint) {
  using Result = TrackTileEligibility;
  if (!facts.loaded || (facts.hidden && !endpoint)) return Result::Ineligible;
  if (facts.endpointOnly && !endpoint) return Result::Ineligible;
  if (facts.liquidDepth > 7) return Result::Unverified;
  if (facts.liquidDepth > 1 || (facts.magma && facts.liquidDepth > 0)) return Result::Ineligible;
  switch (facts.occupancy) {
    case TrackSiteOccupancy::None:
    case TrackSiteOccupancy::PendingTrack: break;
    case TrackSiteOccupancy::BlockingBuilding: return Result::Ineligible;
    default: return Result::Unverified;
  }
  switch (facts.shape) {
    case TileShape::Empty:
    case TileShape::Floor:
    case TileShape::Ramp:
    case TileShape::RampTop:
    case TileShape::StairUp:
    case TileShape::StairDown:
    case TileShape::StairUpDown:
    case TileShape::Shrub:
    case TileShape::Boulder:
    case TileShape::Pebbles:
    case TileShape::TreeBranch:
    case TileShape::Sapling: return Result::Eligible;
    case TileShape::Wall:
    case TileShape::TreeTrunk:
    case TileShape::Fortification: return Result::Ineligible;
    default: return Result::Unverified;
  }
}

std::optional<TrackConstructionPlan> planTrackConstruction(
    std::span<const TilePos> path, std::span<const PendingTrack> existing,
    std::span<const TrackTerrain> terrain, const std::function<bool(TilePos)>& isRamp) {
  const auto pieces = trackPathPieces(path, isRamp);
  if (!pieces) return std::nullopt;
  using Key = std::tuple<int32_t,int32_t,int32_t>;
  std::map<Key, PendingTrack> jobs;
  std::set<int32_t> ids;
  for (const auto& job : existing) {
    if (job.buildingId < 0 || job.connections == 0 || (job.connections & ~15) != 0 ||
        !ids.insert(job.buildingId).second ||
        !jobs.emplace(Key{job.position.x,job.position.y,job.position.z},job).second)
      return std::nullopt;
  }
  std::map<Key, TrackTerrain> built;
  for (const auto& tile : terrain) {
    const Key key{tile.position.x,tile.position.y,tile.position.z};
    if (tile.connections == 0 || (tile.connections & ~15) != 0 ||
        (tile.kind != TrackTerrainKind::Carved && tile.kind != TrackTerrainKind::Constructed) ||
        !built.emplace(key,tile).second) return std::nullopt;
    const auto pending = jobs.find(key);
    if (pending != jobs.end() && ((pending->second.connections & tile.connections) != tile.connections || pending->second.ramp != tile.ramp))
      return std::nullopt;
  }
  TrackConstructionPlan plan;
  plan.pieces.reserve(pieces->size());
  for (const auto& piece : *pieces) {
    TrackPlanPiece step{piece.position,TrackPlanAction::Create,-1,0,piece.connections};
    step.ramp = piece.ramp;
    const auto tile = built.find({piece.position.x,piece.position.y,piece.position.z});
    if (tile != built.end()) {
      if (tile->second.ramp != piece.ramp) return std::nullopt;
      step.expectedTerrainRamp = tile->second.ramp;
      step.expectedTerrainConnections = tile->second.connections;
      step.expectedTerrainKind = tile->second.kind;
      step.connections |= step.expectedTerrainConnections;
    }
    const auto found = jobs.find({piece.position.x,piece.position.y,piece.position.z});
    if (found == jobs.end()) {
      ++plan.newPieceCount;
    } else {
      if (found->second.ramp != piece.ramp) return std::nullopt;
      step.expectedJobRamp = found->second.ramp;
      step.buildingId = found->second.buildingId;
      step.expectedConnections = found->second.connections;
      step.connections |= step.expectedConnections;
      step.action = step.connections == step.expectedConnections
          ? TrackPlanAction::Unchanged : TrackPlanAction::Update;
    }
    plan.pieces.push_back(step);
  }
  return plan;
}

std::optional<std::vector<TrackPathPiece>> trackPathPieces(
    std::span<const TilePos> path, const std::function<bool(TilePos)>& isRamp) {
  if (path.size() < 2 || !isRamp) return std::nullopt;
  std::vector<TrackPathPiece> pieces;
  std::set<std::tuple<int32_t,int32_t,int32_t>> seen;
  pieces.reserve(path.size());
  for (const auto p : path) {
    if (!seen.emplace(p.x,p.y,p.z).second) return std::nullopt;
    pieces.push_back({p,0,isRamp(p)});
  }
  for (size_t i=1; i<path.size(); ++i) {
    const auto a=path[i-1], b=path[i];
    const auto dx=int64_t(b.x)-a.x, dy=int64_t(b.y)-a.y, dz=int64_t(b.z)-a.z;
    if (std::abs(dx)+std::abs(dy)!=1 || std::abs(dz)>1) return std::nullopt;
    if ((dz>0 && !pieces[i-1].ramp) || (dz<0 && !pieces[i].ramp)) return std::nullopt;
    const uint8_t forward=dx>0 ? TrackEast : dx<0 ? TrackWest : dy>0 ? TrackSouth : TrackNorth;
    const uint8_t backward=dx>0 ? TrackWest : dx<0 ? TrackEast : dy>0 ? TrackNorth : TrackSouth;
    pieces[i-1].connections |= forward;
    pieces[i].connections |= backward;
  }
  return pieces;
}
namespace {
using Point = std::array<int32_t, 3>;
Point point(TilePos p) { return {p.x,p.y,p.z}; }
TilePos tile(Point p) { return {p[0],p[1],p[2]}; }
struct Entry { int64_t priority; Point point; };
struct Frontier {
  std::vector<Entry> rows;
  bool push(Entry row) {
    // Native insertion has an 80,000-entry cap. Never return a partial path.
    if (rows.size() >= 80000) return false;
    auto i = rows.size(); rows.push_back(row);
    while (i > 0) {
      const auto parent = i / 2;
      if (rows[parent].priority <= rows[i].priority) break;
      std::swap(rows[parent], rows[i]); i = parent;
    }
    return true;
  }
  void erase(size_t i) {
    const auto last = rows.back(); rows.pop_back();
    if (i >= rows.size()) return;
    rows[i] = last;
    // Native root is zero but its children are 2*i and 2*i+1. Preserve its
    // exact erase/tie behavior; a standard heap changes recorded route choices.
    while (2 * i < rows.size()) {
      const auto left = 2 * i, right = left + 1;
      size_t child;
      if (rows[left].priority < rows[i].priority) {
        child = right < rows.size() && rows[right].priority < rows[left].priority
            ? right : left;
      } else {
        if (right >= rows.size()) break;
        child = right;
      }
      std::swap(rows[i], rows[child]); i = child;
    }
  }
};
}

TrackPathResult routeTrackPath(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum, const TrackRouteRules& rules) {
  const auto inside = [&](TilePos p) {
    return p.x >= minimum.x && p.x <= maximum.x && p.y >= minimum.y &&
        p.y <= maximum.y && p.z >= minimum.z && p.z <= maximum.z;
  };
  if (!rules.eligible || !rules.connected || minimum.x > maximum.x || minimum.y > maximum.y ||
      minimum.z > maximum.z || !inside(start) || !inside(goal))
    return {TrackPathStatus::InvalidInput, {}};
  if (start == goal || !rules.eligible(start) || !rules.eligible(goal)) return {};
  const auto from=point(start), to=point(goal);
  const auto heuristic = [&](Point p) -> int64_t {
    const auto x=std::abs(int64_t(p[0])-start.x), y=std::abs(int64_t(p[1])-start.y), z=std::abs(int64_t(p[2])-start.z);
    return 256 * std::max({x,y,z}) + 106 * std::min({x,y,z});
  };
  Frontier queue;
  queue.push({heuristic(to), to});
  std::map<Point, int64_t> costs{{to, 0}};
  std::map<Point, Point> parent;
  std::set<Point> closed;
  const auto markLinked = [&](Point p) {
    if (!rules.linked) return;
    const auto other=rules.linked(tile(p));
    // Native tags an unseen partner without queuing or assigning a predecessor.
    // Already visited/queued partners retain their own search state.
    if (other && inside(*other) && !costs.contains(point(*other))) closed.insert(point(*other));
  };
  markLinked(to);
  while (!queue.rows.empty()) {
    const auto current = queue.rows.front().point; queue.erase(0);
    closed.insert(current);
    if (current == from) {
      TrackPathResult result{TrackPathStatus::Found, {start}};
      for (auto p = current; p != to;) {
        p = parent.at(p); result.tiles.push_back(tile(p));
      }
      return result;
    }
    for (int dx=-1;dx<=1;++dx) for (int dy=-1;dy<=1;++dy) {
      if ((dx==0)==(dy==0)) continue;
      for (int dz=-1;dz<=1;++dz) {
      // Compute in wider integers before narrowing, including at int32 edges.
      const int64_t x=int64_t(current[0])+dx, y=int64_t(current[1])+dy, z=int64_t(current[2])+dz;
      if (x<minimum.x || x>maximum.x || y<minimum.y || y>maximum.y || z<minimum.z || z>maximum.z) continue;
      const Point next{int32_t(x),int32_t(y),int32_t(z)};
      if (closed.contains(next) || !rules.eligible(tile(next)) || !rules.connected(tile(next),tile(current))) continue;
      const auto score = costs.at(current) + 256;
      const auto prior = costs.find(next);
      if (prior != costs.end() && prior->second <= score) { markLinked(next); continue; }
      if (prior != costs.end()) {
        for (auto i = queue.rows.size(); i > 0; --i) {
          if (queue.rows[i-1].point == next) { queue.erase(i-1); break; }
        }
      }
      costs[next] = score; parent[next] = current;
      if (!queue.push({score + heuristic(next), next}))
        return {TrackPathStatus::FrontierLimit, {}};
      markLinked(next);
      }
    }
  }
  return {};
}
TrackPathResult routeTrackConstruction(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum,
    const std::function<TrackRoutingTile(TilePos)>& lookup) {
  if (!lookup) return {TrackPathStatus::InvalidInput,{}};
  const auto inside=[&](TilePos p) {
    return p.x>=minimum.x && p.x<=maximum.x && p.y>=minimum.y && p.y<=maximum.y &&
        p.z>=minimum.z && p.z<=maximum.z;
  };
  std::map<std::tuple<int32_t,int32_t,int32_t>,TrackRoutingTile> cache;
  bool unverified=false;
  const auto read=[&](TilePos p) {
    if (!inside(p)) return TrackRoutingTile{};
    const auto key=std::tuple{p.x,p.y,p.z};
    auto it=cache.find(key);
    if (it==cache.end()) it=cache.emplace(key,lookup(p)).first;
    if (!it->second.site.loaded || it->second.site.shape==TileShape::Unknown) unverified=true;
    return it->second;
  };
  const TrackMovementLookup movement=[&](TilePos p) {
    const auto tile=read(p);
    return TrackMovementFacts{tile.site.shape,tile.site.loaded,tile.clearanceBlocked.value_or(true),
        tile.support.value_or(false),tile.open.value_or(false),tile.movementRamp.value_or(false)};
  };
  TrackRouteRules rules;
  rules.eligible=[&](TilePos p) {
    const auto result=trackSiteEligibility(read(p).site,p==start || p==goal);
    if (result==TrackTileEligibility::Unverified) unverified=true;
    return result==TrackTileEligibility::Eligible;
  };
  rules.connected=[&](TilePos a,TilePos b) {
    if (a.z!=b.z) {
      const auto ramp=read(a.z<b.z ? a : b);
      // Missing clearance matters only when this is a possible ramp edge.
      if (ramp.site.loaded && ramp.site.shape==TileShape::Ramp && !ramp.movementRamp) unverified=true;
      if (ramp.site.loaded && ramp.movementRamp.value_or(false)) {
        const TilePos upper=a.z<b.z ? TilePos{a.x,a.y,b.z} : TilePos{b.x,b.y,a.z};
        const auto tile=read(upper);
        if (inside(upper) && tile.site.loaded && !tile.clearanceBlocked) unverified=true;
        if (a.z<b.z && tile.site.loaded && tile.site.shape!=TileShape::RampTop && !tile.open) unverified=true;
        const TilePos below=a.z<b.z ? TilePos{b.x,b.y,a.z} : TilePos{a.x,a.y,b.z};
        const auto support=read(below);
        if (inside(below) && support.site.loaded && !support.support) unverified=true;
      }
    }
    const bool connected=trackMovementConnected(a,b,movement);
    if (!connected || a.z==b.z || a==start) return connected;
    // Native skips source eligibility at the route start. Other elevation
    // sources require a nonzero walkability group; equality is not tested.
    const auto source=read(a);
    if (!source.walkable) unverified=true;
    return source.walkable.value_or(false);
  };
  rules.linked=[&](TilePos p){
    const auto here=read(p);
    if (here.site.loaded && here.site.shape==TileShape::Ramp && !here.movementRamp) unverified=true;
    if (here.site.loaded && here.site.shape!=TileShape::Ramp &&
        here.site.shape!=TileShape::RampTop && !here.open) unverified=true;
    if (here.site.loaded && here.movementRamp.value_or(false) && p.z<maximum.z) {
      const auto upper=read({p.x,p.y,p.z+1});
      if (upper.site.loaded && upper.site.shape!=TileShape::RampTop && !upper.open) unverified=true;
    }
    if (here.site.loaded && (here.site.shape==TileShape::RampTop || here.open.value_or(false)) && p.z>minimum.z) {
      const auto below=read({p.x,p.y,p.z-1});
      if (below.site.loaded && below.site.shape==TileShape::Ramp && !below.movementRamp) unverified=true;
    }
    return trackLinkedTile(p,movement);
  };
  const auto result=routeTrackPath(start,goal,minimum,maximum,rules);
  if (result.status==TrackPathStatus::InvalidInput || result.status==TrackPathStatus::FrontierLimit) return result;
  return unverified ? TrackPathResult{TrackPathStatus::UnverifiedTerrain,{}} : result;
}

TrackPathResult routeFlatTrackPath(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum, const std::function<bool(TilePos)>& eligible) {
  if (start.z!=goal.z || minimum.z>maximum.z || start.z<minimum.z || start.z>maximum.z)
    return {TrackPathStatus::InvalidInput,{}};
  minimum.z=maximum.z=start.z;
  return routeTrackPath(start,goal,minimum,maximum,{eligible,[](TilePos,TilePos){return true;},{}});
}
} // namespace wm
