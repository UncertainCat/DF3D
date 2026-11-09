#include "doctest.h"
#include "../bridge/plugin/building_header_transaction.h"
#include "../bridge/plugin/farm_transaction.h"
#include "../bridge/plugin/building_item_transaction.h"
#include "../bridge/plugin/item_transaction.h"
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
TEST_CASE("farm removal commits only explicit revision-matched observed outcomes") {
    using namespace df3d_production;
    for(bool remove:{false,true})for(int fault=0;fault<26;++fault) {
        CAPTURE(remove);CAPTURE(fault);
        Snapshot before;before.removing=!remove;before.pendingFertilization=3;
        before.removalSuspended=!remove;before.removalHasWorker=!remove;
        before.revision=farmRevision(before);
        uint64_t expected=before.revision;
        if(fault==1)expected=0;
        if(fault==2)++expected;
        if(fault==3)before.removing=remove;
        int applies=0,reads=0,validations=0;
        auto result=finishFarmRemoval(before,expected,remove,[&] {
            ++applies;
            if(fault==6)throw 6;
            return fault!=5;
        },[&]()->std::optional<Snapshot> {
            ++reads;
            if(fault==7)throw 7;
            if(fault==8)return {};
            auto after=before;after.removing=remove;after.removalSuspended=false;
            after.removalHasWorker=false;after.pendingFertilization=0;
            switch(fault) {
            case 10:after.removing=!remove;break;
            case 11:++after.buildingId;break;
            case 12:after.selectedSeason=2;break;
            case 13:after.currentSeason=2;break;
            case 14:after.customName="unexpected";break;
            case 15:after.headerName="unexpected";break;
            case 16:after.seasonalCrops[3]=-1;break;
            case 17:after.seasonalFertilization=false;break;
            case 18:++after.currentFertilization;break;
            case 19:++after.maxFertilization;break;
            case 20:after.pendingFertilization=4;break;
            case 21:after.choices[0].rawId="changed";break;
            case 22:after.pendingFertilization=-1;break;
            case 23:after.removalSuspended=true;after.removalHasWorker=true;break;
            case 24:after.pendingFertilization=1;break;
            }
            after.revision=farmRevision(after);return after;
        },[&](const Snapshot&) {
            ++validations;
            if(fault==4)throw 4;
            if(fault==25 && validations==2)throw 25;
            return !(fault==9 && validations==2);
        });
        const bool success=fault==0 || (remove && (fault==23 || fault==24));
        const bool rejected=fault==1 || fault==3 || fault==4 || fault==5;
        CHECK(result.outcome==(success?FarmEditOutcome::Completed:fault==2?FarmEditOutcome::Stale:
            rejected?FarmEditOutcome::Rejected:FarmEditOutcome::Unknown));
        CHECK(applies==(fault>=5 || fault==0?1:0));
        CHECK(reads==(applies && fault!=5 && fault!=6?1:0));
        CHECK(result.mutated==(!rejected && fault!=2));
        CHECK(result.receipt.has_value()==success);
        if(result.receipt)CHECK(result.receipt->removing==remove);
    }
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

TEST_CASE("building contents revision detects changed membership and action context") {
    using namespace df3d_production;
    BuildingContentsSnapshot base;base.buildingId=968;base.completed=true;
    BuildingContentsRow row;row.itemType=53;row.id=47492;row.role=0;row.caption="seed";row.canDump=true;
    row.jobs.push_back({123,1,0});base.rows={row};base.revision=buildingContentsRevision(base);
    CHECK(validBuildingContents(base));
    for(int change=0;change<20;++change) {
        auto next=base;
        switch(change) {
        case 0:++next.buildingId;break;case 1:next.completed=false;break;
        case 2:next.removing=true;break;case 3:next.rows.clear();break;
        case 4:++next.rows[0].id;break;case 5:++next.rows[0].role;break;
        case 6:next.rows[0].caption="other";break;case 7:++next.rows[0].flags;break;
        case 8:++next.rows[0].countdown;break;case 9:--next.rows[0].delay;break;
        case 10:next.rows[0].canDump=false;break;case 11:next.rows[0].canMelt=true;break;
        case 12:++next.rows[0].jobs[0].id;break;case 13:++next.rows[0].jobs[0].type;break;
        case 14:++next.rows[0].jobs[0].flags;break;case 15:next.rows[0].jobs.clear();break;
        case 16:next.rows[0].hidden=true;break;
        case 17:next.rows[0].itemType=54;break;
        case 18:next.rows[0].materialToken="PLANT:POD_SWEET:SEED";break;
        case 19:next.rows[0].subtypeRaw="FIXTURE";break;
        }
        CAPTURE(change);CHECK(buildingContentsRevision(next)!=base.revision);CHECK_FALSE(validBuildingContents(next));
    }
    auto duplicate=base;duplicate.rows.push_back(row);duplicate.revision=buildingContentsRevision(duplicate);
    CHECK_FALSE(validBuildingContents(duplicate));
    auto ordered=base;row.id=47486;ordered.rows.push_back(row);
    const auto orderedRevision=buildingContentsRevision(ordered);
    std::swap(ordered.rows[0],ordered.rows[1]);
    CHECK(buildingContentsRevision(ordered)!=orderedRevision);
}
TEST_CASE("contained item edits distinguish refusal completion and uncertain native effects") {
    using namespace df3d_production;
    for(int fault=0;fault<17;++fault) {
        CAPTURE(fault);
        BuildingContentsSnapshot before;before.buildingId=968;before.completed=true;
        BuildingContentsRow row;row.itemType=53;row.id=47492;row.role=0;row.canDump=true;before.rows={row};
        if(fault==2)before.removing=true;
        if(fault==3)before.completed=false;
        if(fault==4)before.rows[0].canDump=false;
        if(fault==5)before.rows[0].dump=true;
        before.revision=buildingContentsRevision(before);
        int applies=0,reads=0;
        auto action=fault==16?static_cast<BuildingItemAction>(99):BuildingItemAction::Dump;
        const auto result=finishBuildingItemEdit(before,fault==1?1:before.revision,fault==6?0:47492,action,true,[&] {
            ++applies;if(fault==8)throw 1;return fault!=7;
        },[&]()->std::optional<BuildingContentsSnapshot> {
            ++reads;if(fault==9)throw 1;if(fault==10)return {};
            auto after=before;after.rows[0].dump=true;
            // Native may retire jobs/clear other flags; these are accepted facts.
            after.rows[0].flags=123;after.rows[0].jobs.clear();
            if(fault==11)after.rows.clear();
            if(fault==12)++after.buildingId;
            if(fault==13)after.rows[0].dump=false;
            if(fault==14)after.removing=true;
            after.revision=buildingContentsRevision(after);
            if(fault==15)++after.revision;
            return after;
        });
        if(fault==0||fault==5) {
            CHECK(result.outcome==FarmEditOutcome::Completed);REQUIRE(result.receipt);
            CHECK(result.receipt->rows[0].dump);CHECK(applies==(fault==0?1:0));CHECK(reads==(fault==0?1:0));
        } else if(fault==1) {CHECK(result.outcome==FarmEditOutcome::Stale);CHECK(applies==0);}
        else if(fault<=7||fault==16) {CHECK(result.outcome==FarmEditOutcome::Rejected);CHECK_FALSE(result.mutated);}
        else {CHECK(result.outcome==FarmEditOutcome::Unknown);CHECK(result.mutated);CHECK_FALSE(result.receipt);CHECK(applies==1);}
        CHECK(applies<=1);CHECK(reads<=1);
    }
}

TEST_CASE("contents paging has complete boundaries and measures encoded captions") {
    using namespace df3d_production;
    BuildingContentsSnapshot snapshot;snapshot.buildingId=968;snapshot.completed=true;
    for(int i=0;i<70;++i){BuildingContentsRow row;row.itemType=53;row.id=1000-i;row.role=0;row.caption="seed";snapshot.rows.push_back(row);}
    snapshot.revision=buildingContentsRevision(snapshot);
    const auto unchanged=[](const std::string& value){return value;};
    auto first=pageBuildingContents(snapshot,0,0,unchanged);REQUIRE(first);
    CHECK(first->rows.size()==64);CHECK(first->nextCursor==64);CHECK(first->total==70);
    auto last=pageBuildingContents(snapshot,64,snapshot.revision,unchanged);REQUIRE(last);
    CHECK(last->rows.size()==6);CHECK(last->rows[0].id==936);CHECK(last->nextCursor==0);
    CHECK_FALSE(pageBuildingContents(snapshot,64,0,unchanged));
    CHECK_FALSE(pageBuildingContents(snapshot,64,snapshot.revision+1,unchanged));
    CHECK_FALSE(pageBuildingContents(snapshot,70,snapshot.revision,unchanged));
    CHECK_FALSE(pageBuildingContents(snapshot,UINT32_MAX,snapshot.revision,unchanged));
    auto budget=pageBuildingContents(snapshot,0,0,[](const std::string&){return std::string(65536,'x');});
    REQUIRE(budget);CHECK(budget->rows.size()==2);CHECK(budget->nextCursor==2);CHECK(budget->rows[0].caption.size()==65536);
    CHECK_FALSE(pageBuildingContents(snapshot,0,0,[](const std::string&){return std::string(131073,'x');}));
    snapshot.rows.clear();snapshot.revision=buildingContentsRevision(snapshot);
    auto empty=pageBuildingContents(snapshot,0,0,unchanged);REQUIRE(empty);
    CHECK(empty->rows.empty());CHECK(empty->nextCursor==0);CHECK(empty->total==0);
}

TEST_CASE("independent item edits preserve identity across location changes and uncertainty") {
    using namespace df3d_production;
    for(int fault=0;fault<10;++fault) {
        ItemObservation before;before.item.id=45;before.item.itemType=0;before.item.canDump=true;
        before.buildingHolder=ItemLocationLink{227,4,"farm"};before.revision=itemObservationRevision(before);
        int applies=0,reads=0;
        const auto result=finishItemEdit(before,fault==1?before.revision+1:before.revision,
            fault==2?BuildingItemAction::Melt:BuildingItemAction::Dump,true,[&]{++applies;if(fault==3)throw 1;return fault!=4;},
            [&]()->std::optional<ItemObservation>{
                ++reads;if(fault==5)return std::nullopt;if(fault==6)throw 1;
                auto after=before;after.item.dump=fault!=7;
                after.buildingHolder.reset();after.stockpile=ItemLocationLink{333,29,"stockpile"};after.stockpileCategories=1;
                if(fault==8)++after.item.id;
                after.revision=itemObservationRevision(after);if(fault==9)++after.revision;
                return after;
            });
        if(fault==0) {
            CHECK(result.outcome==FarmEditOutcome::Completed);REQUIRE(result.receipt);
            CHECK_FALSE(result.receipt->buildingHolder);REQUIRE(result.receipt->stockpile);
            CHECK(result.receipt->stockpile->id==333);CHECK(result.receipt->revision!=before.revision);
        } else if(fault==1){CHECK(result.outcome==FarmEditOutcome::Stale);CHECK_FALSE(result.mutated);}
        else if(fault==2||fault==4){CHECK(result.outcome==FarmEditOutcome::Rejected);CHECK_FALSE(result.mutated);}
        else {CHECK(result.outcome==FarmEditOutcome::Unknown);CHECK(result.mutated);CHECK_FALSE(result.receipt);}
        CHECK(applies<=1);CHECK(reads<=1);
    }
    ItemObservation item;item.item.id=45;item.item.itemType=0;item.item.canDump=true;
    item.item.dump=true;item.revision=itemObservationRevision(item);
    const auto repeated=finishItemEdit(item,item.revision,BuildingItemAction::Dump,true,
        []{FAIL("repeated desired value entered native mutation");return true;},
        []()->std::optional<ItemObservation>{FAIL("repeated desired value re-read");return std::nullopt;});
    CHECK(repeated.outcome==FarmEditOutcome::Completed);CHECK_FALSE(repeated.mutated);
    const auto revision=item.revision;
    item.stockpile=ItemLocationLink{333,29,"pile"};item.stockpileCategories=1;CHECK(itemObservationRevision(item)!=revision);
    item.revision=itemObservationRevision(item);const auto linked=item.revision;
    item.stockpileCategories=2;CHECK(itemObservationRevision(item)!=linked);item.stockpileCategories=1;
    item.stockpile->name="renamed";CHECK(itemObservationRevision(item)!=linked);
    item.revision=itemObservationRevision(item);CHECK(validItemObservation(item));
    item.stockpile->id=-1;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
}

TEST_CASE("item carrier changes invalidate authority and malformed links fail closed") {
    using namespace df3d_production;
    ItemObservation item;item.item.id=45;item.item.itemType=53;
    item.carrier=ItemCarrier{1,5834,30,"native chest"};item.carrier->appearance=ItemInspectionAppearance{"WOOD","","",1,0};item.revision=itemObservationRevision(item);
    REQUIRE(validItemObservation(item));const auto before=item.revision;
    item.carrier->appearance->colorToken="RED";CHECK(itemObservationRevision(item)!=before);item.carrier->appearance->colorToken="";
    item.carrier->appearance->stack=0;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));item.carrier->appearance->stack=1;item.revision=before;
    item.carrier=ItemCarrier{2,988,-1,"native citizen"};item.revision=itemObservationRevision(item);
    CHECK(item.revision!=before);CHECK(validItemObservation(item));
    auto result=finishItemEdit(item,before,BuildingItemAction::Hidden,true,
        []{FAIL("old carrier revision entered mutation");return true;},[&]{return std::optional<ItemObservation>(item);});
    CHECK(result.outcome==FarmEditOutcome::Stale);CHECK_FALSE(result.mutated);
    const auto unit=item.revision;item.carrier->name="renamed citizen";CHECK(itemObservationRevision(item)!=unit);
    item.carrier->itemType=0;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
    item.carrier->itemType=-1;item.buildingHolder=ItemLocationLink{1,4,"farm"};item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
}

