shader_type canvas_item;
// DF filters each installed 8x12 UI cell independently at fractional scales.
// Bounded, separable Lanczos3 preserves native alpha/RGB and byte rounding.
// Tint source texels before reconstruction: colored glyphs retain native ringing.
varying vec4 tint;
void vertex(){tint=COLOR;}
float native_lanczos_weight(float x) {
    x=abs(x);
    if(x<0.00001)return 1.0;
    if(x>=3.0)return 0.0;
    float p=3.141592653589793*x;
    return (sin(p)/p)*(sin(p/3.0)/(p/3.0));
}
void fragment(){
 vec2 size=vec2(textureSize(TEXTURE,0));
 vec2 scale=1.0/fwidth(UV*size);
 vec4 sampled=texture(TEXTURE,UV)*tint;
 ivec2 lo=ivec2(0), extent=ivec2(size);
 if(mod(size.x,8.0)==0.0 && mod(size.y,12.0)==0.0){extent=ivec2(8,12);lo=ivec2(floor(UV*size/vec2(extent)))*extent;}
 if(any(greaterThan(abs(scale-round(scale)),vec2(.025)))) {
    vec2 position=UV*size-0.5;
    ivec2 start=ivec2(floor(position))-ivec2(2);
    vec4 result=vec4(0.0);
    float total_y=0.0;
    for(int y=0;y<6;y++) {
        int sy=start.y+y;
        if(sy<lo.y || sy>=lo.y+extent.y)continue;
        float wy=native_lanczos_weight(position.y-float(sy));
        vec4 row=vec4(0.0);float total_x=0.0;
        for(int x=0;x<6;x++) {
            int sx=start.x+x;
            if(sx<lo.x || sx>=lo.x+extent.x)continue;
            float wx=native_lanczos_weight(position.x-float(sx));
            row+=texelFetch(TEXTURE,ivec2(sx,sy),0)*tint*wx;total_x+=wx;
        }
        row=floor(clamp(row/total_x,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
        result+=row*wy;total_y+=wy;
    }
    sampled=floor(clamp(result/total_y,vec4(0.0),vec4(1.0))*255.0+0.5)/255.0;
 }
 COLOR=sampled;
}
