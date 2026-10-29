#include "doctest.h"
#include "../bridge/plugin/farm_transaction.h"
#include <string>
#include <vector>
#include <algorithm>

namespace {
struct Choice {int32_t id;std::string name;bool seedsAvailable,currentSeasonWarning;std::string rawId;};
struct Snapshot {
    std::string customName="",headerName="Farm Plot";
    bool removing=false,removalSuspended=false,removalHasWorker=false;
    int32_t buildingId=227,selectedSeason=1,currentSeason=1;
    uint64_t revision=0;
    int32_t currentFertilization=0,maxFertilization=29,pendingFertilization=0;
    bool seasonalFertilization=true;
    std::vector<int32_t> seasonalCrops{173,175,-1,176};
    std::vector<Choice> choices{{175,"Pig tails",true,false,"GRASS_TAIL_PIG"},{176,"Sweet pods",false,true,"POD_SWEET"}};
};
}
TEST_CASE("farm content revision tracks semantic fields and preserves identical receipts") {
    Snapshot original;const auto base=df3d_production::farmRevision(original);
    REQUIRE(base>0);CHECK(base<=INT64_MAX);
    for(int change=0;change<20;++change) {
        auto value=original;
        switch(change) {
        case 0:++value.buildingId;break;
        case 1:++value.selectedSeason;break;
        case 2:++value.currentSeason;break;
        case 3:value.seasonalCrops[3]=-1;break;
        case 4:++value.choices[0].id;break;
        case 5:value.choices[0].name="different";break;
        case 6:value.choices[0].seedsAvailable=false;break;
        case 7:value.choices[0].currentSeasonWarning=true;break;
        case 8:std::reverse(value.choices.begin(),value.choices.end());break;
        case 9:value.choices.pop_back();break;
        case 10:++value.currentFertilization;break;
        case 11:++value.maxFertilization;break;
        case 12:++value.pendingFertilization;break;
        case 13:value.seasonalFertilization=false;break;
        case 14:value.choices[0].rawId="DIFFERENT";break;
        case 15:value.customName="name";break;
        case 16:value.headerName="Name";break;
        case 17:value.removing=true;break;
        case 18:value.removalSuspended=true;break;
        case 19:value.removalHasWorker=true;break;
        }
        CAPTURE(change);CHECK(df3d_production::farmRevision(value)!=base);
        CHECK(df3d_production::farmRevision(original)==base);
    }
    original.revision=base;CHECK(df3d_production::farmRevision(original)==base);
}
TEST_CASE("farm transactions never retry effects or retain unverifiable completion authority") {
    using namespace df3d_production;
    for(int crop:{-1,175})for(int fault=0;fault<16;++fault) {
        CAPTURE(crop);CAPTURE(fault);
        Snapshot before;before.revision=farmRevision(before);
        int applies=0,reads=0,validations=0;
        auto expected=before.revision;
        if(fault==14)++expected;
        if(fault==15)expected=0;
        const auto result=finishFarmEdit(before,expected,crop,[&]() -> std::optional<bool> {
            ++applies;
            if(fault==1)throw 1;
            if(fault==2)return false;
            if(fault==3)return {};
            return true;
        },[&]() -> std::optional<Snapshot> {
            ++reads;
            if(fault==4)throw 1;
            if(fault==5)return {};
            auto after=before;after.seasonalCrops[1]=crop;
            if(fault==8)++after.buildingId;
            if(fault==9)after.selectedSeason=0;
            if(fault==10)after.currentSeason=2;
            if(fault==11)after.seasonalCrops[1]=999;
            if(fault==12)after.seasonalCrops[0]=-1;
            after.revision=farmRevision(after);return after;
        },[&](const Snapshot& s) {
            ++validations;
            if(fault==13)return false;
            if(validations>1 && fault==6)return false;
            if(validations>1 && fault==7)throw 1;
            return s.revision>0 && s.seasonalCrops.size()==4;
        });
        const bool preflight=fault>=13;
        const bool refused=fault==2 || fault==3 || preflight;
        CHECK(applies==(preflight?0:1));
        CHECK(reads==(preflight || fault==1 || fault==2 || fault==3?0:1));
        CHECK(result.mutated==!refused);
        CHECK(result.receipt.has_value()==(fault==0));
        CHECK(result.outcome==(fault==0?FarmEditOutcome::Completed:fault==14?FarmEditOutcome::Stale:
            refused?FarmEditOutcome::Rejected:FarmEditOutcome::Unknown));
        if(result.receipt)CHECK(result.receipt->seasonalCrops[1]==crop);
    }
}

