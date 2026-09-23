#pragma once
#include "submission_uploads.h"
#include <godot_cpp/variant/dictionary.hpp>
#include <array>

namespace df3d_godot::submission {
struct DetailState {
    bool enabled = false;
    uint64_t poll = 0, buildingDropped = 0, batchDropped = 0;
    double batchRecordUs = 0;
    godot::Array buildings, batches;
    std::array<uint64_t,4> reasons{};
    uint64_t buildingEvents = 0, identicalEvents = 0, identicalBytes = 0, yOnlyEvents = 0;
    uint64_t buildingHashUs = 0;
    uint64_t batchCopiedBytes = 0, batchUnchangedCopiedBytes = 0, batchChangedSources = 0,
        batchUnchangedSources = 0, batchNewSources = 0, batchCancelled = 0,
        batchCancelledCopyBytes = 0, batchCancelledUploadBytes = 0,
        batchCachedArrayHits = 0, batchArrayReadbacks = 0;
    DetailState() {
        const auto* flag = std::getenv("DF3D_SUBMISSION_DETAIL");
        enabled = counters().enabled() && flag && std::strcmp(flag, "1") == 0;
    }
    void append(godot::Array& rows, const godot::Dictionary& row, int limit, uint64_t& dropped) {
        if (rows.size() < limit) rows.push_back(row);
        else {
            // Keep expensive examples, not merely the first cheap operations.
            int smallest = 0;
            double minimum = double(godot::Dictionary(rows[0])["elapsed_ms"]);
            for (int i=1;i<rows.size();++i) {
                const double cost = godot::Dictionary(rows[i])["elapsed_ms"];
                if (cost < minimum) { minimum=cost; smallest=i; }
            }
            if (double(row["elapsed_ms"]) > minimum) rows[smallest] = row;
            ++dropped;
        }
    }
    void building(const godot::Dictionary& row) { append(buildings,row,16,buildingDropped); }
    void batch(const godot::Dictionary& row) { append(batches,row,8,batchDropped); }
};
inline DetailState& details() { static DetailState state; return state; }

class BuildingDetailScope {
    bool enabled_;
    uint64_t id_, poll_;
    const char* kind_;
    uint32_t reasons_;
    double started_ = 0;
    double hashUs_ = 0;
    bool hashSupported_ = true;
    MeshCounts before_;
    GeometryFingerprint* previous_;
    uint64_t full_ = 14695981039346656037ULL, withoutY_ = 14695981039346656037ULL;
public:
    BuildingDetailScope(uint64_t id, const char* kind, uint32_t reasons, GeometryFingerprint& previous)
        : enabled_(details().enabled), id_(id), poll_(details().poll), kind_(kind), reasons_(reasons), previous_(&previous) {
        if (!enabled_) return;
        started_ = df3d::profiling::global().nowUs();
        before_ = counters().meshes[std::size_t(MeshSite::Building)];
    }
    void surface(const godot::Array& arrays) {
        if (!enabled_) return;
        const double started=df3d::profiling::global().nowUs();
        df3d::profiling::Scope hashProfile("diagnostics.building_stream_hash",nullptr,df3d::profiling::detailed());
        for(int channel=0;channel<arrays.size();++channel) {
            const godot::Variant value=arrays[channel];
            const auto tag=uint32_t(value.get_type());
            full_=hashBytes(full_,&tag,sizeof(tag)); withoutY_=hashBytes(withoutY_,&tag,sizeof(tag));
            const auto add=[&](const void* data,std::size_t size) {
                full_=hashBytes(full_,data,size); withoutY_=hashBytes(withoutY_,data,size);
            };
            if(tag==godot::Variant::PACKED_VECTOR3_ARRAY) {
                const godot::PackedVector3Array stream=value;
                const auto count=uint64_t(stream.size());add(&count,sizeof(count));
                full_=hashBytes(full_,stream.ptr(),stream.size()*sizeof(godot::Vector3));
                if(channel==godot::Mesh::ARRAY_VERTEX) {
                    for(int i=0;i<stream.size();++i) {
                        const auto& v=stream.ptr()[i];
                        withoutY_=hashBytes(withoutY_,&v.x,sizeof(v.x));
                        withoutY_=hashBytes(withoutY_,&v.z,sizeof(v.z));
                    }
                } else withoutY_=hashBytes(withoutY_,stream.ptr(),stream.size()*sizeof(godot::Vector3));
            } else if(tag==godot::Variant::PACKED_VECTOR2_ARRAY) {
                const godot::PackedVector2Array stream=value;const auto count=uint64_t(stream.size());add(&count,sizeof(count));add(stream.ptr(),stream.size()*sizeof(godot::Vector2));
            } else if(tag==godot::Variant::PACKED_COLOR_ARRAY) {
                const godot::PackedColorArray stream=value;const auto count=uint64_t(stream.size());add(&count,sizeof(count));add(stream.ptr(),stream.size()*sizeof(godot::Color));
            } else if(tag==godot::Variant::PACKED_INT32_ARRAY) {
                const godot::PackedInt32Array stream=value;const auto count=uint64_t(stream.size());add(&count,sizeof(count));add(stream.ptr(),stream.size()*sizeof(int32_t));
            } else if(tag!=godot::Variant::NIL)hashSupported_=false;
        }
        hashUs_+=df3d::profiling::global().nowUs()-started;
    }
    ~BuildingDetailScope() {
        if (!enabled_) return;
        auto& state=details();
        const auto& after=counters().meshes[std::size_t(MeshSite::Building)];
        const auto bytes=after.bytes-before_.bytes;
        const char* relation=streamRelation(*previous_,full_,withoutY_,hashSupported_);
        ++state.buildingEvents;
        for(int i=0;i<4;++i)if(reasons_&(1u<<i))++state.reasons[i];
        if(hashSupported_ && previous_->valid && previous_->full==full_) {++state.identicalEvents;state.identicalBytes+=bytes;}
        else if(hashSupported_ && previous_->valid && previous_->withoutY==withoutY_)++state.yOnlyEvents;
        *previous_={full_,withoutY_,hashSupported_};
        state.buildingHashUs+=uint64_t(hashUs_);
        godot::Dictionary row;
        row["id"]=int64_t(id_);row["kind"]=godot::String(kind_);row["poll"]=int64_t(poll_);
        row["reason_mask"]=int64_t(reasons_);row["stream_relation"]=godot::String(relation);
        row["elapsed_ms"]=(df3d::profiling::global().nowUs()-started_)/1000.0;
        row["hash_ms"]=hashUs_/1000.0;
        row["payload_bytes"]=int64_t(bytes);row["surfaces"]=int64_t(after.calls-before_.calls);
        row["vertices"]=int64_t(after.vertices-before_.vertices);row["indices"]=int64_t(after.indices-before_.indices);
        state.building(row);
    }
};
}
