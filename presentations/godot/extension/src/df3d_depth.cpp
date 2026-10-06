#include "df3d_world.h"
#include "df3d_mesher/depth_scene.h" // Independent diagnostic oracle, never called by poll().

namespace df3d_godot {
namespace mesher=df3d::mesher;

godot::Dictionary Df3dWorld::buffered_state() const {
    godot::Dictionary out;
    out["enabled"]=bool(source_.live());
    out["delay_ms"]=source_.delaySeconds()*1000;
    out["display_age_ms"]=(nowSeconds()-source_.displayedCapturedAt())*1000;
    if(source_.live()) {
        const auto stats=source_.liveStats();
        out["queued_frames"]=int64_t(stats.queuedFrames);
        out["published"]=int64_t(stats.published);
        out["presentation_coalesced"]=int64_t(stats.coalesced);
        const auto& source=stats.sourcePublications;
        out["source_publication_index"]=int64_t(source.lastIndex);
        out["source_publications_accepted"]=int64_t(source.accepted);
        out["source_publications_missed"]=int64_t(source.missed);
        out["source_gap_events"]=int64_t(source.gapEvents);
        out["source_largest_gap"]=int64_t(source.largestGap);
        out["source_read_failures"]=int64_t(source.readFailures);
        out["source_rejected_reads"]=int64_t(source.rejected);
        const auto& captured=stats.capturedPublications;
        out["capture_publication_index"]=int64_t(captured.lastIndex);
        out["capture_publications_accepted"]=int64_t(captured.accepted);
        out["capture_publications_missed"]=int64_t(captured.missed);
        out["capture_read_failures"]=int64_t(captured.readFailures);
        out["capture_rejected_reads"]=int64_t(captured.rejected);
        out["capture_queue_drops"]=int64_t(stats.captureQueueDrops);
        out["pending_snapshots"]=int64_t(stats.pendingSnapshots);
        out["pending_snapshot_bytes"]=int64_t(stats.pendingBytes);
        out["peak_pending_snapshots"]=int64_t(stats.peakPendingSnapshots);
        out["peak_pending_snapshot_bytes"]=int64_t(stats.peakPendingBytes);
        out["capture_ms"]=stats.captureMilliseconds;
        out["retirement_ms"]=stats.retirementMilliseconds;
        out["publication_backpressure"]=int64_t(stats.publicationBackpressure);
        out["bridge_pending_publications"]=int64_t(stats.captureDiagnostics.pendingPublications);
        out["bridge_retained_publications"]=int64_t(stats.captureDiagnostics.retainedPublications);
        out["capture_source_age_ms"]=stats.captureDiagnostics.sourceAgeMilliseconds;
        out["capture_poll_interval_max_ms"]=stats.capturePollIntervalMaxMs;
        out["capture_miss_poll_interval_max_ms"]=stats.captureMissPollIntervalMaxMs;
        out["error"]=godot::String(stats.error.c_str());
    }
    return out;
}

godot::Dictionary Df3dWorld::item_physical_layout() const {
    // On-demand picking/debug evaluation. Never feeds item GPU preparation.
    auto positions=itemPositions_;
    godot::PackedFloat32Array thicknesses;thicknesses.resize(itemIds_.size());
    for(int i=0;i<itemIds_.size();++i) {
        const auto* item=source_.model().item(wm::ItemId(itemIds_[i]));
        if(!item)continue;
        const mesher::DepthTile tile{item->pos.z,item->pos.x,item->pos.y};
        const float support=tileLayouts_.categoryCount(tile,1)>0
            ?mesher::kBuildingBottom+mesher::kBuildingThickness+mesher::kBuildingSpillBias
            :tileLayouts_.categoryCount(tile,0)>0?mesher::kInstallationBottom:0;
        const auto interval=mesher::sharedStackInterval(support,int(tileLayouts_.categoryCount(tile,2)),
            int(tileLayouts_.categoryCount(tile,3)),2,int(itemStackOrdinals_[i]));
        auto p=positions[i];p.y=item->pos.z+mesher::kFloorHeight+interval.bottom+ground_support(godot::Vector3(p.x,item->pos.z,p.z)).y;
        positions.set(i,p);thicknesses.set(i,interval.thickness);
    }
    godot::Dictionary result;result["positions"]=positions;result["thicknesses"]=thicknesses;
    return result;
}

bool Df3dWorld::layout_matches_reference() const {
    mesher::DepthSceneSources source;
    source.generation=source_.model().sessionGeneration();source.top=topZ_;source.window=get_window_depth();
    source.reveal=revealHidden_;source.sliceUnits=sliceUnits_;
    for(const auto& [id,value]:buildingFootprintCache_)
        source.buildings.emplace(id,mesher::BuildingFootprintSource{value.version,value.cells,value.foreground});
    const auto plan=mesher::prepareDepthScene(source_.model(),source);
    if(!plan.valid)return false;
    size_t visibleUnits=0;
    for(size_t i=0;i<plan.units.size();++i) {
        const auto unit=source_.model().evaluate(plan.units[i],double(source_.model().latestTick()));
        if(sliceUnits_ && source_.model().hasTerrain() && topZ_>=0 &&
            unit.pos.z<=topZ_-spriteWindowDepth())continue;
        const int index=int(visibleUnits++);
        if(index>=ids_.size() || plan.units[i]!=wm::UnitId(ids_[index]) ||
            unitCutoutPositions_[index]!=unitCutoutPosition(index,plan.unitDepth[i].bottom) ||
            unitThicknesses_[index]!=plan.unitDepth[i].thickness)return false;
    }
    if(visibleUnits!=size_t(ids_.size()))return false;
    std::map<wm::ItemId,int> quantities;
    size_t materialized=0;
    for(size_t i=0;i<plan.items.size();++i) {
        const auto* item=source_.model().item(plan.items[i]);
        if(!item || !zInSpriteWindow(item->pos.z) || !presentationTileDemanded(item->pos))continue;
        ++materialized;
        const auto found=itemInstanceIndices_.find(plan.items[i]);
        const auto ordinal=quantities[plan.items[i]]++;
        if(found==itemInstanceIndices_.end() || ordinal>=int(found->second.size()))return false;
        const int index=found->second[ordinal];
        const mesher::DepthTile tile{item->pos.z,item->pos.x,item->pos.y};
        const float support=tileLayouts_.categoryCount(tile,1)>0
            ?mesher::kBuildingBottom+mesher::kBuildingThickness+mesher::kBuildingSpillBias
            :tileLayouts_.categoryCount(tile,0)>0?mesher::kInstallationBottom:0;
        const float low=support+.005f;
        const auto count=tileLayouts_.categoryCount(tile,2)+tileLayouts_.categoryCount(tile,3);
        const float step=std::min(.13f,(mesher::kPieceCeiling-low)/std::max(size_t(1),count));
        if(itemPositions_[index].y!=plan.itemZ[i]+mesher::kFloorHeight ||
            low+itemStackOrdinals_[index]*step!=plan.itemDepth[i].bottom ||
            step*(.12f/.13f)!=plan.itemDepth[i].thickness)return false;
    }
    return materialized==size_t(itemIds_.size());
}

}
