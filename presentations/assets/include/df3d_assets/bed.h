#pragma once
#include "df3d_assets/compositor.h"
#include "df3d_assets/resolver.h"

namespace df3d::assets {
// DF53.16 bed compositor: pillow wins over sheet, sheet over base whenever
// the source alpha is nonzero. These layers are not alpha-over blended.
inline CompositeResult compositeBed(const CompositeContext& ctx, std::string_view material,
                                    const wm::BeddingFacts& facts) {
  CompositeResult result;
  if (!ctx.index || !ctx.load || facts.sheet<0 || facts.sheet>1 || facts.pillow<0 || facts.pillow>2)
    return result;
  const auto& index=*ctx.index;
  const auto cls=materialClassOf(index,material);
  if(cls==MaterialClass::Unknown)return result;
  // DF's item and material bed getters select the stone frame for glass.
  // The installed GLASS token is not used by those composite getters.
  const auto frameClass=cls==MaterialClass::Glass?MaterialClass::Stone:cls;
  const auto* base=index.tile(std::string("ITEM_BED_")+materialClassToken(frameClass));
  const auto* sheet=index.tile("ITEM_BED_SHEET_VARIANT",facts.sheet);
  const auto* pillow=index.tile("ITEM_BED_PILLOW_VARIANT",facts.pillow);
  if(!base || !sheet || !pillow)return result;
  const SpriteRef* layers[]={base,sheet,pillow};
  const std::string_view colors[]={facts.baseColor,facts.sheetColor,{}};
  for(int layer=0;layer<3;++layer) {
    const auto* page=index.page(layers[layer]->page);
    const auto* image=page?ctx.load(page->absPath):nullptr;
    const auto rect=index.pixels(*layers[layer]);
    if(!image || rect.pw<=0 || rect.ph<=0 || !image->contains(rect.px,rect.py) ||
       !image->contains(rect.px+rect.pw-1,rect.py+rect.ph-1))return {};
    if(layer==0)result.image=RgbaImage::blank(rect.pw,rect.ph);
    if(result.image.width!=rect.pw || result.image.height!=rect.ph)return {};
    const RgbaImage* palette=nullptr;
    int row=-1,keyRow=-1;
    if(!colors[layer].empty()) {
      row=index.paletteRow(colors[layer]);
      if(!index.palette || row<0)return {};
      keyRow=index.palette->defaultRow;
      palette=ctx.load(index.palette->absPath);
      if(!palette || palette->width<18 || !palette->contains(17,row) || !palette->contains(17,keyRow))return {};
    }
    for(int y=0;y<rect.ph;++y)for(int x=0;x<rect.pw;++x) {
      auto pixel=image->get(rect.px+x,rect.py+y);
      if(!pixel.a)continue;
      if(palette)for(int column=0;column<18;++column) {
        if(packRgb(pixel)==packRgb(palette->get(column,keyRow))) {
          const auto replacement=palette->get(column,row);
          pixel.r=replacement.r;pixel.g=replacement.g;pixel.b=replacement.b;break;
        }
      }
      result.image.set(x,y,pixel);
    }
  }
  result.ok=true;result.layersDrawn=3;result.cellsX=result.cellsY=1;
  result.tileW=result.image.width;result.tileH=result.image.height;
  return result;
}
}
