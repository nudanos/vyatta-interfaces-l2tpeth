# Test stub for Vyatta::VPlaned: each store is printed to STDOUT.
package Vyatta::VPlaned;
use strict;
use warnings;

sub new { return bless {}, shift; }

sub store {
    my ( undef, $key, $cmd ) = @_;
    print "store $key: $cmd\n";
    return;
}

sub store_pb {
    my ( undef, $key, $msg, $type ) = @_;
    printf "store_pb %s: %s cmd=%s dp=%s new=%s\n", $key, $type, $msg->{cmd},
      $msg->{dp_ifname}, $msg->{new_ifname} // 'undef';
    return;
}

1;
