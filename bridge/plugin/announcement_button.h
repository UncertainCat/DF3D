#pragma once
#include <string>
#include <vector>
#include <utility>
#include <cstdlib>
namespace df3d_session {
// Match the observed DF53 passive More/Okay controls, not an arbitrary native label.
// Screen cells are supplied by the native adapter only at acknowledgment time.
inline std::pair<int,int> passiveAnnouncementButton(const std::vector<std::string>& rows,const std::string& anchor,int textHeight,size_t popupCount) {
 if(popupCount==0||popupCount>256)return {-1,-1};
 const char* label=popupCount==1?"Okay":"More";
 if(rows.empty()||rows.size()>256||anchor.empty()||anchor.size()>48||textHeight<0||textHeight>128)return {-1,-1};
 const int width=int(rows.front().size()),height=int(rows.size());
 if(width<32||width>512||size_t(width)*rows.size()>32768)return {-1,-1};
 const int left=width/4,right=3*width/4;
 int anchorY=-1,buttonY=-1,buttonX=-1;
 for(int y=0;y<height;++y) {
  if(int(rows[y].size())!=width)return {-1,-1};
  const auto center=rows[y].substr(left,right-left);
  if(y>=height/4&&y<=3*height/4&&center.find(anchor)!=std::string::npos) {
   if(anchorY>=0)return {-1,-1};
   anchorY=y;
  }
  const auto first=center.find_first_not_of(' '),last=center.find_last_not_of(' ');
  if(first!=std::string::npos&&center.substr(first,last-first+1)==label) {
   const int x=left+int(first)+2;
   if(std::abs(x-width/2)>4)continue;
   if(buttonY>=0)return {-1,-1};
   buttonY=y;buttonX=x;
  }
 }
 if(anchorY<0||buttonY<=anchorY||buttonY>anchorY+textHeight+6)return {-1,-1};
 return {buttonX,buttonY};
}
}
