#pragma once
#include "area_geometry.h"
#include "paint_water.h"

namespace df3d_area {
// Counts are a read of local selection geometry, never a native staged draft.
// -1 means unobserved, not zero. A valid query can have one unknown term.
struct PaintCounts {
  bool valid=false;
  int32_t painted=-1,preview=-1;
};
namespace paint_counts_detail {
// Canonical non-overlapping row spans bound the request and prevent duplicates
// from inflating counts. Draft and preview each use the existing paint limits;
// their union need not fit a single bounding box (a hover may be far away).
inline bool expand(const std::vector<Span>& spans,int32_t width,int32_t height,
                   std::vector<uint64_t>& points) {
  if(spans.size()>kMaxSpans)return false;
  int32_t left=width,top=height,right=-1,bottom=-1;
  int32_t previousY=-1,previousEnd=-1;
  size_t count=0;
  for(const auto& s:spans) {
    if(s.x<0 || s.y<0 || s.y>=height || s.length<1 ||
       int64_t(s.x)+s.length>width || s.y<previousY ||
       (s.y==previousY && s.x<previousEnd) ||
       uint64_t(s.length)>kMaxPaintTiles-count)return false;
    count+=size_t(s.length);previousY=s.y;previousEnd=s.x+s.length;
    left=std::min(left,s.x);top=std::min(top,s.y);
    right=std::max(right,previousEnd-1);bottom=std::max(bottom,s.y);
  }
  if(!spans.empty() && (int64_t(right)-left+1>kMaxSide ||
      int64_t(bottom)-top+1>kMaxSide ||
      (int64_t(right)-left+1)*(int64_t(bottom)-top+1)>kMaxCells))return false;
  points.reserve(count);
  for(const auto& s:spans)for(int32_t x=s.x;x<s.x+s.length;++x)
    points.push_back((uint64_t(uint32_t(s.y))<<32)|uint32_t(x));
  return true;
}
}
// Invoke under one safe point with a current semantic eligibility observer.
// Read the union once; an overlapping preview cell belongs to the painted term.
// Erase intentionally does not change the formula: native062137's actual erase
// button reports eligible *unpainted* preview cells, not the removal/net delta.
template<class Observe>
PaintCounts countPaint(const std::vector<Span>& draft,const std::vector<Span>& preview,
                       int32_t width,int32_t height,Observe observe) {
  if(width<=0 || height<=0)return {};
  std::vector<uint64_t> paintedPoints,previewPoints;
  if(!paint_counts_detail::expand(draft,width,height,paintedPoints) ||
     !paint_counts_detail::expand(preview,width,height,previewPoints))return {};
  PaintCounts result{true,0,0};
  size_t a=0,b=0;
  while(a<paintedPoints.size() || b<previewPoints.size()) {
    const bool painted=a<paintedPoints.size() &&
      (b==previewPoints.size() || paintedPoints[a]<=previewPoints[b]);
    const auto point=painted?paintedPoints[a++]:previewPoints[b++];
    if(painted && b<previewPoints.size() && previewPoints[b]==point)++b;
    auto& term=painted?result.painted:result.preview;
    const auto eligibility=observe(int32_t(uint32_t(point)),int32_t(point>>32));
    if(eligibility!=PaintEligibility::Eligible && eligibility!=PaintEligibility::Ineligible)term=-1;
    else if(eligibility==PaintEligibility::Eligible && term>=0)++term;
  }
  return result;
}
}
