#!/usr/bin/perl
# Tests for scripts/vyatta-xconnect.pl with stub Vyatta modules; the
# dataplane stores are printed by the stub VPlaned.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More tests => 9;

my $json = JSON::PP->new->canonical;

# Runs @cmd and returns its exit status and combined output.
sub capture {
    my @cmd = @_;
    my $pid = open my $out, '-|';
    defined $pid or BAIL_OUT("fork: $!");
    if ( !$pid ) { open STDERR, '>&', \*STDOUT or exit 126; exec @cmd or exit 127; }
    my $text = do { local $/ = undef; <$out> }
      // q{};
    close $out;
    return ( $? >> 8, $text );
}

sub xconnect {
    my ( $action, $new, $orig, %env ) = @_;
    local $ENV{STUB_NEW}    = $json->encode( $new  // {} );
    local $ENV{STUB_ORIG}   = $json->encode( $orig // {} );
    local @ENV{ keys %env } = values %env;
    return capture(
        $^X,
        "-I$FindBin::Bin/xconnect-lib",
        "$FindBin::Bin/../scripts/vyatta-xconnect.pl",
        $action, 'dp0s3'
    );
}

my $key = 'interfaces dataplane dp0s3 xconnect';

my ( $rc, $out ) = xconnect( 'SET', { l2tpeth => 'lttp1' } );
is( $rc, 0, 'SET l2tpeth: exit 0' ) or diag $out;
is(
    $out,
    "store $key: l2tpeth -c add dp0s3 lttp1 255\n",
    'SET l2tpeth: added with the default ttl'
);

( $rc, $out ) = xconnect( 'SET', { l2tpeth => 'lttp1', ttl => '64' } );
is( $out, "store $key: l2tpeth -c add dp0s3 lttp1 64\n", 'SET l2tpeth: ttl' );

( $rc, $out ) = xconnect( 'SET', { l2tpeth => 'lttp1' }, undef, STUB_NO_SESSION => 1 );
is( $out, q{}, 'SET dynamic l2tpeth: left to the VCI component' );

( $rc, $out ) = xconnect( 'SET', { vhost => 'vh0' } );
is( $out, "store_pb $key: vyatta:xconnect cmd=ADD dp=dp0s3 new=vh0\n", 'SET vhost: added' );

( $rc, $out ) = xconnect( 'DELETE', undef, { dataplane => 'dp0s4' } );
is(
    $out,
    "store_pb $key: vyatta:xconnect cmd=REMOVE dp=dp0s3 new=dp0s4\n",
    'DELETE: the old peer removed'
);

( $rc, $out ) = xconnect( 'ACTIVE', { vhost => 'vh1' }, { vhost => 'vh0' } );
is( $out, "store_pb $key: vyatta:xconnect cmd=UPDATE dp=dp0s3 new=vh1\n", 'peer changed: updated' );

( $rc, $out ) = xconnect( 'ACTIVE', {}, { vhost => 'vh0' } );
is( $out, "store_pb $key: vyatta:xconnect cmd=REMOVE dp=dp0s3 new=vh0\n", 'peer removed: removed' );

( $rc, $out ) = xconnect( 'ACTIVE', {}, {} );
is( $out, q{}, 'no peer before or after: nothing stored' );