TEST_CASE("independent item appearance participates in authority") {
    using namespace df3d_production;
    ItemObservation item;item.item.id=45;item.item.itemType=30;item.item.materialToken="WOOD";
    item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
    item.appearance=ItemInspectionAppearance{"WOOD","","RED",1,0};item.revision=itemObservationRevision(item);REQUIRE(validItemObservation(item));
    const auto before=item.revision;item.appearance->colorToken="BLUE";CHECK(itemObservationRevision(item)!=before);
    item.appearance->materialToken="STONE";item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
    item.appearance->materialToken="WOOD";item.appearance->stack=0;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
}

TEST_CASE("contents appearance changes revision and rejects missing instrument facts") {
    using namespace df3d_production;
    BuildingContentsSnapshot value;value.buildingId=278;value.completed=true;
    BuildingContentsRow row;row.id=7504;row.role=0;row.itemType=13;row.materialToken="WOOD";row.subtypeRaw="INSTRUMENT";
    value.rows.push_back(row);value.revision=buildingContentsRevision(value);CHECK_FALSE(validBuildingContents(value));
    value.rows[0].appearance=ItemInspectionAppearance{"WOOD","INSTRUMENT","",1,0,3,0};value.revision=buildingContentsRevision(value);REQUIRE(validBuildingContents(value));
    auto old=value.revision;value.rows[0].appearance->instrumentPlaced=1;value.revision=buildingContentsRevision(value);CHECK(value.revision!=old);CHECK(validBuildingContents(value));
    value.rows[0].appearance->instrumentFamily=-1;value.revision=buildingContentsRevision(value);CHECK_FALSE(validBuildingContents(value));
}

