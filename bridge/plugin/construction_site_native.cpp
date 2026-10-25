#include "construction_site_native.h"
#include "lua.h"
#include "DataDefs.h"
#include "df/world.h"
#include "df/building.h"
#include "df/building_bars_verticalst.h"
#include "df/buildreq.h"
#include "df/building_trap_trigger_flag.h"
#include "df/global_objects.h"
#include "modules/Maps.h"
#include <windows.h>
#include <array>
#include <cstring>
#include <memory>
#include <vector>

namespace df3d_construction {
namespace {
uint64_t fingerprint(const uint8_t* p,size_t n) {
    uint64_t h=14695981039346656037ULL;
    while(n--){h^=*p++;h*=1099511628211ULL;}return h;
 }
// Caller owns the DF safe point. The geological fallback calls eb68b0 only;
// it does not select another stream. Preserve the buffer too: a draw at its
// end twists all624 words, so restoring the index alone is insufficient.
struct RandomRestore {
    uint8_t* buffer=nullptr;
    int32_t* index=nullptr;
    int32_t savedIndex=0;
    std::array<uint8_t,0x9c0> saved{};
    bool valid=true;
    RandomRestore(uint8_t* base,bool needed) {
        if(!needed)return;
        const auto stream=*reinterpret_cast<const int16_t*>(base+0x2159084);
        // Native stream push eb6c80 clamps to9 at the ten-stream limit.
        if(stream<0 || stream>=10){valid=false;return;}
        auto* candidate=reinterpret_cast<int32_t*>(base+0x2131b30+stream*4);
        if(*candidate<0 || *candidate>0x9c0 || (*candidate%4)!=0){valid=false;return;}
        index=candidate;savedIndex=*index;buffer=base+0x234e990+stream*0x9c0;
        std::memcpy(saved.data(),buffer,saved.size());
    }
    ~RandomRestore(){if(buffer){std::memcpy(buffer,saved.data(),saved.size());*index=savedIndex;}}
    RandomRestore(const RandomRestore&)=delete;
    RandomRestore& operator=(const RandomRestore&)=delete;
};
}
int verticalBarsConnections(int32_t x,int32_t y,int32_t z) {
    auto* world=df::global::world;
    if(!world || !DFHack::Maps::IsValid() || x<0 || y<0 || z<0 ||
       x>32766 || y>32766 || z>32767 || !DFHack::Maps::isValidTilePos(x,y,z))return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return -1;
    // Immutable executable check once per process; never cache world state.
    static const bool supported=[base] {
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        return pe->Signature==IMAGE_NT_SIGNATURE && pe->FileHeader.Machine==0x8664 &&
            pe->FileHeader.TimeDateStamp==0x6a70a6d9 && pe->OptionalHeader.SizeOfImage==0x2711000 &&
            fingerprint(base+0x59a350,0x6bb)==0xca5f91d406c621f2ULL &&
            fingerprint(base+0x14aa830,0xa4)==0xb97026a0ce075b18ULL &&
            fingerprint(base+0x1436f30,0x2ee)==0x35f498edc3118b77ULL &&
            fingerprint(base+0x5a8320,0x6b)==0x4de04f905e9764e5ULL &&
            fingerprint(base+0x5a8470,0x6b)==0xb75d074f5230b5feULL &&
            fingerprint(base+0x5a8550,0x6b)==0xb7aeac578a4c6d48ULL;
    }();
    if(!supported)return -1;
    using Open=bool (*)(df::world*,int16_t,int16_t,int16_t);
    using Closed=bool (*)(df::building_handler*,int16_t,int16_t,int16_t);
    const auto open=reinterpret_cast<Open>(base+0x14aa830);
    const auto connected=[&](int32_t nx,int32_t ny) {
        // Exact inline draw predicate before graphics access: unavailable/non-open
        // terrain and fortifications connect; dynamic occupancy asks DF's helpers.
        if(!open(world,int16_t(nx),int16_t(ny),int16_t(z)))return true;
        const auto* tile=DFHack::Maps::getTileType(nx,ny,z);
        const auto* occupancy=DFHack::Maps::getTileOccupancy(nx,ny,z);
        if(!tile || !occupancy)return true;
        const auto value=static_cast<uint16_t>(*tile);
        if(value==0x41 || value==0x142 || value==0x143 || value==0x164 || value==0x1b0 || value==0x1ea)return true;
        const auto occupied=occupancy->bits.building;
        if(occupied==6)return true;
        if(occupied==7)for(const uintptr_t rva:{0x5a8470u,0x5a8550u,0x5a8320u})
            if(reinterpret_cast<Closed>(base+rva)(&world->buildings,int16_t(nx),int16_t(ny),int16_t(z)))return true;
        if(occupied!=0)for(const auto* bars:world->buildings.other.BARS_VERTICAL)
            if(bars && bars->centerx==nx && bars->centery==ny && bars->z==z)return true;
        return false;
    };
    return (connected(x,y-1)?1:0)|(connected(x,y+1)?2:0)|
           (connected(x-1,y)?4:0)|(connected(x+1,y)?8:0);
}

int siteSupport(const std::string& family,int32_t x,int32_t y,int32_t z,bool* randomAdvanced,int32_t width,int32_t height) {
    if(randomAdvanced)*randomAdvanced=false;
    const bool perimeter=family=="SinglePerimeter" || family=="BridgePerimeter";
    if(width<1 || height<1 || width>31 || height>31 ||
       (family!="BridgePerimeter" && (width!=1 || height!=1)))return -1;
    const bool door=family=="Door",well=family=="Well",surface=family=="Surface" || family=="FloorTerrain" || family=="OpenTerrain" || perimeter;
    const bool farm=family=="FarmPlot",road=family=="RoadDirt" || family=="RoadPaved";
    if(!surface && !farm && !road && !door && !well && family!="Hatch" && family!="GrateFloor" && family!="BarsFloor")return -1;
    if(x<0 || y<0 || z<0 || x>32767 || y>32767 || z>32767 ||
       !DFHack::Maps::IsValid() || !DFHack::Maps::isValidTilePos(x,y,z) ||
       !DFHack::Maps::getTileBlock(x,y,z) || x+width-1>32767 || y+height-1>32767 ||
       !DFHack::Maps::isValidTilePos(x+width-1,y+height-1,z))return -1;
    auto* b=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(!b)return -1;
    const auto* dos=reinterpret_cast<IMAGE_DOS_HEADER*>(b);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return -1;
    const auto* pe=reinterpret_cast<IMAGE_NT_HEADERS64*>(b+dos->e_lfanew);
    if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=0x8664 ||
       pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000 ||
       fingerprint(b+0xa827b0,0xd5)!=0x30b1875261582ee7ULL ||
       fingerprint(b+0xa62ba0,0xe4)!=0x6fe4fbdbcf6d528dULL ||
       fingerprint(b+0xa82890,0x110)!=0xae2e718156f7299eULL ||
       fingerprint(b+0xa829a0,0x158)!=0x320796f07bcbaf91ULL)return -1;
    if(surface) {
        if(!df::global::world || fingerprint(b+0x14adea0,0xcb4)!=0x1818a722f3967dcbULL)return -1;
        if(perimeter) {
            if(fingerprint(b+0xaa93e0,0x12a)!=0x332a132992fda3c1ULL)return -1;
            using Perimeter=bool (*)(int16_t,int16_t,int16_t,int16_t,int16_t);
            return reinterpret_cast<Perimeter>(b+0xaa93e0)(int16_t(x),int16_t(x+width-1),int16_t(y),int16_t(y+height-1),int16_t(z))?0:6;
        }
        // Narrow terrain predicate, not complete building eligibility. The
        // ordinary validator calls this before its tile-specific exclusions.
        // movement=false bypasses the lazy walkability rebuild.
        using Surface=bool (*)(df::world*,int16_t,int16_t,int16_t,bool,int32_t);
        const bool accepted=reinterpret_cast<Surface>(b+0x14adea0)(df::global::world,int16_t(x),int16_t(y),int16_t(z),false,0);
        if(family=="Surface")return accepted?0:6;
        // a81f40's ordinary terrain branch is not callable independently: its
        // prologue borrows global buildreq. Compose its native surface/ramp/construction
        // predicates and read its fingerprinted stair dispatch table instead.
        // This deliberately stops before water, occupancy and family support.
        if(fingerprint(b+0xa81f40,0x730)!=0x03fd381000773229ULL ||
           fingerprint(b+0x256170,0x249)!=0x4542b797bd603f82ULL ||
           fingerprint(b+0x14abf60,0x9c)!=0x807efbef5608e489ULL ||
           fingerprint(b+0x247210,0x11a)!=0xe6af19c9adee9bcaULL ||
           fingerprint(b+0xa46d90,0x96)!=0x4a7b09cc49d68a8aULL)return -1;
        const auto* tile=DFHack::Maps::getTileType(x,y,z);
        if(!tile)return -1;
        const auto value=static_cast<uint16_t>(*tile);
        if(family=="OpenTerrain") {
            if(fingerprint(b+0x14aa830,0xa4)!=0xb97026a0ce075b18ULL ||
               fingerprint(b+0x1436f30,0x2ee)!=0x35f498edc3118b77ULL)return -1;
            // Loaded-tile branch of a8221f: native surface or open terrain,
            // excluding the native fortification cases before construction refusal.
            using Open=bool (*)(df::world*,int16_t,int16_t,int16_t);
            const bool fortification=value==0x41 || value==0x142 || value==0x143 ||
                value==0x164 || value==0x1b0 || value==0x1ea;
            if(accepted || (!fortification && reinterpret_cast<Open>(b+0x14aa830)(df::global::world,int16_t(x),int16_t(y),int16_t(z))))return 0;
            return reinterpret_cast<Open>(b+0x14abf60)(df::global::world,int16_t(x),int16_t(y),int16_t(z))?19:6;
        }
        const bool stairs=(value>=4 && value<=63 && b[0xa82634+value-4]==0) ||
            value==0x1dd || value==0x1de || value==0x1df ||
            value==0x1ff || value==0x200 || value==0x201;
        using Classifier=bool (*)(uint16_t);
        if(accepted && !stairs && !reinterpret_cast<Classifier>(b+0x256170)(value))return 0;
        using ExistingConstruction=bool (*)(df::world*,int16_t,int16_t,int16_t);
        return reinterpret_cast<ExistingConstruction>(b+0x14abf60)(df::global::world,int16_t(x),int16_t(y),int16_t(z))?19:6;
    }
    if(farm || road) {
        if(!df::global::world ||
           fingerprint(b+0x14b0b00,0x2ca)!=0x7962ccaa7aa5b9daULL ||
           fingerprint(b+0x14b1460,0xb7)!=0xf10a5339f477c759ULL ||
           fingerprint(b+0x14d2130,0x1b0)!=0x3bc8af42e9b7e7c1ULL ||
           fingerprint(b+0x14adea0,0xcb4)!=0x1818a722f3967dcbULL)return -1;
        bool preservesRandom=false;
        if(family=="RoadDirt") {
            const auto* tile=DFHack::Maps::getTileType(x,y,z);
            if(!tile)return -1;
            const auto value=static_cast<uint16_t>(*tile);
            preservesRandom=value==0x22 || value==0x185 || value==0xe3 || value==0x184;
        }
        if(preservesRandom && (fingerprint(b+0x14e100,0x1a7)!=0xedd44282372d3395ULL ||
            fingerprint(b+0xeb68b0,0x1e3)!=0x4bcd46a418e7a7bbULL ||
            fingerprint(b+0xeb6c80,0xb4)!=0x2e88abd8ec00aa99ULL))return -1;
        RandomRestore restore(b,preservesRandom);
        if(!restore.valid)return -1;
        // buildreq::evaluate_buildability uses these coordinate predicates for
        // farm/road terrain before the menu-dependent general tile validator.
        // Their surface predicate passes movement=false/flags=0, bypassing the
        // lazy walkability-group rebuild. No buildreq or redraw state is used.
        using Farm=int32_t (*)(df::world*,int16_t,int16_t,int16_t);
        using Road=int32_t (*)(df::world*,int16_t,int16_t,int16_t,bool);
        const int result=farm ? reinterpret_cast<Farm>(b+0x14b1460)(df::global::world,int16_t(x),int16_t(y),int16_t(z))
            : reinterpret_cast<Road>(b+0x14b0b00)(df::global::world,int16_t(x),int16_t(y),int16_t(z),family=="RoadDirt");
        if(randomAdvanced && restore.index)*randomAdvanced=*restore.index!=restore.savedIndex ||
            std::memcmp(restore.buffer,restore.saved.data(),restore.saved.size())!=0;
        return result==0 || result==6 || (farm && result==20) || (road && result==21) ? result : -1;
    }
    // DF53.16 a81f40 dispatches to coordinate-only support routines for
    // Door, Well and floor openings. They read map tiles without buildreq.
    using Check=int32_t (*)(int16_t,int16_t,int16_t);
    const auto result=reinterpret_cast<Check>(b+(door?0xa827b0:well?0xa829a0:0xa82890))(int16_t(x),int16_t(y),int16_t(z));
    return result==0 || (door && result==8) || (well && result==16) || (!door && result==17) ? result : -1;
}
static int constructionTerrainImpl(int32_t x,int32_t y,int32_t z,int32_t subtype,int32_t x1,int32_t y1,int32_t width,int32_t height,bool routing) {
    if(subtype<0 || subtype>37)return -1;
    if(x1==-1 && y1==-1 && width==1 && height==1){x1=x;y1=y;}
    if(x1<0 || y1<0 || x1>32767 || y1>32767 || width<1 || width>31 || height<1 || height>31 ||
       x<x1 || y<y1 || x>=x1+width || y>=y1+height)return -1;
    // These queries validate coordinates and fingerprint the native predicates,
    // including a81f40 and its dispatch tables. No buildreq state is consulted.
    const int floor=siteSupport("FloorTerrain",x,y,z);
    const int open=siteSupport("OpenTerrain",x,y,z);
    const int perimeter=routing?0:siteSupport("BridgePerimeter",x1,y1,z,nullptr,width,height);
    if(floor<0 || open<0 || perimeter<0)return -1;
    auto* b=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    int32_t mapX=0,mapY=0,mapZ=0;
    DFHack::Maps::getTileSize(mapX,mapY,mapZ);
    // a81fbf..a8205b: only wall/fortification/reinforced-wall selected
    // subtypes require five surface tiles to the edge. Underground is exempt.
    if(fingerprint(b+0x7dc40,0x86)!=0x396b58fb95c29f02ULL)return -1;
    using Designation=uint32_t (*)(df::world*,int16_t,int16_t,int16_t);
    const auto designation=reinterpret_cast<Designation>(b+0x7dc40)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    if(!routing && (designation&(1U<<9)))return 7; // outer native hidden-tile rejection precedes all terrain stages
    if((subtype<=1 || subtype==37) && !(designation&(1U<<15)) &&
       (x<5 || y<5 || x>=mapX-5 || y>=mapY-5))return 14;
    // a82061..a8208a, before terrain/liquid: these selected construction
    // subtypes need the level above. The immediate is covered by a81f40's hash.
    if(z==mapZ-1 && ((0x200000006aULL>>subtype)&1))return 18;
    const auto value=static_cast<uint16_t>(*DFHack::Maps::getTileType(x,y,z));
    using Existing=bool (*)(df::world*,int16_t,int16_t,int16_t);
    const bool existing=reinterpret_cast<Existing>(b+0x14abf60)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    // a8259f: use DF's own replacement dispatch. Group1 is the stair
    // exception for UpDownStair (5); group2 requires removal.
    bool replacement=true;
    if(existing) {
        if(value<0x1d9 || value>0x2b6)replacement=false;
        else {
            const auto group=b[0xa826c8+value-0x1d9];
            if(group>2)return -1;
            replacement=group==0 || (group==1 && subtype==5);
        }
    }
    // The native validator checks water, then magma, before replacement.
    // Both leaf routines read map designation only and have no callees.
    if(fingerprint(b+0x247d80,0xbf)!=0xc034bea0c49abf36ULL ||
       fingerprint(b+0x2c3a90,0xbf)!=0x4ba71cffd1601553ULL)return -1;
    using Depth=uint8_t (*)(df::world*,int16_t,int16_t,int16_t);
    const auto water=reinterpret_cast<Depth>(b+0x247d80)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    const auto magma=reinterpret_cast<Depth>(b+0x2c3a90)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    if(fingerprint(b+0x68010,0x86)!=0x388d6b4f5c5f658eULL)return -1;
    const auto occupancy=reinterpret_cast<Designation>(b+0x68010)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    bool occupied=(occupancy&7)!=0;
    if(occupied) {
        // a82460..a82497 exempts an actual Construction at this center.
        // Match DF's all-building scan and virtual type query; no UI state.
        for(auto* building:df::global::world->buildings.all) {
            if(building->getType()==df::building_type::Construction &&
               building->centerx==x && building->centery==y && building->z==z) {
                occupied=false;break;
            }
        }
    }
    const auto finish=[&](int terrain) {return terrain?terrain:water>=2?10:magma?11:occupied?12:replacement?0:19;};
    if(finish(floor)==0)return 0;
    // 269b00 routing tries native modes0,1,4 directly. Mode1 has no
    // selection perimeter requirement; mode4 also admits raw open/ramp-top.
    if(routing)return finish((open==0 || value==1 || value==0x20)?0:open);
    const auto openResult=finish(open);
    if(openResult!=0)return openResult;
    if(perimeter==0)return 0;
    // Native mode4's explicit open-space/ramp-top branch bypasses the
    // below-stair requirement. All other terrain needs an up or up/down stair.
    if(value==1 || value==0x20)return finish(0);
    const auto* below=z>0?DFHack::Maps::getTileType(x,y,z-1):nullptr;
    bool stairBelow=false;
    if(below) {
        const auto v=static_cast<uint16_t>(*below);
        // Constants are the native a82326..a823e6 classification, covered by
        // a81f40's fingerprint above, not Godot tile-shape approximations.
        stairBelow=(v<=0x36 && ((0x48024008000010ULL>>v)&1)) ||
            (v<=0x34 && ((0x12009002000040ULL>>v)&1)) ||
            v==0x39 || v==0x3c || v==0x3f || v==0x1df || v==0x201 ||
            v==0x37 || v==0x3a || v==0x3d || v==0x1dd || v==0x1ff;
    }
    if(open==0 && stairBelow)return finish(0);
    return existing?19:6;
}
int constructionTerrain(int32_t x,int32_t y,int32_t z,int32_t subtype,int32_t x1,int32_t y1,int32_t width,int32_t height) {
    return constructionTerrainImpl(x,y,z,subtype,x1,y1,width,height,false);
}
int trackTerrain(int32_t x,int32_t y,int32_t z) {
    return constructionTerrainImpl(x,y,z,21,x,y,1,1,true);
}
// Protected native-reference capture only. Runtime adapters must use the
// independent trackTerrain predicate above, never this menu-dependent oracle.
int trackTerrainOracle(int32_t x,int32_t y,int32_t z) {
    if(!df::global::pause_state || !*df::global::pause_state || !df::global::buildreq ||
       df::global::buildreq->building_type!=df::building_type::Construction ||
       df::global::buildreq->building_subtype!=21 || siteSupport("FloorTerrain",x,y,z)<0)return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Check=int32_t (*)(int16_t,int16_t,int16_t,bool,int32_t,bool,bool);
    auto check=reinterpret_cast<Check>(base+0xa81f40);
    for(int mode:{0,1,4})if(check(int16_t(x),int16_t(y),int16_t(z),true,mode,true,false)==0)return 0;
    return 1;
}
int areaConnectivity(const std::string& family,int32_t x,int32_t y,int32_t z,int32_t width,int32_t height) {
    if((family!="FarmPlot" && family!="RoadDirt" && family!="RoadPaved") || width<1 || width>31 || height<1 || height>31 ||
       x<0 || y<0 || x>32767-width+1 || y>32767-height+1 ||
       siteSupport("FarmPlot",x,y,z)<0 || siteSupport("RoadDirt",x,y,z)<0)return -1;
    for(int dx=0;dx<width;++dx)for(int dy=0;dy<height;++dy)
        if(!DFHack::Maps::isValidTilePos(x+dx,y+dy,z) || !DFHack::Maps::getTileBlock(x+dx,y+dy,z))return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(fingerprint(base+0x3c0c30,0x11ac)!=0x4e65d6bc9dfce908ULL ||
       fingerprint(base+0x3c2640,0x427)!=0xf375f61cace77e62ULL ||
       fingerprint(base+0x3c1e60,0x7b7)!=0xfcbc3593568b4f03ULL)return -1;
    // These three footprint branches read only the supplied request. The
    // connectivity routine reads native farm/road terrain, using an owned
    // 31x31 visited grid and the shared two-frontier coordinate scratch.
    // At most961 cells can be queued, below the native120000-entry capacity.
    std::unique_ptr<df::buildreq> request(df::allocate<df::buildreq>());
    request->building_type=family=="FarmPlot"?df::building_type::FarmPlot:family=="RoadDirt"?df::building_type::RoadDirt:df::building_type::RoadPaved;
    request->building_subtype=-1;request->custom_type=-1;request->direction=0;
    request->selection_pos=df::coord(x,y,z);request->pos=df::coord(x+width-1,y+height-1,z);
    struct FrontierRestore {
        uint8_t* target;std::vector<uint8_t> saved;
        explicit FrontierRestore(uint8_t* p):target(p),saved(p,p+2*120000*12){}
        ~FrontierRestore(){std::memcpy(target,saved.data(),saved.size());}
    } frontier(base+0x1bb3700);
    RandomRestore random(base,true);if(!random.valid)return -1;
    // Outer validator3c0d62 scans every tile through road then farm predicates,
    // even after finding eligible terrain. Preserve that native RNG sequence.
    using Road=int32_t (*)(df::world*,int16_t,int16_t,int16_t,bool);
    using Farm=int32_t (*)(df::world*,int16_t,int16_t,int16_t);
    bool any=false;
    for(int dx=0;dx<width;++dx)for(int dy=0;dy<height;++dy) {
        const int road=reinterpret_cast<Road>(base+0x14b0b00)(df::global::world,int16_t(x+dx),int16_t(y+dy),int16_t(z),family=="RoadDirt");
        const int farm=reinterpret_cast<Farm>(base+0x14b1460)(df::global::world,int16_t(x+dx),int16_t(y+dy),int16_t(z));
        any=any || (family=="FarmPlot"?farm==0:road==0);
    }
    if(!any)return 0; // Empty eligible terrain is a terrain refusal, not Disconnected.

    using Check=bool (*)(df::buildreq*);
    return reinterpret_cast<Check>(base+0x3c2640)(request.get())?22:0;
}
static int floorBuildingTile(int type,int32_t x,int32_t y,int32_t z,bool opening=false) {
    if(type<0)return -1;
    const int floor=siteSupport(opening?"OpenTerrain":"FloorTerrain",x,y,z);
    if(floor<0)return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(fingerprint(base+0x3c0c30,0x11ac)!=0x4e65d6bc9dfce908ULL ||
       fingerprint(base+0xa82670,0x4a)!=0x4eca7547875adba8ULL ||
       fingerprint(base+0x7dc40,0x86)!=0x396b58fb95c29f02ULL ||
       fingerprint(base+0x247d80,0xbf)!=0xc034bea0c49abf36ULL ||
       fingerprint(base+0x2c3a90,0xbf)!=0x4ba71cffd1601553ULL ||
       fingerprint(base+0x68010,0x86)!=0x388d6b4f5c5f658eULL)return -1;
    using Bits=uint32_t (*)(df::world*,int16_t,int16_t,int16_t);
    using Depth=uint8_t (*)(df::world*,int16_t,int16_t,int16_t);
    const auto designation=reinterpret_cast<Bits>(base+0x7dc40)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    if(designation&(1U<<9))return 7;
    int32_t mapX=0,mapY=0,mapZ=0;DFHack::Maps::getTileSize(mapX,mapY,mapZ);
    if(type!=19 && !(designation&(1U<<15)) && (x<5 || y<5 || x>=mapX-5 || y>=mapY-5))return 14;
    if(floor)return floor;
    if(reinterpret_cast<Depth>(base+0x247d80)(df::global::world,int16_t(x),int16_t(y),int16_t(z))>=2)return 10;
    if(reinterpret_cast<Depth>(base+0x2c3a90)(df::global::world,int16_t(x),int16_t(y),int16_t(z)))return 11;
    if(reinterpret_cast<Bits>(base+0x68010)(df::global::world,int16_t(x),int16_t(y),int16_t(z))&7)return 12;
    // Read the supported native dispatch, with caller-owned type. Never read
    // buildreq: a81f40 itself cannot be called safely by the runtime service.
    if(type>45)return 0; // Native a824c5 bypasses the table for later building types.
    switch(base[0xa8268c+type]) {
    case 1:return x<10 || y<10 || x>=mapX-10 || y>=mapY-10?14:0;
    case 0:return designation&(1U<<16)?13:0;
    case 2:return siteSupport("Door",x,y,z);
    case 3:return siteSupport("Well",x,y,z);
    case 5:return siteSupport("Hatch",x,y,z);
    case 6:return 0;
    default:return -1;
    }
}
int bridgeTile(int32_t x,int32_t y,int32_t z,bool anchor) {
    // Bridge bypasses the general five-tile map edge check. Native raising
    // anchors use the full mode0 decision after mode1 has accepted the tile.
    const int open=floorBuildingTile(19,x,y,z,true);
    if(open!=0 || !anchor)return open;
    const int floor=floorBuildingTile(19,x,y,z);
    return floor<0?-1:floor?5:0;
}
int specialTile(const std::string& key,int32_t x,int32_t y,int32_t z,bool openTerrain) {
    // Caller supplies the independently computed native hookup result (machines)
    // or whether this tile is off-center (magma recipes). Whole-placement
    // hookup warnings and recipe-specific footprint effects remain separate.
    const int type=key=="ScrewPump"?33:key=="GearAssembly"?40:
        key=="AxleHorizontal"?41:key=="AxleVertical"?42:key=="WaterWheel"?43:
        key=="Windmill"?44:key=="Rollers"?50:
        key=="Workshop:Millstone" || key=="Workshop:MagmaForge"?13:
        key=="Furnace:MagmaSmelter" || key=="Furnace:MagmaGlassFurnace" || key=="Furnace:MagmaKiln"?5:-1;
    return floorBuildingTile(type,x,y,z,openTerrain);
}
int openingTile(const std::string& family,int32_t x,int32_t y,int32_t z) {
    // Native mode1 for openings, mode0 for Support. AnimalTrap's separate
    // whole-selection perimeter refusal is not represented by this tile code.
    const int type=family=="Well"?18:family=="AnimalTrap"?24:
        family=="Hatch"?35:family=="GrateFloor"?37:family=="BarsFloor"?39:
        family=="Support"?25:-1;
    return floorBuildingTile(type,x,y,z,family!="Support");
}
int furnitureTile(const std::string& family,int32_t x,int32_t y,int32_t z) {
    // Only the mode0 families covered by the protected oracle are admitted.
    const int type=family=="Chair"?0:family=="Bed"?1:family=="Door"?8:
        family=="Weaponrack"?11:family=="Statue"?15:family=="Cage"?28:
        family=="Table"?2:
        family=="Box"?10:
        family=="Cabinet"?14:
        family=="Coffin"?3:
        family=="Slab"?46:
        family=="TractionBench"?45:
        family=="Bookcase"?52:
        family=="DisplayFurniture"?53:
        family=="OfferingPlace"?54:
        family=="Instrument"?51:
        family=="GrateWall"?36:
        family=="BarsVertical"?38:
        family=="WindowGlass"?16:
        family=="WindowGem"?17:-1;
    return floorBuildingTile(type,x,y,z);
}
int ordinaryTile(const std::string& key,int32_t x,int32_t y,int32_t z) {
    // Explicit recipe admission excludes magma, machines and opening variants.
    const int type=key=="ArcheryTarget"?26:
        key=="Armorstand"?12:
        key=="Chain"?27:
        key=="Floodgate"?9:
        key=="Furnace:GlassFurnace"?5:
        key=="Furnace:Kiln"?5:
        key=="Furnace:Smelter"?5:
        key=="Furnace:WoodFurnace"?5:
        key=="Hive"?49:
        key=="NestBox"?48:
        key=="SiegeEngine:Ballista"?22:
        key=="SiegeEngine:BoltThrower"?22:
        key=="SiegeEngine:Catapult"?22:
        key=="TradeDepot"?6:
        key=="Trap:CageTrap"?23:
        key=="Trap:Lever"?23:
        key=="Trap:PressurePlate"?23:
        key=="Trap:StoneFallTrap"?23:
        key=="Trap:TrackStop"?23:
        key=="Trap:WeaponTrap"?23:
        key=="Weapon"?31:
        key=="Workshop:Ashery"?13:
        key=="Workshop:Bowyers"?13:
        key=="Workshop:Butchers"?13:
        key=="Workshop:Carpenters"?13:
        key=="Workshop:Clothiers"?13:
        key=="Workshop:Craftsdwarfs"?13:
        key=="Workshop:Custom:SCREW_PRESS"?13:
        key=="Workshop:Custom:SOAP_MAKER"?13:
        key=="Workshop:Dyers"?13:
        key=="Workshop:Farmers"?13:
        key=="Workshop:Fishery"?13:
        key=="Workshop:Jewelers"?13:
        key=="Workshop:Kennels"?13:
        key=="Workshop:Kitchen"?13:
        key=="Workshop:Leatherworks"?13:
        key=="Workshop:Loom"?13:
        key=="Workshop:Masons"?13:
        key=="Workshop:Mechanics"?13:
        key=="Workshop:MetalsmithsForge"?13:
        key=="Workshop:Quern"?13:
        key=="Workshop:Siege"?13:
        key=="Workshop:Still"?13:
        key=="Workshop:Tanners"?13:-1;
    return floorBuildingTile(type,x,y,z);
}
int extentTile(const std::string& family,int32_t x,int32_t y,int32_t z,int* rawTerrain) {
    if(rawTerrain)*rawTerrain=-1;
    if(family!="FarmPlot" && family!="RoadDirt" && family!="RoadPaved")return -1;
    const int raw=siteSupport(family,x,y,z);
    if(raw<0)return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(fingerprint(base+0x3c0c30,0x11ac)!=0x4e65d6bc9dfce908ULL ||
       fingerprint(base+0xa81f40,0x730)!=0x03fd381000773229ULL ||
       fingerprint(base+0xa82670,0x4a)!=0x4eca7547875adba8ULL ||
       fingerprint(base+0x7dc40,0x86)!=0x396b58fb95c29f02ULL ||
       fingerprint(base+0x247d80,0xbf)!=0xc034bea0c49abf36ULL ||
       fingerprint(base+0x2c3a90,0xbf)!=0x4ba71cffd1601553ULL ||
       fingerprint(base+0x68010,0x86)!=0x388d6b4f5c5f658eULL)return -1;
    if(rawTerrain)*rawTerrain=raw;
    // Outer3c126e/3c11d0 uses raw terrain before the general tile result.
    // Its area-level SKIP decision belongs to the caller, not this tile query.
    if(raw)return raw;
    using Bits=uint32_t (*)(df::world*,int16_t,int16_t,int16_t);
    using Depth=uint8_t (*)(df::world*,int16_t,int16_t,int16_t);
    int32_t mapX=0,mapY=0,mapZ=0;DFHack::Maps::getTileSize(mapX,mapY,mapZ);
    const auto designation=reinterpret_cast<Bits>(base+0x7dc40)(df::global::world,int16_t(x),int16_t(y),int16_t(z));
    // a81fa7 exempts roads20/21; farm4 uses the underground-aware five-tile edge.
    if(family=="FarmPlot" && !(designation&(1U<<15)) &&
       (x<5 || y<5 || x>=mapX-5 || y>=mapY-5))return 14;
    const int floor=siteSupport("FloorTerrain",x,y,z);
    if(floor)return floor;
    // Native mode0 order. Unlike Construction, these families have no occupied
    // construction exception and dispatch directly to success at a82605.
    if(reinterpret_cast<Depth>(base+0x247d80)(df::global::world,int16_t(x),int16_t(y),int16_t(z))>=2)return 10;
    if(reinterpret_cast<Depth>(base+0x2c3a90)(df::global::world,int16_t(x),int16_t(y),int16_t(z)))return 11;
    if(reinterpret_cast<Bits>(base+0x68010)(df::global::world,int16_t(x),int16_t(y),int16_t(z))&7)return 12;
    return 0;
}
int farmWarning(int32_t x,int32_t y,int32_t z,int32_t width,int32_t height,const std::vector<uint8_t>& eligible) {
    if(width<1 || width>31 || height<1 || height>31 || x<0 || y<0 || x>32767 || y>32767 ||
       x+width-1>32767 || y+height-1>32767 || eligible.size()!=size_t(width*height) || siteSupport("FarmPlot",x,y,z)<0)return -1;
    for(auto value:eligible)if(value>1)return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(fingerprint(base+0x3c0c30,0x11ac)!=0x4e65d6bc9dfce908ULL ||
       fingerprint(base+0x54c3c0,0x6b)!=0xdc232cdf5ce19964ULL ||
       fingerprint(base+0x7dc40,0x86)!=0x396b58fb95c29f02ULL)return -1;
    // Native 3c1789..3c188a accumulates underground soil/mud only for
    // accepted tiles (edi==0). Farm type4 bypasses footprint exclusion54c3d5.
    // The caller supplies eligibility; this query never borrows buildreq.
    // Validate the whole owned rectangle before returning even an early match.
    for(int dx=0;dx<width;++dx)for(int dy=0;dy<height;++dy)
        if(!DFHack::Maps::isValidTilePos(x+dx,y+dy,z) || !DFHack::Maps::getTileBlock(x+dx,y+dy,z))return -1;
    using Designation=uint32_t (*)(df::world*,int16_t,int16_t,int16_t);
    using Soil=bool (*)(df::world*,int16_t,int16_t,int16_t);
    for(int dx=0;dx<width;++dx)for(int dy=0;dy<height;++dy)
        if(eligible[size_t(dx*height+dy)] &&
           (reinterpret_cast<Designation>(base+0x7dc40)(df::global::world,int16_t(x+dx),int16_t(y+dy),int16_t(z))&(1U<<15)) &&
           reinterpret_cast<Soil>(base+0x14d2130)(df::global::world,int16_t(x+dx),int16_t(y+dy),int16_t(z)))return 0;
    return 1;
}
int pressureTrigger(uint32_t flags) {
    if(flags>63)return -1;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return -1;
    const auto* dos=reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return -1;
    const auto* pe=reinterpret_cast<IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
    if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=0x8664 ||
       pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000 ||
       fingerprint(base+0x3c0c30,0x11ac)!=0x4e65d6bc9dfce908ULL ||
       fingerprint(base+0x3c0e97,0x18)!=0xea8f061448b130e7ULL)return -1;
    // Native TEST at3c0ea6 reads global buildreq flags, so cannot be called.
    // Its fingerprinted immediate mask is applied to caller-owned flag bits.
    // Citizens/reset behavior is selected by DF's mask, not a local trigger list.
    return (flags&base[0x3c0eac])?0:1;
}
int nativeSiteSupport(lua_State* L) {
    int32_t p[3]{};bool valid=lua_istable(L,1);
    if(valid){int i=0;for(const auto* key:{"x","y","z"}) {
        lua_getfield(L,1,key);auto v=lua_tointeger(L,-1);
        valid=valid && lua_isinteger(L,-1) && v>=0 && v<=32767;
        p[i++]=v>=0 && v<=32767 ? int32_t(v) : -1;lua_pop(L,1);
    }}
    int32_t size[2]={1,1};
    for(int i=0;i<2;++i)if(!lua_isnoneornil(L,3+i)) {
        const auto v=lua_tointeger(L,3+i);
        valid=valid && lua_isinteger(L,3+i) && v>=1 && v<=31;
        size[i]=v>=1 && v<=31?int32_t(v):0;
    }
    const std::string family=lua_type(L,2)==LUA_TSTRING?lua_tostring(L,2):"";
    if(family=="PressurePlateTrigger") {
        uint32_t flags=0;
        valid=valid && lua_istable(L,5);
        using F=df::building_trap_trigger_flag;
        const char* keys[]={"units","water","magma","citizens","resets","track"};
        const uint32_t masks[]={F::mask_units,F::mask_water,F::mask_magma,F::mask_citizens,F::mask_resets,F::mask_track};
        if(valid)for(int i=0;i<6;++i) {
            lua_getfield(L,5,keys[i]);valid=valid && lua_isboolean(L,-1);
            if(lua_toboolean(L,-1))flags|=masks[i];lua_pop(L,1);
        }
        const int result=valid?pressureTrigger(flags):-1;
        lua_pushboolean(L,result==0);lua_pushstring(L,result==1?"Need trigger type":"");
        lua_pushboolean(L,result>=0);return 3;
    }
    if(family=="FarmPlotWarning") {
        std::vector<uint8_t> eligible;
        valid=valid && lua_istable(L,5) && lua_rawlen(L,5)==size_t(size[0]*size[1]);
        if(valid)for(int i=1;i<=size[0]*size[1];++i) {
            lua_rawgeti(L,5,i);const auto v=lua_tointeger(L,-1);
            valid=valid && lua_isinteger(L,-1) && (v==0 || v==1);
            eligible.push_back(v==1?1:0);lua_pop(L,1);
        }
        const int warning=valid?farmWarning(p[0],p[1],p[2],size[0],size[1],eligible):-1;
        lua_pushboolean(L,warning==1);
        lua_pushstring(L,warning==1?"No mud/soil for farm\nMud is left by water":"");
        lua_pushboolean(L,warning>=0);return 3;
    }
    int32_t construction[3]{};
    if(family=="ConstructionTerrain")for(int i=0;i<3;++i) {
        const auto v=lua_tointeger(L,5+i);
        valid=valid && lua_isinteger(L,5+i) && v>=0 && v<=(i==0?37:32767);
        construction[i]=v>=0 && v<=32767?int32_t(v):-1;
    }
    const bool area=family=="FarmPlotConnectivity" || family=="RoadDirtConnectivity" || family=="RoadPavedConnectivity";
    const bool extent=family=="FarmPlotTile" || family=="RoadDirtTile" || family=="RoadPavedTile";
    const bool special=family.size()>11 && family.compare(family.size()-11,11,"SpecialTile")==0;
    if(special || family=="BridgeTile")valid=valid && lua_isboolean(L,5);
    const bool opening=family.size()>11 && family.compare(family.size()-11,11,"OpeningTile")==0;
    const bool ordinary=family.size()>12 && family.compare(family.size()-12,12,"OrdinaryTile")==0;
    const bool furniture=family.size()>13 && family.compare(family.size()-13,13,"FurnitureTile")==0;
    int raw=-1;
    const auto result=!valid?-1:family=="BridgeTile"?bridgeTile(p[0],p[1],p[2],lua_toboolean(L,5)!=0):special?specialTile(family.substr(0,family.size()-11),p[0],p[1],p[2],lua_toboolean(L,5)!=0):opening?openingTile(family.substr(0,family.size()-11),p[0],p[1],p[2]):ordinary?ordinaryTile(family.substr(0,family.size()-12),p[0],p[1],p[2]):furniture?furnitureTile(family.substr(0,family.size()-13),p[0],p[1],p[2]):extent?extentTile(family.substr(0,family.size()-4),p[0],p[1],p[2],&raw):area?areaConnectivity(family.substr(0,family.size()-12),p[0],p[1],p[2],size[0],size[1]):family=="ConstructionTerrain"
        ?constructionTerrain(p[0],p[1],p[2],construction[0],construction[1],construction[2],size[0],size[1])
        :family=="TrackTerrain"?trackTerrain(p[0],p[1],p[2]):siteSupport(family,p[0],p[1],p[2],nullptr,size[0],size[1]);
    lua_pushboolean(L,result==0);
    // Verbatim native refusal text; see construction site-support fixtures.
    lua_pushstring(L,result==5?"Needs to be anchored on edge":result==22?"Disconnected":result==6 && (family=="SinglePerimeter" || family=="BridgePerimeter")?"Needs walkable perimeter":result==7?"Hidden, cannot build at this location":result==12?"Building present":result==13?"Must be inside":result==14?"Too close to edge":result==18?"Cannot build at highest level":result==10?"Water at this location":result==11?"Lava/Magma at this location":result==19?"Must remove construction":result==6?"Blocked at this location":result==20?"Need soil or mud at location":result==21?"Need soil at location":result==8?"Needs adjacent wall":result==16?"Needs open space":result==17?"Surrounded by empty space":"");lua_pushboolean(L,result>=0);
    if(extent){lua_pushboolean(L,raw==0);return 4;}return 3;
}
}
