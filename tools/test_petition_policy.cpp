#include "doctest.h"
#include "../bridge/plugin/petition_policy.h"
#include "../bridge/plugin/petition_button.h"
#include <string>
#include <utility>
#include <vector>
using namespace df3d_session;

TEST_CASE("petition receipts track native identity, responses and transitions") {
 PetitionIdentity v;v.agreement=10;v.subject=11;v.location=12;v.screen=13;v.id=v.selected=212;v.complete=v.open=v.responsible=true;v.pending=v.uiIds={212};v.flags=1;v.terms={0,104,168260,12,0,1,378,11,0,-1,37,1,0};v.requirements={2000,10000};v.parties={{20,0,{780},{},{"The Whiskered Guild"}},{21,1,{483},{},{"Government"}}};
 PetitionReceipt p;auto r=p.observe(7,v,true);CHECK((r&&p.observe(7,v,true)==r));
 auto check=[&](PetitionIdentity c){auto old=p.observe(7,v,true);CHECK(p.observe(7,c,true)!=old);CHECK(!p.consume(7,old,true));};
 auto c=v;c.parties[0].names[0]+=" changed";check(c);c=v;c.parties[0].entities.push_back(999);check(c);c=v;c.terms.back()=1;check(c);c=v;c.flags=3;check(c);c=v;c.requirements[0]++;check(c);c=v;c.screen++;check(c);c=v;c.continuing={42};check(c);c=v;c.context="different";check(c);
 c=v;c.pending={212,213};CHECK(!p.observe(7,c,true));c=v;c.responsible=false;CHECK(p.observe(7,c,true)); // Close remains receipt-bound without an official.
 c=v;c.complete=false;CHECK(!p.observe(7,c,true));c=v;c.selected=213;CHECK(!p.observe(7,c,true));CHECK(!p.observe(0,v,true));
 r=p.observe(7,v,true);CHECK(!p.consume(8,r,true));CHECK(p.consume(7,r,true));CHECK(!p.consume(7,r,true));CHECK(!p.observe(7,v,true));
 c=v;c.pending.clear();c.uiIds.clear();c.selected=-1;c.flags=0;c.continuing={212};CHECK(p.transitioned(7,c));CHECK(!p.transitioned(8,c));c.parties[1].entities[0]++;CHECK(!p.transitioned(7,c));p.finish();CHECK((p.uncertainContext(v)&&!p.observe(7,v,true)));
 CHECK(p.observe(8,v,true)); // Identical native addresses in another world are not quarantined.
 PetitionReceipt ordered;auto prior=v;prior.continuing={8,10};auto token=ordered.observe(7,prior,true);CHECK(ordered.consume(7,token,true));auto inserted=prior;inserted.pending.clear();inserted.uiIds.clear();inserted.selected=-1;inserted.flags=0;inserted.continuing={8,212,10};CHECK(ordered.transitioned(7,inserted));inserted.continuing={10,212,8};CHECK(!ordered.transitioned(7,inserted));
 PetitionReceipt back;token=back.observe(7,v,true);CHECK(back.consume(7,token,false));back.finish(true);CHECK(back.observe(7,v,true)>token); // Successful Back and review can mint a fresh response receipt.
 PetitionReceipt deny;r=deny.observe(7,v,true);CHECK(deny.consume(7,r,false));c=v;c.pending.clear();c.uiIds.clear();c.selected=-1;CHECK(deny.transitioned(7,c));c.flags=0;CHECK(!deny.transitioned(7,c));
}
TEST_CASE("petition decision buttons and launcher are located only in the verified layout") {
 const std::string question="Do you approve this request?";
 std::vector<std::string> rows(66,std::string(150,' '));rows[6].replace(45,19,"The Whiskered Guild");rows[23].replace(45,question.size(),question);rows[26].replace(47,7,"Approve");rows[26].replace(58,4,"Deny");
 CHECK(petitionDecisionButton(rows,"The Whiskered Guild",true)==std::make_pair(50,26));CHECK(petitionDecisionButton(rows,"The Whiskered Guild",false)==std::make_pair(59,26));
 auto bad=rows;bad[27].replace(47,7,"Approve");CHECK(petitionDecisionButton(bad,"The Whiskered Guild",true).first<0);bad=rows;bad[26][80]='X';CHECK(petitionDecisionButton(bad,"The Whiskered Guild",true).first<0);CHECK(petitionDecisionButton(rows,"Wrong guild",true).first<0);bad=rows;bad[7].replace(45,19,"The Whiskered Guild");CHECK(petitionDecisionButton(bad,"The Whiskered Guild",true).first<0);
 rows[7].replace(5,9,"PETITIONS");CHECK(petitionLauncher(rows)==std::make_pair(9,7));rows[8].replace(5,9,"PETITIONS");CHECK(petitionLauncher(rows).first<0);
}