TEST_CASE("building header actions reject stale authority and uncertain effects") {
    using namespace df3d_production;
    for(auto operation:{BuildingHeaderOperation::Rename,BuildingHeaderOperation::Remove,BuildingHeaderOperation::CancelRemoval}) {
        for(int fault=0;fault<14;++fault) {
            CAPTURE(int(operation));CAPTURE(fault);
            BuildingHeaderObservation before;before.id=278;before.type=10;before.stage=before.maxStage=1;
            before.nativeName=before.headerName="Chest";
            before.removing=operation==BuildingHeaderOperation::CancelRemoval;
            if(before.removing)before.jobs.push_back({123,88,0});
            before.revision=buildingHeaderRevision(before);
            const std::string name=operation==BuildingHeaderOperation::Rename?"named":"";
            uint64_t expected=before.revision;if(fault==1)++expected;if(fault==2)expected=0;
            int applies=0,reads=0;
            auto result=finishBuildingHeaderEdit(before,expected,operation,name,[&] {
                ++applies;if(fault==3)throw 3;return fault!=4;
            },[&]()->std::optional<BuildingHeaderObservation> {
                ++reads;if(fault==5)throw 5;if(fault==6)return {};
                auto after=before;
                if(operation==BuildingHeaderOperation::Rename)after.customName=after.nativeName=after.headerName=name;
                else {
                    after.removing=operation==BuildingHeaderOperation::Remove;
                    after.jobs.clear();if(after.removing)after.jobs.push_back({124,88,0});
                }
                if(fault==7)++after.id;
                if(fault==8)++after.type;
                if(fault==9)after.stage=0;
                if(fault==10)after.headerName="";
                if(fault==11) {
                    if(operation==BuildingHeaderOperation::Rename)after.jobs.push_back({124,88,0});
                    else after.customName="unexpected";
                }
                if(fault==12) {
                    if(operation==BuildingHeaderOperation::Rename)after.customName="wrong";
                    else after.removing=!after.removing;
                }
                after.revision=buildingHeaderRevision(after);if(fault==13)++after.revision;
                return after;
            });
            const auto outcome=fault==0?BuildingHeaderOutcome::Completed:fault==1?BuildingHeaderOutcome::Stale:
                (fault==2||fault==4)?BuildingHeaderOutcome::Rejected:BuildingHeaderOutcome::Unknown;
            CHECK(result.outcome==outcome);CHECK(bool(result.receipt)==(fault==0));
            CHECK(applies==((fault==1||fault==2)?0:1));
            CHECK(reads==((fault==1||fault==2||fault==3||fault==4)?0:1));
            CHECK(result.mutated==(fault!=1 && fault!=2 && fault!=4));
        }
    }
}
TEST_CASE("building header rename bounds and repeated name are effect free") {
    using namespace df3d_production;
    BuildingHeaderObservation before;before.id=278;before.type=10;before.stage=before.maxStage=1;
    before.customName=before.nativeName=before.headerName="Chest";before.revision=buildingHeaderRevision(before);
    int calls=0;auto apply=[&]{++calls;return true;};auto observe=[&]{++calls;return std::optional<BuildingHeaderObservation>{before};};
    auto repeated=finishBuildingHeaderEdit(before,before.revision,BuildingHeaderOperation::Rename,"Chest",apply,observe);
    CHECK(repeated.outcome==BuildingHeaderOutcome::Completed);CHECK_FALSE(repeated.mutated);CHECK(calls==0);
    for(const auto& name:{std::string(31,'X'),std::string("bad\0name",8)}) {
        auto result=finishBuildingHeaderEdit(before,before.revision,BuildingHeaderOperation::Rename,name,apply,observe);
        CHECK(result.outcome==BuildingHeaderOutcome::Rejected);CHECK_FALSE(result.receipt);CHECK(calls==0);
    }
    before.jobs.push_back({1,88,0});auto revision=buildingHeaderRevision(before);
    before.jobs[0].id=2;CHECK(buildingHeaderRevision(before)!=revision);revision=buildingHeaderRevision(before);
    before.jobs[0].flags=2;CHECK(buildingHeaderRevision(before)!=revision);
}

