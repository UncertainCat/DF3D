#pragma once
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <set>
#include <algorithm>
#include <cstdint>
#include <vector>

namespace df3d_godot {
// One record per semantic tile. Only changed pages cross the engine boundary;
// individual resident item transforms do not depend on creature occupancy.
class SharedStackAtlas {
    godot::Ref<godot::Texture2DArray> texture_;
    std::vector<godot::Ref<godot::Image>> pages_;
    std::vector<uint8_t> ground_;
    std::set<int> dirty_;
    int side_=32, columns_=0, rows_=0, bottom_=0, depth_=0;
public:
    uint64_t revision=0, uploads=0, uploadedBytes=0;
    void reset(int width,int height,int bottom,int depth) {
        side_=32;bottom_=bottom;depth_=std::max(1,depth);
        while(((width+side_-1)/side_)*((height+side_-1)/side_)*depth_>2048)side_*=2;
        columns_=std::max(1,(width+side_-1)/side_);rows_=std::max(1,(height+side_-1)/side_);
        ground_.assign(size_t(columns_)*rows_*depth_*side_*side_,0);
        pages_.clear();dirty_.clear();
        godot::TypedArray<godot::Ref<godot::Image>> images;
        for(int i=0;i<columns_*rows_*depth_;++i) {
            auto image=godot::Image::create_empty(side_,side_,false,godot::Image::FORMAT_RGBAF);
            image->fill(godot::Color(0,0,0,0));pages_.push_back(image);images.push_back(image);
        }
        if(texture_.is_null())texture_.instantiate();
        texture_->create_from_images(images);++revision;
    }
    void set(int x,int y,int z,float support,int objects,int creatures) {
        if(x<0 || y<0 || x>=columns_*side_ || y>=rows_*side_ || z<bottom_ || z>=bottom_+depth_)return;
        const int page=(z-bottom_)*columns_*rows_+(y/side_)*columns_+x/side_;
        const godot::Color value(support,float(objects),float(creatures),pages_[page]->get_pixel(x%side_,y%side_).a);
        if(pages_[page]->get_pixel(x%side_,y%side_)==value)return;
        pages_[page]->set_pixel(x%side_,y%side_,value);dirty_.insert(page);
    }
    int ground(int x,int y,int z) const {
        if(x<0 || y<0 || x>=columns_*side_ || y>=rows_*side_ || z<bottom_ || z>=bottom_+depth_ || pages_.empty())return 0;
        const int page=(z-bottom_)*columns_*rows_+(y/side_)*columns_+x/side_;
        return ground_[size_t(page)*side_*side_+(y%side_)*side_+x%side_];
    }
    bool setGround(int x,int y,int z,int code) {
        if(x<0 || y<0 || x>=columns_*side_ || y>=rows_*side_ || z<bottom_ || z>=bottom_+depth_ || pages_.empty())return false;
        const int page=(z-bottom_)*columns_*rows_+(y/side_)*columns_+x/side_;
        auto& old=ground_[size_t(page)*side_*side_+(y%side_)*side_+x%side_];
        if(old==code)return false;
        old=uint8_t(code);
        auto value=pages_[page]->get_pixel(x%side_,y%side_);
        if(value.a==float(code))return false;
        value.a=float(code);pages_[page]->set_pixel(x%side_,y%side_,value);dirty_.insert(page);return true;
    }
    void flush() {
        for(const int page:dirty_) { texture_->update_layer(pages_[page],page);++uploads;uploadedBytes+=uint64_t(side_)*side_*16; }
        dirty_.clear();
    }
    void configure(const godot::Ref<godot::ShaderMaterial>& material) const {
        if(material.is_null() || texture_.is_null())return;
        material->set_shader_parameter("shared_stack_texture",texture_);
        material->set_shader_parameter("shared_stack_shape",godot::Vector4(side_,columns_,rows_,bottom_));
        material->set_shader_parameter("shared_stack_enabled",true);
    }
};
}
