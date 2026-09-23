#pragma once
#include <string>
#include <utility>
#include <vector>
namespace df3d_session {
inline bool petitionRowsValid(const std::vector<std::string>& rows) {
  if(rows.empty()||rows.size()>256||rows.front().size()<32||rows.front().size()>512||rows.size()*rows.front().size()>32768)return false;
  for(const auto& row:rows)if(row.size()!=rows.front().size())return false;
  return true;
}
inline std::pair<int,int> uniquePetitionText(const std::vector<std::string>& rows,const std::string& text) {
  std::pair<int,int> found{-1,-1};if(text.empty())return found;
  for(size_t y=0;y<rows.size();++y)for(size_t x=rows[y].find(text);x!=std::string::npos;x=rows[y].find(text,x+1)) {
    if((x&&rows[y][x-1]!=' ')||(x+text.size()<rows[y].size()&&rows[y][x+text.size()]!=' '))continue;
    if(found.first>=0)return {-1,-1};
    found={int(x),int(y)};
  }
  return found;
}
inline std::pair<int,int> petitionLauncher(const std::vector<std::string>& rows) {
  if(!petitionRowsValid(rows))return {-1,-1};
  const auto p=uniquePetitionText(rows,"PETITIONS");
  return p.first<0?p:std::make_pair(p.first+4,p.second);
}
inline std::pair<int,int> petitionDecisionButton(const std::vector<std::string>& rows,const std::string& applicant,bool approve) {
  if(!petitionRowsValid(rows)||applicant.empty()||applicant.size()>256)return {-1,-1};
  const auto name=uniquePetitionText(rows,applicant),q=uniquePetitionText(rows,"Do you approve this request?"),yes=uniquePetitionText(rows,"Approve"),no=uniquePetitionText(rows,"Deny");
  if(name.first<0||q.first<0||yes.first<0||no.first<0||q.second<=name.second||q.second-name.second>64||yes.second!=no.second||yes.second<=q.second||yes.second>q.second+4||yes.first<q.first||no.first<=yes.first+7||no.first>yes.first+20)return {-1,-1};
  auto row=rows[yes.second];row.replace(yes.first,7,7,' ');row.replace(no.first,4,4,' ');
  if(row.find_first_not_of(' ')!=std::string::npos)return {-1,-1};
  return approve?std::make_pair(yes.first+3,yes.second):std::make_pair(no.first+1,no.second);
}
}
