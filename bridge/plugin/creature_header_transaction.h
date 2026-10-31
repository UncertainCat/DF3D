#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace df3d_creature {
// Raw DF strings; conversion is performed once at the transport boundary.
// The world epoch is validated independently by the command dispatcher.
struct HeaderEditSnapshot {
    int32_t unitId=-1,histFigureId=-1;
    bool hasFigure=false;
    std::string nickname,profession,figureNickname;
    uint64_t revision=0;
};
inline uint64_t headerEditRevision(const HeaderEditSnapshot& value) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t b){hash^=b;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){byte(uint8_t(n));n>>=8;}};
    number(value.unitId);number(value.histFigureId);byte(value.hasFigure);
    for(const auto* text:{&value.nickname,&value.profession,&value.figureNickname}) {
        number(text->size());for(unsigned char b:*text)byte(b);
    }
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
enum class HeaderEditOutcome:uint8_t {Rejected,Completed,Stale,Unknown};
struct HeaderEditResult {
    HeaderEditOutcome outcome=HeaderEditOutcome::Rejected;
    bool mutated=false;
    std::optional<HeaderEditSnapshot> receipt;
};
inline bool validHeaderEditSnapshot(const HeaderEditSnapshot& value) {
    return value.unitId>=0 && value.histFigureId>=-1 &&
        (!value.hasFigure || value.histFigureId>=0) &&
        (value.hasFigure || value.figureNickname.empty()) &&
        value.nickname.size()<=512 && value.profession.size()<=512 &&
        value.figureNickname.size()<=512 && value.revision==headerEditRevision(value);
}
// At one safe point, caller supplies a freshly observed visible target and
// checks world epoch. Apply=false guarantees no effects. Exceptions or failed
// post-write observation are Unknown; this function never retries a write.
template<class Apply,class Observe>
HeaderEditResult finishHeaderNameEdit(const HeaderEditSnapshot& before,uint64_t expectedRevision,
                                     bool profession,const std::string& bytes,Apply apply,Observe observe) {
    HeaderEditResult result;
    if(!expectedRevision || !validHeaderEditSnapshot(before) || bytes.size()>30 ||
       bytes.find('\0')!=std::string::npos)return result;
    if(before.revision!=expectedRevision){result.outcome=HeaderEditOutcome::Stale;return result;}
    try {
        auto expected=before;
        auto& target=profession?expected.profession:expected.nickname;
        if(target==bytes) {
            result.receipt=before;result.outcome=HeaderEditOutcome::Completed;return result;
        }
        target=bytes;
        if(!profession && expected.hasFigure)expected.figureNickname=bytes;
        expected.revision=headerEditRevision(expected);
        result.mutated=true;result.outcome=HeaderEditOutcome::Unknown;
        if(!apply(bytes)){result.mutated=false;result.outcome=HeaderEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !validHeaderEditSnapshot(*after) || after->unitId!=expected.unitId ||
           after->histFigureId!=expected.histFigureId || after->hasFigure!=expected.hasFigure ||
           after->nickname!=expected.nickname || after->profession!=expected.profession ||
           after->figureNickname!=expected.figureNickname)return result;
        result.receipt=std::move(after);result.outcome=HeaderEditOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}
}
