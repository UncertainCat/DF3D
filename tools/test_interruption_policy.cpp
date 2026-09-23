#include "doctest.h"
#include "../bridge/plugin/interruption_policy.h"
#include "../bridge/plugin/announcement_button.h"
#include <string>
#include <utility>
#include <vector>
using namespace df3d_session;

TEST_CASE("interruption receipts follow popup identity transitions") {
 InterruptionReceipt p;PopupIdentity both;both.queue={101,102};both.text="Identical message";
 auto first=p.observe(7,both,true);CHECK((first&&p.consume(7,first)&&!p.consume(7,first)));
 PopupIdentity second=both;second.queue={102};CHECK(p.transitioned(7,second));p.finish();
 auto next=p.observe(7,second,true);CHECK((next&&next!=first&&!p.consume(7,first)));
 auto changed=second;changed.text="Replaced meaning";auto replacement=p.observe(7,changed,true);CHECK((replacement!=next&&!p.consume(7,next)));
 CHECK((!p.observe(7,changed,false)&&!p.consume(7,replacement))); // mandatory panel/save gate
 auto current=p.observe(7,changed,true);CHECK(p.consume(7,current));
 PopupIdentity empty;CHECK(!p.transitioned(8,empty));p.observe(8,empty,false);CHECK(!p.transitioned(8,empty));p.finish();
 current=p.observe(8,second,true);CHECK(p.consume(8,current));
 auto incomplete=empty;incomplete.complete=false;CHECK(!p.transitioned(8,incomplete));CHECK(p.transitioned(8,empty));p.finish();
 CHECK(!p.observe(8,empty,true));CHECK(!p.observe(0,second,true));
 auto duplicate=second;duplicate.queue={103};CHECK(p.observe(9,duplicate,true));
}
TEST_CASE("passive announcement button is located only in the verified layout") {
 std::vector<std::string> rows(40,std::string(80,' '));
 const std::string anchor="Native popup words.";
 rows[17].replace(24,anchor.size(),anchor);rows[21].replace(38,4,"More");
 CHECK(passiveAnnouncementButton(rows,"Native popup words.",2,2)==std::make_pair(40,21));
 rows[22].replace(38,4,"More");CHECK(passiveAnnouncementButton(rows,"Native popup words.",2,2).first<0);
 rows[22]=std::string(80,' ');rows[21].replace(38,9,"More text");CHECK(passiveAnnouncementButton(rows,"Native popup words.",2,2).first<0);
 rows[21]=std::string(80,' ');rows[30].replace(38,4,"More");CHECK(passiveAnnouncementButton(rows,anchor,2,2).first<0);
 rows[30]=std::string(80,' ');rows[21].replace(38,4,"More");rows[18].replace(24,anchor.size(),anchor);CHECK(passiveAnnouncementButton(rows,anchor,2,2).first<0);
 CHECK(passiveAnnouncementButton(std::vector<std::string>(256,std::string(512,' ')),"Native",2,2).first<0);
 rows[18]=std::string(80,' ');
 CHECK(passiveAnnouncementButton(rows,anchor,2,1).first<0); // More cannot close last popup
 rows[21].replace(38,4,"Okay");
 CHECK(passiveAnnouncementButton(rows,anchor,2,1)==std::make_pair(40,21));
 CHECK(passiveAnnouncementButton(rows,anchor,2,2).first<0); // Okay cannot advance a queue
 CHECK(passiveAnnouncementButton(rows,anchor,2,0).first<0);
 rows[22].replace(38,4,"Okay");CHECK(passiveAnnouncementButton(rows,anchor,2,1).first<0);
}