TEST_CASE("pending chest contents edits require opt-in and stable removal state") {
    using namespace df3d_production;
    for(bool allow:{false,true}) for(bool stable:{false,true}) for(bool stale:{false,true}) {
        BuildingContentsSnapshot before;before.buildingId=278;before.completed=true;before.removing=true;
        BuildingContentsRow row;row.itemType=30;row.id=5834;row.role=2;row.canDump=true;
        row.materialToken="WOOD:KUMQUAT";row.appearance=ItemInspectionAppearance{};row.appearance->materialToken=row.materialToken;before.rows={row};
        before.revision=buildingContentsRevision(before);int calls=0;
        auto result=finishBuildingItemEdit(before,before.revision+(stale?1:0),5834,BuildingItemAction::Dump,true,
            [&]{++calls;return true;},[&]()->std::optional<BuildingContentsSnapshot>{
                auto after=before;after.rows[0].dump=true;after.removing=stable;
                after.revision=buildingContentsRevision(after);return after;
            },allow);
        CHECK(calls==(allow&&!stale?1:0));
        CHECK(result.outcome==(!allow?FarmEditOutcome::Rejected:stale?FarmEditOutcome::Stale:stable?FarmEditOutcome::Completed:FarmEditOutcome::Unknown));
        CHECK(bool(result.receipt)==(allow&&!stale&&stable));
    }
}

