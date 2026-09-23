#include "df3d_world.h"
#include "../../../../schema/cpp/track_route.h"
namespace df3d_godot {
using namespace godot;
// --- commands ---

namespace {
// Rect2i (position + size, tiles) -> inclusive wm::TileRect on z. False
// when the size is not positive.
bool toTileRect(const Rect2i& rect, int z, wm::TileRect& out) {
    if (rect.size.x <= 0 || rect.size.y <= 0) return false;
    out.x1 = rect.position.x;
    out.y1 = rect.position.y;
    out.x2 = rect.position.x + rect.size.x - 1;
    out.y2 = rect.position.y + rect.size.y - 1;
    out.z = z;
    return true;
}

bool toOptionalBool(int v, wm::OptionalBool& out) {
    if (v < 0 || v > static_cast<int>(wm::OptionalBool::Clear)) return false;
    out = static_cast<wm::OptionalBool>(v);
    return true;
}
}  // namespace

int64_t Df3dWorld::send_set_pause(bool paused) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    const uint64_t seq = source_.sendSetPause(paused);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::designate_dig(const Rect2i& rect, int z, int kind, int priority, bool marker, int mining_mode, int max_z) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::TileRect r;
    if (!toTileRect(rect, z, r)) {
        lastError_ = "designate_dig: rect size must be positive";
        return 0;
    }
    if (kind < 0 || kind > static_cast<int>(wm::DigKind::Mark)) {
        lastError_ = "designate_dig: unknown kind";
        return 0;
    }
    if (priority < wm::kMinDigPriority || priority > wm::kMaxDigPriority) {
        lastError_ = "designate_dig: priority outside 1..7";
        return 0;
    }
    if(mining_mode<0 || mining_mode>3) { lastError_="invalid mining mode"; return 0; }
    const uint64_t seq = source_.sendDesignateDig(r, static_cast<wm::DigKind>(kind),
                                                   static_cast<uint8_t>(priority), marker, static_cast<uint8_t>(mining_mode), max_z);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::designate_stairs(const Rect2i& rect, int z1, int z2, int priority, bool marker) {
    wm::TileRect r;
    if(!source_.live() || !toTileRect(rect,std::min(z1,z2),r) || priority<1 || priority>7) { lastError_="invalid stairs request or not attached"; return 0; }
    const auto seq=source_.sendDesignateDig(r,wm::DigKind::StairsSpan,uint8_t(priority),marker,0,std::max(z1,z2));
    if(!seq) lastError_=String(source_.error().c_str());
    return int64_t(seq);
}
Array Df3dWorld::preview_track(const Rect2i& rect, int z, bool from_east, bool from_south, int end_z) const {
    Array out; wm::TileRect r;
    if(!toTileRect(rect,z,r)) return out;
    const auto size=source_.model().mapSize();
    const df3d::track::Point start{from_east?r.x2:r.x1,from_south?r.y2:r.y1,z};
    const df3d::track::Point end{from_east?r.x1:r.x2,from_south?r.y1:r.y2,end_z==-1?z:end_z};
    const auto lookup=[&](df3d::track::Point p) {
        df3d::track::Terrain result;
        if(p.x<=0 || p.y<=0 || p.x>=size.x-1 || p.y>=size.y-1 || p.z<0 || p.z>=size.z) return result;
        const auto t=source_.model().tileAt({p.x,p.y,p.z});
        if(!t) return result;
        const bool stone=t->materialKind==wm::MaterialKind::Stone || t->materialKind==wm::MaterialKind::Mineral || t->materialKind==wm::MaterialKind::Gem;
        result.ramp=t->shape==wm::TileShape::Ramp;
        result.rampTop=t->shape==wm::TileShape::RampTop;
        result.open=t->trackOpen;
        result.support=t->trackSupport;
        result.eligible=!(t->flags & wm::kTileHidden) && stone && (t->shape==wm::TileShape::Floor || result.ramp || t->shape==wm::TileShape::Boulder || t->shape==wm::TileShape::Pebbles);
        result.clearanceBlocked=t->trackClearanceBlocked;
        result.horizontalBlocked=t->trackHorizontalBlocked;
        return result;
    };
    const auto path=df3d::track::route(start,end,[&](df3d::track::Point p){return lookup(p).eligible;},
        [&](df3d::track::Point from,df3d::track::Point to) {
            return (from==start || !lookup(from).horizontalBlocked) && df3d::track::connected(from,to,lookup);
        });
    for(const auto& t:path) {
        Dictionary d; const Vector3i tile(t.point.x,t.point.y,t.point.z);
        d["tile"]=tile; d["track"]=int(t.mask); d["height"]=selection_height(tile); out.push_back(d);
    }
    return out;
}

int64_t Df3dWorld::designate_track(const Rect2i& rect, int z, bool from_east, bool from_south, int priority, bool marker, int end_z) {
    wm::TileRect r;
    if(!source_.live() || !toTileRect(rect,z,r) || priority<1 || priority>7) { lastError_="invalid track request or not attached"; return 0; }
    const auto seq=source_.sendDesignateSmooth(r,wm::SmoothKind::Track,uint8_t(priority),marker,from_east,from_south,-1,end_z);
    if(!seq) lastError_=String(source_.error().c_str());
    return int64_t(seq);
}

int64_t Df3dWorld::designate_smooth(const Rect2i& rect, int z, int kind, int priority, bool marker, int max_z) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::TileRect r;
    if (!toTileRect(rect, z, r)) {
        lastError_ = "designate_smooth: rect size must be positive";
        return 0;
    }
    if (kind < 0 || kind > static_cast<int>(wm::SmoothKind::Track)) {
        lastError_ = "designate_smooth: unknown kind";
        return 0;
    }
    if(priority<1 || priority>7) { lastError_="priority outside 1..7"; return 0; }
    const uint64_t seq = source_.sendDesignateSmooth(r, static_cast<wm::SmoothKind>(kind), static_cast<uint8_t>(priority), marker, false, false, max_z);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::designate_chop(const Rect2i& rect, int z, bool enable, int priority, bool marker, int max_z) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::TileRect r;
    if (!toTileRect(rect, z, r)) {
        lastError_ = "designate_chop: rect size must be positive";
        return 0;
    }
    if(priority<1 || priority>7) { lastError_="priority outside 1..7"; return 0; }
    const uint64_t seq = source_.sendDesignateChop(r, enable, static_cast<uint8_t>(priority), marker, max_z);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::designate_gather(const Rect2i& rect, int z, bool enable, int priority, bool marker, int max_z) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::TileRect r;
    if (!toTileRect(rect, z, r)) {
        lastError_ = "designate_gather: rect size must be positive";
        return 0;
    }
    if(priority<1 || priority>7) { lastError_="priority outside 1..7"; return 0; }
    const uint64_t seq = source_.sendDesignateGather(r, enable, static_cast<uint8_t>(priority), marker, max_z);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::set_item_flags(int64_t item, int forbidden, int dump, int melt) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::OptionalBool f, d, m;
    if (item <= 0 || item > 0xFFFFFFFFll || !toOptionalBool(forbidden, f) || !toOptionalBool(dump, d) ||
        !toOptionalBool(melt, m)) {
        lastError_ = "set_item_flags: bad item id or flag value";
        return 0;
    }
    const uint64_t seq = source_.sendSetItemFlags(static_cast<wm::ItemId>(item), f, d, m);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

int64_t Df3dWorld::set_building_flags(int64_t building, int forbidden) {
    if (!source_.live()) {
        lastError_ = "not attached to the live mirror";
        return 0;
    }
    wm::OptionalBool f;
    if (building <= 0 || building > 0xFFFFFFFFll || !toOptionalBool(forbidden, f)) {
        lastError_ = "set_building_flags: bad building id or flag value";
        return 0;
    }
    const uint64_t seq = source_.sendSetBuildingFlags(static_cast<wm::BuildingId>(building), f);
    if (!seq) lastError_ = String(source_.error().c_str());
    return static_cast<int64_t>(seq);
}

Array Df3dWorld::drain_command_results() {
    Array out;
    for (const wm::CommandResult& r : source_.model().drainCommandResults()) {
        Dictionary d;
        d["seq"] = static_cast<int64_t>(r.seq);
        d["status"] = static_cast<int64_t>(r.status);
        d["message"] = String(r.message.c_str());
        d["tick"] = static_cast<int64_t>(r.tick);
        out.push_back(d);
    }
    return out;
}

}
