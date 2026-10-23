# Test stub for Vyatta::Config: the candidate and running l2tp-session
# leaves come from the JSON objects in STUB_NEW and STUB_ORIG (leaf name =>
# value); STUB_STATUS is the l2tp-session node status.
package Vyatta::Config;
use strict;
use warnings;
use JSON::PP;

sub new { return bless {}, shift; }

sub leaf {
    my ( $var, $path ) = @_;
    my ($leaf) = $path =~ m{^l2tp-session[ ](\S+)$}x or return;
    return decode_json( $ENV{$var} // '{}' )->{$leaf};
}

sub returnValue     { my ( undef, $path ) = @_; return leaf( 'STUB_NEW',  $path ); }
sub returnOrigValue { my ( undef, $path ) = @_; return leaf( 'STUB_ORIG', $path ); }

## no critic (Subroutines::ProhibitBuiltinHomonyms) reason: Vyatta::Config's method name
sub exists { return %{ decode_json( $ENV{STUB_NEW} // '{}' ) } ? 1 : 0; }
## use critic

sub getNodeStatus { return $ENV{STUB_STATUS} // 'changed'; }

1;
