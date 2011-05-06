package Nagios::Plugin::LVS;

use strict;
use warnings;
use vars '$VERSION', '$AUTHORITY';

$VERSION = '0.002';
$AUTHORITY = 'SUKRIA';

use Nagios::Plugin; # needed for the constants import
use base 'Nagios::Plugin';

my $ipvsadm = '/sbin/ipvsadm';

sub new {
  my ($class, %args) = @_;

  my $self = $class->SUPER::new(
                    %args,
                    usage => "$0 --service LocalAddress:Port [--warning_servers THRESHOLD] [--critical_servers THRESHOLD]",
		    blurb => "
ipvsadm command needs special privileges to be executed. This check can work either setuid (default) or via sudo. 
Please add this line in your sudoers file for the plugin to work correctly in sudo mode:

nagios          ALL=NOPASSWD:/sbin/ipvsadm -L",
  );

  $self->add_arg(
    'spec' => 'service=s',
    'help' => '  --service LocalAddress:Port : The address and port of the service to check',
    'required' => 1,
  );

  $self->add_arg(
    'spec' => 'warning_servers=s',
    'help' => '  --warning_servers THRESHOLD for number of backend servers to consider WARNING state',
    'default' => undef,
  );

  $self->add_arg(
    'spec' => 'critical_servers=s',
    'help' => '  --critical_servers THRESHOLD for number of backend servers to consider CRITICAL state',
    'default' => undef,
  );

  $self->add_arg(
    'spec' => 'sudo',
    'help' => '  --sudo Execute command via sudo',
    'default' => 0,
  );


  $self->getopts;

  return $self;
}


sub retrieve_page {
    my ($self) = @_;
    my $page;

    if ($self->opts->sudo){
       $page = `sudo $ipvsadm`;
    } else {
       $page = `$ipvsadm`;
    }
    die "Error executing $ipvsadm: $!\n" if ($? != 0);
    return $page;
}
 
# If LVS is running fine, we should not have a table with 0 active connection
sub test_page {
    my ($self, $page) = @_;
    my ($total_active, $total_inactive, $stats) = $self->parse_page($page);

    my $vals = $stats->{ $self->opts->service };
    $self->nagios_exit( UNKNOWN, "No stats for " . $self->opts->service ) if (not defined $vals);

    my $exit = $self->check_threshold( check => $vals->{'servers'},
                            warning => $self->opts->warning_servers,
                            critical => $self->opts->critical_servers );

    $self->add_perfdata( label => 'servers', value => $vals->{'servers'}, uom => '');
    $self->add_perfdata( label => 'active_conn', value => $vals->{'active_conn'}, uom => '');
    $self->add_perfdata( label => 'inactive_conn', value => $vals->{'inactive_conn'}, uom => '');

    $self->nagios_exit( $exit, "LVS " . $self->opts->service . " has " . $vals->{'servers'} . " servers" );

    $self->nagios_exit( OK, "LVS is running ($stats)" );
}

# We should have something like this in $page
#
# IP Virtual Server version 1.2.1 (size=4096)
# Prot LocalAddress:Port Scheduler Flags
# -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
# TCP  vip.domain.com:protocol wlc persistent 50
# -> xxx.domain.com:protocol       Route   1      2          1         
# -> yyy.domain.com:protocol       Local   2      0          0         
# TCP  vip.domain.com:www wlc persistent 50
# -> xxx.domain.com:www            Route   1      99         200       
# -> yyy.domain.com:www            Local   2      191        374      
sub parse_page {
    my ($self, $page) = @_;

    my $services = {};
    my $actual_service = undef;
    my $total_conn = 0;
    my $total_active = 0;
    my $total_inactive = 0;

    foreach my $line (split /\n/, $page) {
        if ($line =~ m/^(TCP|UDP)\s+(\S+\:\S+)/){
            my ($proto, $service) = ($1, $2);
            $actual_service = $service;
            if (not defined $services->{ $actual_service }){
                $services->{ $actual_service } = { servers => 0, active_conn => 0, inactive_conn => 0 };
            } else {
                $self->nagios_exit( CRITICAL, "something wrong in ipvsadm output. repeated service!" );
            }
        }
        if ($line =~ m/^\s*\-\>\s+(\S+:\S+)\s+\w+\s+(\d+)\s+(\d+)\s+(\d+)/) {
            my ($host, $weight, $active, $inactive) = ($1, $2, $3, $4);
            $total_active += $active;
            $total_inactive += $inactive;
            $services->{ $actual_service }->{'servers'} ++;
            $services->{ $actual_service }->{'active_conn'} += $active;
            $services->{ $actual_service }->{'inactive_conn'} += $inactive;
        }
    }

    return ($total_active, $total_inactive, $services);
}

1;