TEST_CASE("removing chest Melt respects native eligibility before entry") {
    using namespace df3d_production;
    for(bool eligible:{false,true}) {
        BuildingContentsSnapshot before;before.buildingId=278;before.completed=true;before.removing=true;
        BuildingContentsRow row;row.itemType=24;row.id=123;row.role=0;row.canMelt=eligible;before.rows={row};
        before.revision=buildingContentsRevision(before);int calls=0;
        auto result=finishBuildingItemEdit(before,before.revision,123,BuildingItemAction::Melt,true,
            [&]{++calls;return true;},[&]()->std::optional<BuildingContentsSnapshot>{
                auto after=before;after.rows[0].melt=true;after.revision=buildingContentsRevision(after);return after;
            },true);
        CHECK(calls==(eligible?1:0));CHECK(result.outcome==(eligible?FarmEditOutcome::Completed:FarmEditOutcome::Rejected));
    }
}

TEST_CASE("item owner changes invalidate edits independently of carrier") {
    using namespace df3d_production;
    ItemObservation item;item.item.id=45;item.item.itemType=53;
    item.carrier=ItemCarrier{2,1017,-1,"carrier"};item.revision=itemObservationRevision(item);
    const auto unowned=item.revision;item.owner=ItemOwner{988,"owner"};item.revision=itemObservationRevision(item);
    REQUIRE(validItemObservation(item));CHECK(item.revision!=unowned);
    const auto owned=item.revision;item.owner->id=989;item.revision=itemObservationRevision(item);
    const auto stale=finishItemEdit(item,owned,BuildingItemAction::Hidden,true,
      []{FAIL("owner change entered mutation");return true;},[&]{return std::optional<ItemObservation>(item);});
    CHECK(stale.outcome==FarmEditOutcome::Stale);CHECK_FALSE(stale.mutated);
    const auto renamed=item.revision;item.owner->name="new name";CHECK(itemObservationRevision(item)!=renamed);
    item.owner->id=-1;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
    item.owner=ItemOwner{988,std::string(513,'x')};item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
}

