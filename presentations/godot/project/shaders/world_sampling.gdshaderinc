#include "res://shaders/world_color.gdshaderinc"
global uniform bool world_texture_smoothing;
// AUTO uses nearest near integer, axis-aligned magnification and a radius-three
// Lanczos reconstruction between those scales. Oblique/minified surfaces keep
// mip/anisotropic filtering. All kernels remain inside the owning atlas cell.
float world_lanczos_weight(float x) {
    x=abs(x);
    if(x<0.00001)return 1.0;
    if(x>=3.0)return 0.0;
    float p=3.141592653589793*x;
    return (sin(p)/p)*(sin(p/3.0)/(p/3.0));
}
int world_filter_mode(vec2 dx,vec2 dy) {
    float footprint=max(length(dx),length(dy));
    // Native reconstruction owns aligned views; ordinary 3D magnification can
    // preserve source pixels while minification retains the bounded mip path.
    int fallback_mode=(!world_texture_smoothing && footprint<=1.0) ? 3 : 0;
    if(!native_world_color)return fallback_mode;
    if(footprint>1.001 || min(length(dx),length(dy))<0.00001)return 0;
    if(abs(dx.y)>0.001*footprint || abs(dy.x)>0.001*footprint)return fallback_mode;
    vec2 scale=1.0/vec2(abs(dx.x),abs(dy.y));
    if(any(greaterThan(abs(scale-round(scale)),vec2(0.025))))return 2;
    return 1;
}
vec4 world_decode_texel(vec4 c) { return vec4(world_decode(c.rgb),c.a); }
vec4 world_lanczos(sampler2D tex,vec2 pixel,ivec2 lo,ivec2 extent) {
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
            row+=texelFetch(tex,ivec2(sx,sy),0)*wx;total_x+=wx;
        }
        row=floor(clamp(row/total_x,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
        result+=row*wy;total_y+=wy;
    }
    return floor(clamp(result/total_y,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
}
vec4 sample_world_region(sampler2D tex, vec2 uv, vec4 region) {
    vec2 size=vec2(textureSize(tex,0));
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    ivec2 lo=ivec2(round(region.xy*size)), extent=ivec2(round(region.zw*size));
    int mode=world_filter_mode(dx*size,dy*size);
    if(mode==3) {
        ivec2 p=ivec2(floor(uv*size));
        return world_decode_texel(texelFetch(tex,clamp(p,lo,lo+extent-ivec2(1)),0));
    }
    if(mode==1) {
        ivec2 p=ivec2(floor(uv*size-0.5*(abs(dx)+abs(dy))*size+0.0001));
        return world_decode_texel(texelFetch(tex,clamp(p,lo,lo+extent-ivec2(1)),0));
    }
    if(mode==2)return world_decode_texel(world_lanczos(tex,uv*size,lo,extent));
    if(region==vec4(0.0,0.0,1.0,1.0))return world_decode_texel(textureGrad(tex,uv,dx,dy));
    float max_lod=floor(log2(max(float(min(extent.x,extent.y)),1.0)));
    float scale=exp2(max_lod);
    if(any(greaterThan(abs(mod(vec2(lo),scale)),vec2(.001))) ||
       any(greaterThan(abs(mod(vec2(extent),scale)),vec2(.001))) ||
       any(greaterThan(abs(mod(size,scale)),vec2(.001))))max_lod=0.0;
    float footprint=max(length(dx*size),length(dy*size));
    float lod=clamp(log2(max(footprint,1.0)),0.0,max_lod);
    vec2 inset=vec2(.5*exp2(ceil(lod)));
    vec2 bounded=clamp(uv*size,vec2(lo)+inset,vec2(lo+extent)-inset)/size;
    return world_decode_texel(textureLod(tex,bounded,lod));
}
vec4 sample_world_grid_at(sampler2D tex, vec2 uv, vec2 cell, vec2 tile_center) {
    vec2 size = vec2(textureSize(tex, 0));
    if (cell.x <= 0.0 || cell.y <= 0.0) return sample_world_region(tex, uv, vec4(0.0,0.0,1.0,1.0));
    // MSAA evaluates fragments whose centers can lie just outside a triangle.
    // Select the atlas cell from the primitive, not extrapolated edge UVs.
    vec2 index = clamp(floor(tile_center * size / cell), vec2(0.0), size / cell - 1.0);
    return sample_world_region(tex, uv, vec4(index * cell / size, cell / size));
}
vec4 sample_world_grid(sampler2D tex, vec2 uv, vec2 cell) {
    return sample_world_grid_at(tex, uv, cell, uv);
}
