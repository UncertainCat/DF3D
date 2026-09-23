#include "submission_uploads.h"
#include "submission_details.h"
#include "mesh_batches.h"
#include "batch_texture_pool.h"
#include "profiling.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <chrono>
#include <vector>
#include <algorithm>

namespace df3d_godot {
using namespace godot;
namespace {
void set_render_layers(MeshInstance3D* node, uint32_t layers) {
    if(node->get_layer_mask()==layers) return;
    // Godot 4.7 Forward+ can retain stale geometry/light pairs when changing
    // masks directly. Leaving visibility first unpairs them; restore the
    // semantic visibility synchronously so picking and effects still see it.
    const bool visible=node->is_visible();
    if(visible) node->hide();
    node->set_layer_mask(layers);
    if(visible) node->show();
}
void release(MeshInstance3D*& node) {
    if (!node) return;
    if (node->get_parent()) node->get_parent()->remove_child(node);
    memdelete(node);
    node = nullptr;
}
struct Surface {
    Ref<Material> material;
    PackedVector3Array vertices, normals;
    PackedVector2Array uv, uv2;
    PackedColorArray colors;
    PackedFloat32Array tangents;
    PackedFloat32Array layers;
    PackedInt32Array indices;
};
}
struct MeshBatches::Work {
    Key key;
    std::vector<uint64_t> ids;
    size_t cursor = 0;
    std::map<uint64_t, Surface> surfaces;
    Node* parent = nullptr;
    float margin = 0;
    std::vector<Ref<ArrayMesh>> meshes;
    uint64_t startPoll=0,copiedBytes=0,uploadedBytes=0,unchangedCopiedBytes=0;
    uint64_t newSources=0,changedSources=0,unchangedSources=0;
    std::map<uint64_t,uint64_t> sourceMeshes;
};
MeshBatches::MeshBatches(uint64_t quietFrames,const char* detailKind) : detailKind_(detailKind),quiet_(quietFrames),textures_(std::make_unique<BatchTexturePool>()) {}
MeshBatches::~MeshBatches() = default;
void MeshBatches::recordDetail(const char* stage,double elapsed,uint64_t copied,uint64_t api,bool cancelled) {
    auto& detail=submission::details();
    if(!detail.enabled || !work_)return;
    const double recordStart=df3d::profiling::global().nowUs();
    const auto& work=*work_;
    Dictionary row;
    row["batch_kind"]=String(detailKind_);row["stage"]=String(stage);row["poll"]=int64_t(detail.poll);
    row["start_poll"]=int64_t(work.startPoll);row["region"]=Vector3i(std::get<0>(work.key),std::get<1>(work.key),std::get<2>(work.key));
    row["source_count"]=int64_t(work.ids.size());row["processed_sources"]=int64_t(work.cursor);
    row["new_sources"]=int64_t(work.newSources);row["changed_sources"]=int64_t(work.changedSources);row["unchanged_sources"]=int64_t(work.unchangedSources);
    row["copied_bytes"]=int64_t(copied);row["api_payload_bytes"]=int64_t(api);row["elapsed_ms"]=elapsed;
    row["cancelled"]=cancelled;
    if(cancelled) {
        row["cancelled_copy_bytes"]=int64_t(work.copiedBytes);row["cancelled_upload_bytes"]=int64_t(work.uploadedBytes);
        ++detail.batchCancelled;detail.batchCancelledCopyBytes+=work.copiedBytes;detail.batchCancelledUploadBytes+=work.uploadedBytes;
    }
    detail.batch(row);
    detail.batchRecordUs+=df3d::profiling::global().nowUs()-recordStart;
}
void MeshBatches::invalidate(const Key& key) {
    df3d::profiling::Scope profile("batch.invalidate_slow", nullptr, df3d::profiling::detailed(), 100);
    ++invalidations_;
    if(work_ && work_->key==key) {
        recordDetail("cancel",0,0,0,true);
        ++cancellations_; work_.reset();
    }
    auto it=groups_.find(key);
    if(it==groups_.end()) return;
    // Only a published batch hides its sources. A dirty/in-flight group already
    // draws originals, so repeated edits must not walk every source again.
    if (!it->second.nodes.empty()) {
        for(auto& node:it->second.nodes)release(node);
        it->second.nodes.clear();
        for(auto id:it->second.sources) {
            ++restoreChecks_;
            auto& source=sources_.at(id);
            set_render_layers(source.node,source.layers);
        }
    }
    if(enabled_) dirty_.insert(key);
}
void MeshBatches::put(uint64_t id, MeshInstance3D* node, Vector3i cell) {
    const Key key{cell.x,cell.y,cell.z};
    const auto mesh=node->get_mesh();
    if(mesh.is_null()) {erase(id);return;}
    auto old=sources_.find(id);
    const uint64_t meshId=mesh->get_instance_id();
    if(old!=sources_.end() && old->second.node==node && old->second.cell==key && old->second.mesh==meshId) return;
    erase(id);
    // Geometry is authored in world coordinates. Unsupported transforms or
    // visibility/layers stay on their original path instead of being changed.
    if(node->get_material_override().is_valid() || node->get_transform()!=Transform3D() || !node->is_visible() || node->get_layer_mask()!=1) return;
    const bool deferred=quiet_.inserted(id);
    sources_.emplace(id,Source{node,key,meshId,node->get_layer_mask(),deferred});
    if(deferred) { ++deferrals_; return; }
    groups_[key].sources.insert(id);
    invalidate(key);
}
void MeshBatches::erase(uint64_t id) {
    auto it=sources_.find(id);
    if(it==sources_.end()) return;
    quiet_.removed(id);
    if(it->second.deferred) { sources_.erase(it); return; }
    const auto key=it->second.cell;
    invalidate(key);
    groups_.at(key).sources.erase(id);
    sources_.erase(it);
    if(groups_.at(key).sources.empty()) {groups_.erase(key);dirty_.erase(key);}
}
void MeshBatches::clear() {
    for(auto& [key,group]:groups_) invalidate(key);
    groups_.clear();sources_.clear();dirty_.clear();quiet_.clear();
    textures_->clear();
}
void MeshBatches::set_enabled(bool value) {
    if(enabled_==value) return;
    enabled_=value;
    for(auto& [key,group]:groups_) invalidate(key);
    if(!enabled_) dirty_.clear();
}
// One source gather or one surface upload per step. Keep originals visible
// until the complete replacement is ready; invalidation cancels partial work.
bool MeshBatches::step() {
    df3d::profiling::Scope profile("batch.step", nullptr, df3d::profiling::detailed());
    auto& work=*work_;
    auto& surfaces=work.surfaces;
    auto& parent=work.parent;
    auto& margin=work.margin;
    if(work.cursor<work.ids.size()) {
        df3d::profiling::Scope gatherProfile("batch.gather", nullptr, df3d::profiling::detailed());
        ++gatheredSources_;
        const auto id=work.ids[work.cursor++];
        const auto& source=sources_.at(id);
        auto node=source.node;
        if(!parent) parent=node->get_parent();
        if(parent!=node->get_parent() || !node->is_visible() || node->get_transform()!=Transform3D()) return true;
        margin=std::max(margin,node->get_extra_cull_margin());
        const Ref<ArrayMesh> mesh=node->get_mesh();
        if(mesh.is_null()) return true;
        bool unchanged=false;
        if(submission::details().enabled) {
            const auto& previous=groups_.at(work.key).publishedSourceMeshes;
            const auto before=previous.find(id);
            unchanged=before!=previous.end() && before->second==source.mesh;
            auto& detail=submission::details();
            if(before==previous.end()) {++work.newSources;++detail.batchNewSources;}
            else if(unchanged) {++work.unchangedSources;++detail.batchUnchangedSources;}
            else {++work.changedSources;++detail.batchChangedSources;}
            work.sourceMeshes[id]=source.mesh;
        }
        for(int i=0;i<mesh->get_surface_count();++i) {
            if(mesh->surface_get_primitive_type(i)!=Mesh::PRIMITIVE_TRIANGLES) return true;
            const Array cached=mesh->get_meta("df3d_batch_arrays",Array());
            if(submission::details().enabled) {
                if(cached.size()==mesh->get_surface_count())++submission::details().batchCachedArrayHits;
                else ++submission::details().batchArrayReadbacks;
            }
            const Array a=cached.size()==mesh->get_surface_count() ? Array(cached[i]) : mesh->surface_get_arrays(i);
            // These render paths use positions/normals/colors/UVs and indices.
            // Reject other channels rather than silently discarding attributes.
            for(int channel=0;channel<Mesh::ARRAY_MAX;++channel)
                if(channel!=Mesh::ARRAY_VERTEX && channel!=Mesh::ARRAY_NORMAL && channel!=Mesh::ARRAY_TANGENT && channel!=Mesh::ARRAY_COLOR && channel!=Mesh::ARRAY_TEX_UV && channel!=Mesh::ARRAY_TEX_UV2 && channel!=Mesh::ARRAY_INDEX && a[channel].get_type()!=Variant::NIL) return true;
            Ref<Material> material=node->get_surface_override_material(i);
            if(material.is_null()) material=mesh->surface_get_material(i);
            if(material.is_null()) return true;
            const auto binding=textures_->resolve(material);
            material=binding.material;
            auto& dst=surfaces[material->get_instance_id()];
            dst.material=material;
            const PackedVector3Array vertices=a[Mesh::ARRAY_VERTEX], normals=a[Mesh::ARRAY_NORMAL];
            gatheredVertices_ += vertices.size();
            const PackedVector2Array uv=a[Mesh::ARRAY_TEX_UV];
            const PackedVector2Array uv2=a[Mesh::ARRAY_TEX_UV2];
            const PackedColorArray colors=a[Mesh::ARRAY_COLOR];
            const PackedFloat32Array tangents=a[Mesh::ARRAY_TANGENT];
            const PackedInt32Array indices=a[Mesh::ARRAY_INDEX];
            // Consistent complete streams avoid mixed-format merged surfaces.
            if(normals.size()!=vertices.size() || colors.size()!=vertices.size() || (!uv.is_empty() && uv.size()!=vertices.size()) || (!uv2.is_empty() && uv2.size()!=vertices.size())) return true;
            if(!tangents.is_empty() && tangents.size()!=vertices.size()*4) return true;
            const int base=dst.vertices.size();
            if(base && (dst.uv.is_empty()!=uv.is_empty() || dst.uv2.is_empty()!=uv2.is_empty() || dst.tangents.is_empty()!=tangents.is_empty())) return true;
            if(submission::details().enabled) {
                const uint64_t bytes=uint64_t(vertices.size()+normals.size())*sizeof(Vector3)+
                    uint64_t(colors.size())*sizeof(Color)+uint64_t(uv.size()+uv2.size())*sizeof(Vector2)+
                    uint64_t(tangents.size())*sizeof(float)+uint64_t(indices.is_empty()?vertices.size():indices.size())*sizeof(int32_t);
                work.copiedBytes+=bytes;submission::details().batchCopiedBytes+=bytes;
                if(unchanged) {work.unchangedCopiedBytes+=bytes;submission::details().batchUnchangedCopiedBytes+=bytes;}
            }
            dst.vertices.append_array(vertices);dst.normals.append_array(normals);
            if(binding.layer>=0) {
                const auto first=dst.layers.size();dst.layers.resize(first+vertices.size());
                std::fill(dst.layers.ptrw()+first,dst.layers.ptrw()+dst.layers.size(),binding.layer);
            }
            dst.colors.append_array(colors);dst.uv.append_array(uv);dst.uv2.append_array(uv2);dst.tangents.append_array(tangents);
            const int offset=dst.indices.size();
            dst.indices.resize(offset+(indices.is_empty()?vertices.size():indices.size()));
            auto* out=dst.indices.ptrw()+offset;
            if(indices.is_empty()) {for(int j=0;j<vertices.size();++j) out[j]=base+j;}
            else {for(int j=0;j<indices.size();++j) out[j]=base+indices[j];}
        }
        return false;
    }
    if(!surfaces.empty()) {
        df3d::profiling::Scope uploadProfile("batch.upload", nullptr, df3d::profiling::detailed());
        // Material cardinality can exceed the engine's per-mesh surface cap.
        // Keep all chunks unpublished until the whole spatial group is ready.
        if(work.meshes.empty() || work.meshes.back()->get_surface_count()>=RenderingServer::MAX_MESH_SURFACES)
            work.meshes.push_back(submission::createMesh(submission::MeshSite::Batch));
        const auto& merged=work.meshes.back();
        const int previousSurfaces=merged->get_surface_count();
        auto& surface=surfaces.begin()->second;
        Array a;a.resize(Mesh::ARRAY_MAX);
        a[Mesh::ARRAY_VERTEX]=surface.vertices;a[Mesh::ARRAY_NORMAL]=surface.normals;
        if(!surface.tangents.is_empty()) a[Mesh::ARRAY_TANGENT]=surface.tangents;
        a[Mesh::ARRAY_COLOR]=surface.colors;a[Mesh::ARRAY_INDEX]=surface.indices;
        if(!surface.uv.is_empty()) a[Mesh::ARRAY_TEX_UV]=surface.uv;
        if(!surface.uv2.is_empty()) a[Mesh::ARRAY_TEX_UV2]=surface.uv2;
        if(!surface.layers.is_empty()) a[Mesh::ARRAY_CUSTOM0]=surface.layers;
        const auto bytesBefore=submission::counters().meshes[std::size_t(submission::MeshSite::Batch)].bytes;
        submission::meshSurface(merged, a, submission::MeshSite::Batch,
            surface.layers.is_empty()?0:uint64_t(Mesh::ARRAY_CUSTOM_R_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT);
        if(submission::details().enabled)work.uploadedBytes+=submission::counters().meshes[std::size_t(submission::MeshSite::Batch)].bytes-bytesBefore;
        // Any rejected upload leaves original sources visible, never publish a
        // partial group or accidentally replace the preceding surface material.
        if(merged->get_surface_count()!=previousSurfaces+1)return true;
        ++uploadedSurfaces_;
        merged->surface_set_material(previousSurfaces,surface.material);
        surfaces.erase(surfaces.begin());
        return false;
    }
    if(work.meshes.empty()) return true;
    df3d::profiling::Scope publishProfile("batch.publish", nullptr, df3d::profiling::detailed());
    auto& group=groups_.at(work.key);
    group.nodes.reserve(work.meshes.size());
    for(const auto& mesh:work.meshes) {
        auto node=memnew(MeshInstance3D);
        node->set_name("spatial_batch");
        node->set_mesh(mesh);node->set_extra_cull_margin(margin);
        node->set_meta("df3d_render_batch",true);
        parent->add_child(node);
        group.nodes.push_back(node);
    }
    if(submission::details().enabled)group.publishedSourceMeshes=work.sourceMeshes;
    for(auto id:group.sources) set_render_layers(sources_.at(id).node,0);
    ++builds_;
    return true;
}
void MeshBatches::flush(double budgetMs) {
    const auto start=std::chrono::steady_clock::now();
    quiet_.advance();
    while(quiet_.ready() || (enabled_ && !dirty_.empty())) {
        if(quiet_.ready()) {
            const auto id=quiet_.pop();
            if(id) {
                auto& source=sources_.at(*id);
                source.deferred=false;
                groups_[source.cell].sources.insert(*id);
                invalidate(source.cell);
                ++rejoins_;
            }
        } else {
            if(!work_) {
                work_=std::make_unique<Work>();
                work_->key=*dirty_.begin();
                const auto& ids=groups_.at(work_->key).sources;
                work_->ids.assign(ids.begin(),ids.end());
                if(submission::details().enabled)work_->startPoll=submission::details().poll;
            }
            const bool detail=submission::details().enabled;
            const double started=detail?df3d::profiling::global().nowUs():0;
            const uint64_t copiedBefore=detail?work_->copiedBytes:0,uploadedBefore=detail?work_->uploadedBytes:0;
            const char* stage=work_->cursor<work_->ids.size()?"gather":work_->surfaces.empty()?"publish":"upload";
            const bool complete=step();
            if(detail)recordDetail(stage,(df3d::profiling::global().nowUs()-started)/1000.0,
                work_->copiedBytes-copiedBefore,work_->uploadedBytes-uploadedBefore);
            if(complete) {
                dirty_.erase(work_->key);
                work_.reset();
            }
        }
        if(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()>=budgetMs) break;
    }
    if (df3d::profiling::global().mode() != df3d::profiling::Mode::Off)
        buildMs_+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
Dictionary MeshBatches::stats() const {
    Dictionary out;int batches=0,surfaces=0,publishedGroups=0,maxSurfaces=0;
    out["texture_pool"]=textures_->stats();
    for(const auto& [key,group]:groups_) {
        if(!group.nodes.empty())++publishedGroups;
        for(const auto node:group.nodes) {
            ++batches;
            const int count=node->get_mesh()->get_surface_count();
            surfaces+=count;maxSurfaces=std::max(maxSurfaces,count);
        }
    }
    out["enabled"]=enabled_;out["sources"]=static_cast<int64_t>(sources_.size());
    out["batches"]=batches;out["surfaces"]=surfaces;out["pending"]=pending();
    out["published_groups"]=publishedGroups;out["max_surfaces_per_mesh"]=maxSurfaces;
    out["builds"]=static_cast<int64_t>(builds_);out["build_ms"]=buildMs_;
    out["invalidations"]=int64_t(invalidations_);out["cancellations"]=int64_t(cancellations_);
    out["restore_checks"]=int64_t(restoreChecks_);out["gathered_sources"]=int64_t(gatheredSources_);
    out["gathered_vertices"]=int64_t(gatheredVertices_);out["uploaded_surfaces"]=int64_t(uploadedSurfaces_);
    out["deferred_sources"]=int64_t(quiet_.pending());out["quiet_history"]=int64_t(quiet_.size());
    out["deferrals"]=int64_t(deferrals_);out["rejoins"]=int64_t(rejoins_);
    return out;
}
}
