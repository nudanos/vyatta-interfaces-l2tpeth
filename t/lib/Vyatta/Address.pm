# Test stub for Vyatta::Address: STUB_LOCAL_IF is the interface holding the
# local address ("" when none), STUB_LINK_DOWN marks it down.
package Vyatta::Address;
use strict;
use warnings;

sub get_interface {
    my $if   = $ENV{STUB_LOCAL_IF} // 'dp0s3';
    my $up   = $ENV{STUB_LINK_DOWN} ? 0 : 1;
    my $tent = 0;
    return ( \$if, \$up, \$tent );
}

sub is_ipv6 { my ($addr) = @_; return $addr =~ m{:}x; }

sub ipv6_tentative_addr_dad_wait { return; }

1;
