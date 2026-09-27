#pragma once
namespace df3d_management {
// Effects depend on committed chunks, including a Rejected partial Place.
// A zero-sized chunk never clears mutations recorded by an earlier chunk.
template<class Origin,class Hint>
void constructionEffects(int chunk,const Origin* origin,int width,int height,int depth,
                         bool& mutated,Hint hint) {
    if(chunk<=0)return;
    mutated=true;
    if(!origin)return;
    for(int z=origin->z();z<origin->z()+depth;++z)
        for(int by=origin->y()>>4;by<=(origin->y()+height-1)>>4;++by)
            for(int bx=origin->x()>>4;bx<=(origin->x()+width-1)>>4;++bx)
                hint(bx<<4,by<<4,z);
}
}
