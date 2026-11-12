#pragma once
#include "df/world.h"
#include "df/interrogation_report.h"
#include "df/curses_text_boxst.h"
#include <optional>
#include <string>
#include <vector>

namespace df3d_justice {
// Native471a1f copies the semantic report vector in storage order. The report
// renderer4789b5 wraps owned strings; never call the Justice menu initializer.
struct IntelligenceReport {uint32_t index=0;std::string title,officer;bool viewed=false;std::vector<std::string> lines,paragraphs;};
inline bool intelligenceReportsReady() {
    if(!df::global::world)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const uint8_t*>(&df::global::world->status.interrogation_reports)!=base+0x24e3938)return false;
    static_assert(offsetof(df::interrogation_report,officer_name)==0x28 && offsetof(df::interrogation_report,details)==0x110);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x471a1f,0x2e,UINT64_C(0x0ad3e6d4e7a715a0)},
            {0x4789b5,0x1a1,UINT64_C(0x7638220d2535d3e0)},
            {0x478c8a,0x4a2,UINT64_C(0x32b85fd7b5d130d2)},
            {0x8e7310,0x121,UINT64_C(0x672cfcd6c9373787)},
            {0xbb9b0,0x80,UINT64_C(0xcc2c8d1b49288e49)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){hash^=base[p.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=p.hash)return false;}
        return true;
    }();
    return pinned;
}
inline std::optional<std::vector<IntelligenceReport>> intelligenceReports(int columns) {
    if(!intelligenceReportsReady() || columns<1 || columns>512)return std::nullopt;
    const auto& source=df::global::world->status.interrogation_reports;
    if(source.size()>65536)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<IntelligenceReport> result;size_t totalBytes=0;
    for(size_t i=0;i<source.size();++i){
        const auto* report=source[i];if(!report || report->title.size()>16384 || report->officer_name.size()>16384 || report->details.size()>4096)return std::nullopt;
        IntelligenceReport row;row.index=uint32_t(i);row.title=report->title;row.officer="Officer: "+report->officer_name;row.viewed=report->flags.bits.viewed;
        df::curses_text_boxst box;
        struct Cleanup {df::curses_text_boxst& box;const uint8_t* base;~Cleanup(){reinterpret_cast<void(*)(std::vector<std::string*>*)>(base+0xbb9b0)(&box.text);}} cleanup{box,base};
        const auto wrap=[&](std::string text){reinterpret_cast<void(*)(df::curses_text_boxst*,std::string*,int32_t)>(base+0x8e7310)(&box,&text,columns);};
        wrap(row.title);wrap("Prepared by "+report->officer_name);
        const auto copy=[&](){for(const auto* line:box.text){if(!line || line->size()>16384)return false;totalBytes+=line->size();if(totalBytes>4*1024*1024)return false;row.lines.push_back(*line);}reinterpret_cast<void(*)(std::vector<std::string*>*)>(base+0xbb9b0)(&box.text);return true;};
        if(!copy())return std::nullopt;row.lines.emplace_back();
        for(const auto* detail:report->details){if(!detail || detail->size()>65536)return std::nullopt;row.paragraphs.push_back(*detail);row.lines.emplace_back();wrap(*detail);if(!copy())return std::nullopt;}
        result.push_back(std::move(row));
    }
    return result;
}
}