TEST_CASE("item contents changes invalidate parent authority") {
    using namespace df3d_production;
    ItemObservation parent;parent.item.id=1;parent.item.itemType=0;
    const auto unknown=itemObservationRevision(parent);parent.contents.emplace();
    CHECK(itemObservationRevision(parent)!=unknown);
    ItemSheetContent item;item.kind=1;item.id=2;item.caption="bar";item.item.emplace();
    item.item->id=2;item.item->itemType=0;item.item->caption="bar";item.item->materialToken="INORGANIC:IRON";
    item.appearance.emplace();item.appearance->materialToken="INORGANIC:IRON";
    ItemSheetContent unit;unit.kind=2;unit.id=3;unit.caption="creature";
    *parent.contents={item,unit};parent.revision=itemObservationRevision(parent);REQUIRE(validItemObservation(parent));
    const auto original=parent.revision;
    std::swap((*parent.contents)[0],(*parent.contents)[1]);CHECK(itemObservationRevision(parent)!=original);
    std::swap((*parent.contents)[0],(*parent.contents)[1]);
    (*parent.contents)[0].item->hidden=true;(*parent.contents)[0].item->flags|=0x1000000;
    parent.revision=itemObservationRevision(parent);CHECK(parent.revision!=original);
    auto rejected=finishItemEdit(parent,original,BuildingItemAction::Hidden,true,[]{FAIL("stale contents entered mutation");return true;},[&]{return std::optional<ItemObservation>(parent);});
    CHECK(rejected.outcome==FarmEditOutcome::Stale);CHECK_FALSE(rejected.mutated);
    (*parent.contents)[1].appearance.emplace();parent.revision=itemObservationRevision(parent);CHECK_FALSE(validItemObservation(parent));
}