TEST_CASE("fertilizer transactions distinguish stale refusals and post-effect uncertainty") {
    using namespace df3d_production;
    for(int seasonal:{-1,0,1})for(int fault=0;fault<12;++fault) {
        CAPTURE(seasonal);CAPTURE(fault);Snapshot before;before.revision=farmRevision(before);
        int applies=0;auto expected=before.revision+(fault==1?1:0);
        auto result=finishFarmFertilization(before,expected,seasonal,[&]{
            ++applies;if(fault==2)throw 1;return fault!=3;
        },[&]() -> std::optional<Snapshot> {
            if(fault==4)throw 1;if(fault==5)return {};
            auto after=before;
            if(seasonal<0)after.pendingFertilization=29;else after.seasonalFertilization=seasonal!=0;
            if(fault==6)++after.buildingId;
            if(fault==7)++after.currentFertilization;
            if(fault==8)++after.maxFertilization;
            if(fault==9)after.seasonalCrops[0]=-1;
            if(fault==10)after.pendingFertilization=100;
            if(fault==11)after.seasonalFertilization=!after.seasonalFertilization;
            after.revision=farmRevision(after);return after;
        },[](const Snapshot& s){return s.revision>0;});
        CHECK(applies==(fault==1?0:1));
        CHECK(result.receipt.has_value()==(fault==0));
        CHECK(result.mutated==(fault!=1 && fault!=3));
        CHECK(result.outcome==(fault==0?FarmEditOutcome::Completed:fault==1?FarmEditOutcome::Stale:
            fault==3?FarmEditOutcome::Rejected:FarmEditOutcome::Unknown));
    }
}

TEST_CASE("farm rename refuses invalid intent before effects and never retries uncertainty") {
    using namespace df3d_production;
    for(int fault=0;fault<26;++fault) {
        CAPTURE(fault);Snapshot before;before.customName="old";before.headerName="Old";
        if(fault==1)before.removing=true;
        before.revision=farmRevision(before);
        std::string requested="new farm";
        if(fault==2)requested=std::string(91,'x');
        if(fault==3)requested=std::string("a\0b",3);
        const auto expected=fault==4?0:before.revision+(fault==5?1:0);
        int applies=0,reads=0,validations=0;
        auto result=finishFarmRename(before,expected,requested,[&](const std::string& text)->std::optional<std::string> {
            if(fault==6)return {};
            if(fault==7)throw 1;
            if(fault==8)return std::string(31,'x');
            if(fault==9)return std::string("a\0b",3);
            return text;
        },[&](const std::string& raw) {
            ++applies;CHECK(raw=="new farm");
            if(fault==10)throw 1;
            return fault!=11;
        },[&]()->std::optional<Snapshot> {
            ++reads;if(fault==12)throw 1;if(fault==13)return {};
            auto after=before;after.customName=requested;after.headerName="New farm";
            if(fault==14)after.customName="wrong";
            if(fault==15)after.headerName.clear();
            if(fault==16)++after.buildingId;
            if(fault==17)++after.selectedSeason;
            if(fault==18)++after.currentSeason;
            if(fault==19)++after.pendingFertilization;
            if(fault==20)after.removing=true;
            if(fault==21)after.seasonalCrops[0]=-1;
            if(fault==22)after.choices[0].seedsAvailable=false;
            after.revision=farmRevision(after);return after;
        },[&](const Snapshot& s) {
            ++validations;
            if(fault==23)return false;
            if(validations>1 && fault==24)return false;
            if(validations>1 && fault==25)throw 1;
            return s.revision>0;
        });
        const bool preflight=(fault>=1 && fault<=9) || fault==23;
        CHECK(applies==(preflight?0:1));
        CHECK(reads==(preflight || fault==10 || fault==11?0:1));
        CHECK(result.mutated==(!preflight && fault!=11));
        CHECK(result.receipt.has_value()==(fault==0));
        CHECK(result.outcome==(fault==0?FarmEditOutcome::Completed:fault==5?FarmEditOutcome::Stale:
            preflight || fault==11?FarmEditOutcome::Rejected:FarmEditOutcome::Unknown));
    }
}

TEST_CASE("farm rename accepts clearing and lossless byte limits and skips identical writes") {
    using namespace df3d_production;
    // Injected encoding is explicit: the live adapter must verify DF2UTF(UTF2DF)
    // equality. These cases exercise transaction boundaries, not DF's converter.
    for(const std::string requested:{std::string(),std::string(30,'x'),std::string("\xc3\xa9"),std::string("old")}) {
        Snapshot before;before.customName="old";before.revision=farmRevision(before);
        int applies=0,reads=0;
        auto result=finishFarmRename(before,before.revision,requested,
            [&](const std::string& text)->std::optional<std::string> {
                return text=="\xc3\xa9"?std::string(1,char(0x82)):text;
            },[&](const std::string& bytes) {
                ++applies;CHECK(bytes==(requested=="\xc3\xa9"?std::string(1,char(0x82)):requested));return true;
            },[&]()->std::optional<Snapshot> {
                ++reads;auto after=before;after.customName=requested;
                after.headerName=requested.empty()?"Farm Plot":"Native formatted";
                after.revision=farmRevision(after);return after;
            },[](const Snapshot& s){return s.revision>0;});
        REQUIRE(result.outcome==FarmEditOutcome::Completed);REQUIRE(result.receipt);
        CHECK(result.receipt->customName==requested);
        CHECK(result.mutated==(requested!="old"));
        CHECK(applies==(requested=="old"?0:1));CHECK(reads==applies);
    }
}
