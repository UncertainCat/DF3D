#pragma once
// Immutable artwork only. Stable, size-compatible texture-array banks let
// spatial mesh batches share a material without changing source UVs/mipmaps.
#include "submission_uploads.h"
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <map>
#include <vector>
#include <tuple>
#include <cstdlib>

namespace df3d_godot {
class BatchTexturePool {
    struct Bank {
        godot::Ref<godot::Texture2DArray> texture;
        int used=0,capacity=0;
    };
    struct Entry {size_t bank; int layer;};
    std::vector<Bank> banks_;
    std::map<std::tuple<int,int,int,bool>,size_t> open_;
    std::map<uint64_t,Entry> textures_;
    std::map<godot::String,godot::Ref<godot::ShaderMaterial>> materials_;
public:
    struct Binding {godot::Ref<godot::Material> material; float layer=-1;};
private:
    std::map<uint64_t,Binding> bindings_;
    uint64_t allocatedBytes_=0,uploadedBytes_=0;
    bool enabled_=!std::getenv("DF3D_BATCH_TEXTURES") || std::string(std::getenv("DF3D_BATCH_TEXTURES"))!="0";
public:
    Binding resolve(const godot::Ref<godot::Material>& source) {
        using namespace godot;
        if(!enabled_ || source.is_null())return {source};
        const auto id=source->get_instance_id();
        if(const auto it=bindings_.find(id);it!=bindings_.end())return it->second;
        Ref<ShaderMaterial> material=source;
        if(material.is_null() || material->get_shader().is_null() || material->get_next_pass().is_valid())return {source};
        if(!material->has_meta("df3d_batch_parameters"))return {source};
        const Dictionary parameters=material->get_meta("df3d_batch_parameters");
        const String shader=material->get_shader()->get_path();
        const bool terrain=shader=="res://shaders/terrain.gdshader" || shader=="res://shaders/terrain_cutout.gdshader";
        const bool building=shader=="res://shaders/unit_sprite.gdshader";
        if(!terrain && !building)return {source};
        if(building && bool(parameters.get("actor_animated",false)))return {source};
        const StringName parameter=terrain?"albedo_tex":"sprite_tex";
        Ref<Texture2D> texture=parameters.get(parameter,Variant());
        if(texture.is_null())return {source};
        auto found=textures_.find(texture->get_instance_id());
        if(found==textures_.end()) {
            Ref<Image> image=texture->get_meta("df3d_immutable_image",Variant());
            if(image.is_null())return {source}; // Unsupported mutable/external texture stays independent.
            if(image.is_null() || image->is_empty() || image->is_compressed())return {source};
            const auto key=std::make_tuple(image->get_width(),image->get_height(),int(image->get_format()),image->has_mipmaps());
            auto bank=open_.find(key);
            if(bank==open_.end() || banks_[bank->second].used==banks_[bank->second].capacity) {
                // Bound spare allocation to 4 MiB per bank; big pages do not
                // reserve dozens of unused full-resolution copies.
                const int64_t bytes=image->get_data().size();
                const int capacity=int(std::clamp<int64_t>((4*1024*1024)/std::max<int64_t>(1,bytes),1,32));
                TypedArray<Ref<Image>> images;
                for(int i=0;i<capacity;++i)images.push_back(image);
                Bank next;next.capacity=capacity;next.texture.instantiate();
                if(next.texture->create_from_images(images)!=OK)return {source};
                allocatedBytes_+=uint64_t(bytes)*capacity;uploadedBytes_+=uint64_t(bytes)*capacity;
                submission::counters().texture(submission::TextureSite::Atlas,uint64_t(bytes)*capacity);
                const size_t index=banks_.size();banks_.push_back(next);
                bank=open_.insert_or_assign(key,index).first;
            }
            auto& target=banks_[bank->second];
            const int layer=target.used++;
            // The first layer was supplied on creation; later artwork updates
            // only its reserved layer. All existing layer indices stay stable.
            if(layer>0) {
                target.texture->update_layer(image,layer);
                const uint64_t bytes=image->get_data().size();uploadedBytes_+=bytes;
                submission::counters().texture(submission::TextureSite::Atlas,bytes);
            }
            found=textures_.emplace(texture->get_instance_id(),Entry{bank->second,layer}).first;
        }
        const auto entry=found->second;
        // Match every other uniform, including palette-cell sizes and spatter
        // textures. Never merge different material behavior just by shader name.
        String key=shader+String(":")+String::num_uint64(entry.bank)+String(":")+String::num_int64(material->get_render_priority());
        auto names=parameters.keys();names.sort();
        for(int i=0;i<names.size();++i) {
            const StringName name=names[i];
            if(name==parameter || String(name).begins_with("batch_"))continue;
            const Variant value=parameters[name];
            key+=String("|")+String(name)+String("=")+value.stringify();
        }
        auto& merged=materials_[key];
        if(merged.is_null()) {
            merged.instantiate();
            merged->set_shader(material->get_shader());
            merged->set_render_priority(material->get_render_priority());
            for(int i=0;i<names.size();++i)merged->set_shader_parameter(names[i],parameters[names[i]]);
            merged->set_shader_parameter("batch_texture_enabled",true);
            merged->set_shader_parameter("batch_texture",banks_[entry.bank].texture);
        }
        PackedInt64Array provenance=merged->get_meta("df3d_batch_source_materials",PackedInt64Array());
        if(provenance.size()<=entry.layer)provenance.resize(entry.layer+1);
        provenance.set(entry.layer,int64_t(id));
        merged->set_meta("df3d_batch_source_materials",provenance);
        Binding binding{merged,float(entry.layer)};
        bindings_[id]=binding;return binding;
    }
    void clear() {bindings_.clear();materials_.clear();textures_.clear();open_.clear();banks_.clear();allocatedBytes_=uploadedBytes_=0;}
    godot::Dictionary stats() const {
        godot::Dictionary d;d["enabled"]=enabled_;d["banks"]=int64_t(banks_.size());
        d["textures"]=int64_t(textures_.size());d["materials"]=int64_t(materials_.size());
        d["allocated_bytes"]=int64_t(allocatedBytes_);d["uploaded_bytes"]=int64_t(uploadedBytes_);return d;
    }
};
}