TEST_CASE("contained item edits retain parent authority and verify the child receipt") {
    using namespace df3d_production;
    for(int fault=0;fault<8;++fault) {
        ItemObservation before;before.item.id=1;before.item.itemType=0;before.contents.emplace();
        ItemSheetContent child;child.kind=1;child.id=2;child.caption="bar";child.item.emplace();
        child.item->id=2;child.item->itemType=0;child.item->caption="bar";child.item->materialToken="INORGANIC:IRON";
        child.appearance.emplace();child.appearance->materialToken="INORGANIC:IRON";
        before.contents->push_back(child);before.revision=itemObservationRevision(before);REQUIRE(validItemObservation(before));
        int applies=0,reads=0;
        auto result=finishItemEdit(before,before.revision+(fault==1),BuildingItemAction::Hidden,true,[&]{++applies;return fault!=3;},[&]()->std::optional<ItemObservation>{
            ++reads;if(fault==4)return std::nullopt;auto after=before;
            if(fault==5)after.contents->clear();
            else if(fault!=6){after.contents->front().item->hidden=true;after.contents->front().item->flags|=0x1000000;}
            if(fault==7)after.item.id=9;
            after.revision=itemObservationRevision(after);return after;
        },fault==2?99:2);
        if(fault==0){REQUIRE(result.receipt);CHECK(result.outcome==FarmEditOutcome::Completed);CHECK_FALSE(result.receipt->item.hidden);CHECK(result.receipt->contents->front().item->hidden);}
        else if(fault==1)CHECK(result.outcome==FarmEditOutcome::Stale);
        else if(fault==2||fault==3)CHECK(result.outcome==FarmEditOutcome::Rejected);
        else {CHECK(result.outcome==FarmEditOutcome::Unknown);CHECK_FALSE(result.receipt);}
        CHECK(applies==(fault==1||fault==2?0:1));CHECK(reads==(fault==1||fault==2||fault==3?0:1));
    }
}

TEST_CASE("cage occupant facts participate in item authority") {
 using namespace df3d_production;
 ItemObservation item;item.item.id=28448;item.item.itemType=16;item.item.materialToken="INORGANIC:COPPER";
 item.appearance.emplace();auto& a=*item.appearance;a.materialToken="INORGANIC:COPPER";
 item.revision=itemObservationRevision(item);REQUIRE(validItemObservation(item));const auto unknown=item.revision;
 a.cageMaterialFamily=0;a.cageOccupantEntity=0;a.cageSolidColor="COPPER";
 item.revision=itemObservationRevision(item);REQUIRE(validItemObservation(item));CHECK(item.revision!=unknown);const auto empty=item.revision;
 a.cageOccupantEntity=1;a.cageOccupantId=6960;item.revision=itemObservationRevision(item);REQUIRE(validItemObservation(item));CHECK(item.revision!=empty);
 const auto occupied=item.revision;a.cageOccupantId=6961;item.revision=itemObservationRevision(item);CHECK(item.revision!=occupied);
 a.cageOccupantId=-1;item.revision=itemObservationRevision(item);CHECK_FALSE(validItemObservation(item));
}
