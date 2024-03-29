#!/usr/bin/env perl
use strict;
use warnings;
use Test::More qw/no_plan/;
require 't/CommonConfig.pm';
use lib "testdata/regression-mismatch-world-north-south-unknown";
use SquidReportArchiveConfig;
use Carp;
use lib "./t";
use Generate::Squid;
use List::Util qw/sum first/;
use Data::Dumper;
use POSIX 'strftime';


# 
# Scenario: Every region code receives 2 entries.
# 
# We test that the invariant world_total - global_north - global_south - ipv6 - unknown
# is 0.
# 

our $__DATA_BASE;
our $__CODE_BASE;

# We pick two days and simulate squid/varnish log output for
# them. The days must not be older than one year, or otherwise
# SquidCountArchive.pl will complain. So we resort to the 1st,
# 2nd, ... day of the previous month. That should always work.
#
# We're mostly interested in the 2nd day of the month, and filter for
# that. The 1st day of the month is just there to simulate boundaries.
my @date = gmtime(time);
$date[4]--; # Set month to previous
if ($date[4] < 0) {
    # Month underrun. Make up by borrowing from year.
    $date[4]+=12;
    $date[5]--;
}

# First day of month
$date[3]=1;
my $day_1_ymd = strftime('%Y-%m-%d', @date);

# Second day of month. This is the day we're interested in.
$date[3]++;
my $day_2_ym = strftime('%Y-%m', @date);
my $day_2_ymd_slash = strftime('%Y/%m/%d', @date);

my $o = Generate::Squid->new({
   start_date => $day_1_ymd,
   prefix     => "sampled-1000.log-"  ,
   output_dir => "$__DATA_BASE",
});


$o->generate_line({ geocode=>"--"  });
$o->__increase_day; 

for my $country (@Generate::Squid::ALL_COUNTRY_CODES) {
  $o->generate_line({ 
      geocode=> $country,
      client_ip=>'random_ipv4',
  }) for 1..2;
};


$o->__increase_day; 
$o->generate_line({ geocode=>"--"  });
$o->dump_to_disk_and_increase_day;



my $wikistats_run_cmd = qq{
    
    cd $__DATA_BASE;
    rm -f sampled-1000.log*.gz
    ls sampled-1000.log* | xargs gzip;
    cd $__CODE_BASE;

    echo "FINISHED gzip";

    rm -rf $__DATA_BASE/csv/;
    rm -rf $__DATA_BASE/reports/;
    rm -rf $__DATA_BASE/logs/;

    echo "FINISHED cleaning";

    mkdir $__DATA_BASE/csv/;
    ln -s ../../../csv/meta $__DATA_BASE/csv/meta;

    echo "FINISHED cleaning 2";

    ########################
    # Run Count Archive
    ########################
    nice perl			                  \\
    -I ./perl                                     \\
    perl/SquidCountArchive.pl	                  \\
    -d $day_2_ymd_slash-$day_2_ymd_slash          \\
    -r $__DATA_BASE/SquidCountArchiveConfig.pm    \\
    -p 2>&1;

    echo "FINISHED counting";
    ########################
    # Make the reports
    ########################
    nice perl  perl/SquidReportArchive.pl         \\
    -r $__DATA_BASE/SquidReportArchiveConfig.pm   \\
    -m $day_2_ym                                  \\
    -p 2>&1;
};

my $wikistats_run_cmd_output = `$wikistats_run_cmd`;
#warn $wikistats_run_cmd_output;




use HTML::TreeBuilder::XPath;
use Data::Dumper;
my $p = HTML::TreeBuilder::XPath->new;
$p->parse_file("$__DATA_BASE/reports/$day_2_ym/SquidReportCountryData.htm");

my @nodes;

@nodes = map { $_->as_HTML();  }  $p->findnodes(".//*[\@id='table1']/tbody/tr[1]/td[7]");
my ($world_total)  = $nodes[0] =~ /showCount\((\d+|-),/;

@nodes = map { $_->as_HTML();  }  $p->findnodes(".//*[\@id='table1']/tbody/tr[3]/td[7]");
my ($global_north) = $nodes[0] =~ /showCount\((\d+|-),/;

@nodes = map { $_->as_HTML();  }  $p->findnodes(".//*[\@id='table1']/tbody/tr[4]/td[7]");
my ($global_south) = $nodes[0] =~ /showCount\((\d+|-),/;

@nodes = map { $_->as_HTML();  }  $p->findnodes(".//*[\@id='table1']/tbody/tr[6]/td[7]");
my ($ipv6)         = $nodes[0] =~ /showCount\((\d+|-),/;

@nodes = map { $_->as_HTML();  }  $p->findnodes(".//*[\@id='table1']/tbody/tr[7]/td[7]");
my ($unknown)      = $nodes[0] =~ /showCount\((\d+|-),/;

$world_total  = $world_total  eq '-' ? 0 : $world_total;
$global_south = $global_south eq '-' ? 0 : $global_south;
$global_north = $global_north eq '-' ? 0 : $global_north;
$ipv6         = $ipv6         eq '-' ? 0 : $ipv6;
$unknown      = $unknown      eq '-' ? 0 : $unknown;

$world_total  /= 1000;
$global_north /= 1000;
$global_south /= 1000;
$ipv6         /= 1000;
$unknown      /= 1000;

warn "
world_total  = $world_total
global_north = $global_north
global_south = $global_south
ipv6         = $ipv6
unknown      = $unknown
";

ok($world_total  > 2, "world_total  > 2");
ok($global_south > 2, "globla_south > 2");
ok($global_north > 2, "globla_north > 2");

warn "world_total - global_north - global_south - ipv6 - unknown = ".($world_total - $global_north - $global_south - $ipv6 - $unknown);

my $country_code_invariant_1 = $world_total - $global_north - $global_south - $ipv6 - $unknown;
is($country_code_invariant_1,0,"Country code invariant I is zero ( World - Global_North - Global_South - IPv6 - Unknown )");
