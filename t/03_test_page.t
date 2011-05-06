use Test::More tests => 7;
use strict;
use warnings;

use Nagios::Plugin::LVS;
@ARGV = ('--service', 'stub');

my $np = Nagios::Plugin::LVS->new( shortname => "my plugin");
my $page = '
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  vip.domain.com:https wlc persistent 50
  -> xxx.domain.com:https         Route   1      2          1         
  -> yyy.domain.com:https       Local   2      0          0         
TCP  vip.domain.com:www wlc persistent 50
  -> xxx.domain.com:www           Route   1      99         200       
  -> yyy.domain.com:www         Local   2      191        374   
';
my ($nb_active, $nb_inactive, $stats) = $np->parse_page($page);

is $nb_active, 292, "nb active is OK";
is $nb_inactive, 575, "nb inactive is OK";

$page = '
IP Virtual Server version 1.2.1 (size=1048576)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  loadb-images:www lc
  -> front-5:www                  Route   1      0          3
  -> front-4:www                  Route   1      1          0
  -> front-2:www                  Route   1      0          2
  -> front-3:www                  Route   1      0          2
TCP  loadb-static:www lc
  -> front-1:www                  Route   1      0          1
TCP  loadb-none:www lc
TCP  loadb-text:www lc
  -> front-5:www                  Route   1      4          16
  -> front-3:www                  Route   1      4          15
  -> front-4:www                  Route   1      4          20
  -> front-2:www                  Route   1      5          9
TCP  loadb-none2:www lc
';

($nb_active, $nb_inactive, $stats) = $np->parse_page($page);

is $nb_active, 18, "nb active is OK";
is $nb_inactive, 68, "nb inactive is OK";

is $stats->{'loadb-images:www'}->{'servers'}, 4, "loadb-images:www servers is OK";

is $stats->{'loadb-none:www'}->{'servers'}, 0, "loadb-none:www servers is OK";
is $stats->{'loadb-none2:www'}->{'servers'}, 0, "loadb-none2:www servers is OK";

