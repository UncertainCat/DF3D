// Persistent world-model consumer for the paused missing-part smoke lane.
// Exact references verify changed stacks and restoration without reattaching.
#include "wm/mirror_client.h"
#include <chrono>
#include <fstream>
#include <sstream>
#include <thread>

int main(int argc,char** argv) {
    if(argc!=3) return 2;
    const std::string prefix=argv[1];
    const auto id=std::stoull(argv[2]);
    std::string error, acknowledged, requested;
    auto client=wm::MirrorClient::open(error);
    if(!client) {std::ofstream(prefix+".error")<<error;return 1;}
    wm::WorldModel model;
    const auto start=std::chrono::steady_clock::now();
    while(std::chrono::steady_clock::now()-start<std::chrono::seconds(180)) {
        const double now=std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
        client->poll(model,now);
        std::ifstream input(prefix+".request");
        std::string phase,line,expected;
        std::getline(input,phase);
        if(phase=="quit") return 0;
        bool complete=false;
        while(std::getline(input,line)) {
            if(line=="END"){complete=true;break;}
            expected+=line+'\n';
        }
        input.close();
        if(complete && phase!=acknowledged) {
            // The lane edits memory outside normal DF simulation/commands.
            // An idempotent pause command requests a source publication while
            // preserving the tick; no full recovery or client reattach occurs.
            if(phase!=requested && client->sendSetPause(true)) requested=phase;
            if(const auto* a=model.unitAppearance(id)) {
                std::ostringstream actual;
                for(const auto& l:a->layers) {
                    auto pal=model.paletteName(l.palette);
                    actual<<model.tilePageName(l.page)<<' '<<l.tileX<<' '<<l.tileY<<' '
                          <<int(l.cellsX)<<' '<<int(l.cellsY)<<' '<<(pal.empty()?"-":pal)<<' '
                          <<l.paletteRow<<' '<<l.paletteKeyRow<<' '<<int(l.offsetX)<<' '<<int(l.offsetY)<<'\n';
                }
                if(actual.str()==expected) {
                    acknowledged=phase;
                    std::ofstream(prefix+".ack")<<phase;
                    std::ofstream(prefix+".log",std::ios::app)<<phase<<" layers="<<a->layers.size()<<" tick="<<client->bridgeTick()<<'\n';
                }else std::ofstream(prefix+".actual")<<actual.str();
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    std::ofstream(prefix+".error")<<"Timed out";
    return 1;
}
