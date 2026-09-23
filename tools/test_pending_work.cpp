#include "doctest.h"
#include "../bridge/plugin/pending_work.h"

namespace {
namespace pw=df3d_pending_work;
enum class JobType {
    Dig,CarveUpwardStaircase,CarveDownwardStaircase,CarveUpDownStaircase,CarveRamp,DigChannel,
    SmoothWall,SmoothFloor,DetailWall,DetailFloor,FellTree,GatherPlants,
    RemoveConstruction,CarveTrack,CarveFortification,HaulStone,Eat
};
enum class Operation { None,Dig,Channel,StairUp,StairDown,StairUpDown,Ramp,RemoveConstruction,Chop,Gather,Smooth,Engrave,Fortify };
}

TEST_CASE("pending work classifies native jobs into designation kinds") {
    CHECK_MESSAGE(pw::operation<Operation>(JobType::Dig)==Operation::Dig,"exact mining operation");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::DigChannel)==Operation::Channel,"channel never degrades to mining");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::CarveUpwardStaircase)==Operation::StairUp,"up stairs");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::CarveDownwardStaircase)==Operation::StairDown,"down stairs");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::CarveUpDownStaircase)==Operation::StairUpDown,"up/down stairs");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::CarveRamp)==Operation::Ramp,"ramp");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::FellTree)==Operation::Chop,"chopping remains distinct from digging");
    CHECK_MESSAGE(pw::operation<Operation>(JobType::GatherPlants)==Operation::Gather,"gathering remains distinct from digging");
    for(auto type:{JobType::Dig,JobType::CarveUpwardStaircase,JobType::CarveDownwardStaircase,
                  JobType::CarveUpDownStaircase,JobType::CarveRamp,JobType::DigChannel})
        CHECK_MESSAGE(pw::classify(type)==pw::Kind::Dig,"excavation job family");
    for(auto type:{JobType::RemoveConstruction,JobType::HaulStone,JobType::Eat})
        CHECK_MESSAGE(pw::classify(type)==pw::Kind::None,"unrelated jobs are not designations");
    CHECK_MESSAGE(pw::classify(JobType::FellTree)==pw::Kind::Chop,"tree order remains after bit becomes job");
    CHECK_MESSAGE(pw::classify(JobType::GatherPlants)==pw::Kind::Gather,"plant order remains after bit becomes job");
    CHECK_MESSAGE((pw::classify(JobType::SmoothWall)==pw::Kind::Smooth && pw::classify(JobType::SmoothFloor)==pw::Kind::Smooth),"smooth jobs");
    CHECK_MESSAGE((pw::classify(JobType::DetailWall)==pw::Kind::Engrave && pw::classify(JobType::DetailFloor)==pw::Kind::Engrave),"engrave jobs");
    CHECK_MESSAGE((pw::classify(JobType::CarveFortification)==pw::Kind::Smooth && pw::classify(JobType::CarveTrack)==pw::Kind::None),"track masks are indexed separately, never displayed as smoothing");
}
TEST_CASE("pending work index invalidates blocks and matches removals") {
    pw::Index index;
    pw::Tiles jobs;
    const pw::Tile size{48,48,5},dig{15,8,2},tree{16,8,2};
    pw::add(jobs,dig,pw::Kind::Dig,size);
    pw::add(jobs,dig,pw::Kind::Dig,size);
    pw::add(jobs,tree,pw::Kind::Chop,size);
    pw::add(jobs,{-1,8,2},pw::Kind::Dig,size);
    pw::add(jobs,{48,8,2},pw::Kind::Dig,size);
    pw::add(jobs,{2,8,5},pw::Kind::Dig,size);
    pw::add(jobs,{2,8,2},pw::Kind::None,size);
    CHECK_MESSAGE(jobs.size()==2,"invalid positions and unrelated kinds cannot enter grid index");
    CHECK_MESSAGE((index.replace(jobs)==pw::Blocks{{0,0,2},{1,0,2}}),"job creation invalidates both blocks across seam");
    CHECK_MESSAGE((index.at(dig)==uint8_t(pw::Kind::Dig) && index.at(tree)==uint8_t(pw::Kind::Chop)),"both jobs remain queryable without raw designation bits");
    CHECK_MESSAGE(index.replace(jobs).empty(),"paused unchanged jobs do not force reclassification");
    jobs[dig]=uint8_t(pw::Kind::Smooth);
    CHECK_MESSAGE((index.replace(jobs)==pw::Blocks{{0,0,2}}),"changed job kind invalidates despite same tile set");
    jobs.erase(tree);
    CHECK_MESSAGE((index.replace(jobs)==pw::Blocks{{1,0,2}} && index.at(tree)==0),"completed or canceled job clears its old block");
    CHECK_MESSAGE((index.replace({})==pw::Blocks{{0,0,2}} && index.at(dig)==0),"last job removal invalidates while tile bits remain unchanged");
    CHECK_MESSAGE((index.replace({}).empty()),"empty stable state is cheap");
    CHECK_MESSAGE(pw::matchesRemoval(pw::Kind::Dig,false),"dig removal includes job-backed excavation");
    CHECK_MESSAGE((pw::matchesRemoval(pw::Kind::Smooth,true) && pw::matchesRemoval(pw::Kind::Engrave,true)),"detail removal includes both job families");
    CHECK_MESSAGE((!pw::matchesRemoval(pw::Kind::Dig,true) && !pw::matchesRemoval(pw::Kind::Smooth,false)),"remove families remain separate");
    for(auto kind:{pw::Kind::None,pw::Kind::Chop,pw::Kind::Gather})
        CHECK_MESSAGE((!pw::matchesRemoval(kind,false) && !pw::matchesRemoval(kind,true)),"generic job cancellation excludes unrelated and plant jobs");
    CHECK_MESSAGE((pw::inRect(dig,15,8,16,8,2) && pw::inRect(tree,15,8,16,8,2)),"inclusive cancellation rectangle");
    CHECK_MESSAGE((!pw::inRect({15,8,3},15,8,16,8,2) && !pw::inRect({14,8,2},15,8,16,8,2)),"cancellation never crosses selected level/rectangle");
}
