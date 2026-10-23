# Test stub for Vyatta::Config as vyatta-xconnect.pl uses it: the
# candidate and running xconnect leaves of the dataplane interface come
# from the JSON objects in STUB_NEW and STUB_ORIG; an l2tpeth interface has
# an l2tp-session unless STUB_NO_SESSION is set.
package Vyatta::Config;
use strict;
use warnings;
use JSON::PP;

sub new { my ( $class, $path ) = @_; return bless { path => $path }, $class; }

sub leaf {
    my ( $var, $path ) = @_;
    my ($leaf) = $path =~ m{^xconnect[ ](\S+)$}x or return;
    return decode_json( $ENV{$var} // '{}' )->{$leaf};
}

sub returnValue     { my ( undef, $path ) = @_; return leaf( 'STUB_NEW',  $path ); }
sub returnOrigValue { my ( undef, $path ) = @_; return leaf( 'STUB_ORIG', $path ); }

## no critic (Subroutines::ProhibitBuiltinHomonyms) reason: Vyatta::Config's method name
sub exists { return $ENV{STUB_NO_SESSION} ? 0 : 1; }
## use critic

1;
