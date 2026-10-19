// Array layers use the same encoded-byte AUTO kernel and atlas bounds.
uniform bool batch_texture_enabled = false;
uniform sampler2DArray batch_texture : filter_linear_mipmap_anisotropic, repeat_disable;
varying flat float batch_layer;
vec4 batch_lanczos(sampler2DArray tex,vec2 pixel,ivec2 lo,ivec2 extent) {
    vec2 position=pixel-0.5;
    ivec2 start=ivec2(floor(position))-ivec2(2);
    vec4 result=vec4(0.0);
    float total_y=0.0;
    for(int y=0;y<6;y++) {
        int sy=start.y+y;
        if(sy<lo.y || sy>=lo.y+extent.y)continue;
        float wy=world_lanczos_weight(position.y-float(sy));
        vec4 row=vec4(0.0);float total_x=0.0;
        for(int x=0;x<6;x++) {
            int sx=start.x+x;
            if(sx<lo.x || sx>=lo.x+extent.x)continue;
            float wx=world_lanczos_weight(position.x-float(sx));
            row+=texelFetch(tex,ivec3(sx,sy,int(batch_layer)),0)*wx;total_x+=wx;
        }
        row=floor(clamp(row/total_x,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
        result+=row*wy;total_y+=wy;
    }
    return floor(clamp(result/total_y,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
}
vec4 sample_batch_region(sampler2DArray tex, vec2 uv, vec4 region) {
    vec2 size=vec2(textureSize(tex,0).xy);
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    ivec2 lo=ivec2(round(region.xy*size)), extent=ivec2(round(region.zw*size));
    int mode=world_filter_mode(dx*size,dy*size);
    if(mode==3) {
        ivec2 p=ivec2(floor(uv*size));
        return world_decode_texel(texelFetch(tex,ivec3(clamp(p,lo,lo+extent-ivec2(1)),int(batch_layer)),0));
    }
    if(mode==1) {
        ivec2 p=ivec2(floor(uv*size-0.5*(abs(dx)+abs(dy))*size+0.0001));
        return world_decode_texel(texelFetch(tex,ivec3(clamp(p,lo,lo+extent-ivec2(1)),int(batch_layer)),0));
    }
    if(mode==2)return world_decode_texel(batch_lanczos(tex,uv*size,lo,extent));
    if(region==vec4(0.0,0.0,1.0,1.0))return world_decode_texel(textureGrad(tex,vec3(uv,batch_layer),dx,dy));
    float max_lod=floor(log2(max(float(min(extent.x,extent.y)),1.0)));
    float scale=exp2(max_lod);
    if(any(greaterThan(abs(mod(vec2(lo),scale)),vec2(.001))) ||
       any(greaterThan(abs(mod(vec2(extent),scale)),vec2(.001))) ||
       any(greaterThan(abs(mod(size,scale)),vec2(.001))))max_lod=0.0;
    float footprint=max(length(dx*size),length(dy*size));
    float lod=clamp(log2(max(footprint,1.0)),0.0,max_lod);
    vec2 inset=vec2(.5*exp2(ceil(lod)));
    vec2 bounded=clamp(uv*size,vec2(lo)+inset,vec2(lo+extent)-inset)/size;
    return world_decode_texel(textureLod(tex,vec3(bounded,batch_layer),lod));
}
vec4 sample_batch_grid_at(vec2 uv,vec2 cell,vec2 tile_center) {
    vec2 size=vec2(textureSize(batch_texture,0).xy);
    if(cell.x<=0.0 || cell.y<=0.0 || cell==size)return sample_batch_region(batch_texture,uv,vec4(0.0,0.0,1.0,1.0));
    vec2 index=clamp(floor(tile_center*size/cell),vec2(0.0),size/cell-1.0);
    return sample_batch_region(batch_texture,uv,vec4(index*cell/size,cell/size));
}
vec4 sample_batch_grid(vec2 uv,vec2 cell) {return sample_batch_grid_at(uv,cell,uv);}
