#pragma once
#include "df3d_assets/compositor.h"

namespace df3d::assets {
// Presentation-only deterministic arrangement, verified against DF53.16's
// item renderer. The seed is an owned item ID, never native RNG scratch.
inline unsigned gemVariant(uint32_t id) {
  uint64_t value=uint64_t(id)+0x9e3779b97f4a7c15ULL;
  value=(value^(value>>30))*0xbf58476d1ce4e5b9ULL;
  value=(value^(value>>27))*0x94d049bb133111ebULL;
  return unsigned(((value^(value>>31))>>32)&3);
}

inline CompositeResult compositeGem(const CompositeContext& ctx, std::string_view shape,
                                    uint32_t id, std::string_view color) {
  CompositeResult result;
  if(!ctx.index || !ctx.load || shape.empty())return result;
  const auto& index=*ctx.index;
  const auto* sprite=index.tile("GEM_SHAPE:"+std::string(shape));
  if(!sprite)return result;
  const auto* page=index.page(sprite->page);
  const auto* source=page?ctx.load(page->absPath):nullptr;
  const auto rect=index.pixels(*sprite);
  if(!source || rect.pw!=16 || rect.ph!=16 || !source->contains(rect.px,rect.py) ||
     !source->contains(rect.px+15,rect.py+15))return result;
  static constexpr int origins[4][3][2]={
    {{8,3},{13,8},{3,13}},{{4,3},{12,7},{7,13}},
    {{13,3},{3,8},{8,13}},{{3,5},{12,6},{6,12}}};
  result.image=RgbaImage::blank(32,32);
  for(const auto& origin:origins[gemVariant(id)]) {
    for(int y=0;y<16;++y)for(int x=0;x<16;++x) {
      const auto src=source->get(rect.px+x,rect.py+y);
      if(!src.a)continue;
      auto dst=result.image.get(origin[0]+x,origin[1]+y);
      // Native pre-seeds empty destination alpha before its SDL blit.
      // Keep the two truncations separate, including the alpha channel.
      if(!dst.a)dst.a=src.a;
      const auto blend=[&](unsigned s,unsigned d)->uint8_t {
        return uint8_t(((s*src.a)>>8)+((d*(255-src.a))>>8));
      };
      if(src.a==255)dst=src;
      else dst={blend(src.r,dst.r),blend(src.g,dst.g),blend(src.b,dst.b),blend(255,dst.a)};
      result.image.set(origin[0]+x,origin[1]+y,dst);
    }
  }
  if(!color.empty()) {
    const int row=index.paletteRow(color);
    if(!index.palette || row<0)return {};
    const auto* palette=ctx.load(index.palette->absPath);
    const int key=index.palette->defaultRow;
    if(!palette || !palette->contains(17,row) || !palette->contains(17,key))return {};
    for(int y=0;y<32;++y)for(int x=0;x<32;++x) {
      auto pixel=result.image.get(x,y);
      if(!pixel.a)continue;
      for(int i=0;i<18;++i)if(packRgb(pixel)==packRgb(palette->get(i,key))) {
        const auto replacement=palette->get(i,row);
        pixel.r=replacement.r;pixel.g=replacement.g;pixel.b=replacement.b;break;
      }
      result.image.set(x,y,pixel);
    }
  }
  result.ok=true;result.layersDrawn=3;result.cellsX=result.cellsY=1;
  result.tileW=result.tileH=32;
  return result;
}
}
