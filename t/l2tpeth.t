#!/usr/bin/perl
# Tests for scripts/vyatta-l2tpeth.pl with stub Vyatta modules and stub ip
# and ifmgrctl commands that log their arguments.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More tests => 15;

my $tmp = tempdir( CLEANUP => 1 );
my $log = "$tmp/calls.log";
mkdir "$tmp/bin" or BAIL_OUT("mkdir: $!");

sub write_file {
    my ( $file, $content, $mode ) = @_;
    open my $fh, '>', $file or BAIL_OUT("cannot write $file: $!");
    print {$fh} $content;
    close $fh or BAIL_OUT("cannot close $file: $!");
    chmod $mode, $file if defined $mode;
    return;
}

foreach my $cmd (qw(ip ifmgrctl)) {
    write_file( "$tmp/bin/$cmd", "#!/bin/sh\necho \"$cmd \$*\" >> '$log'\nexit \${STUB_RC:-0}\n",
        oct 755 );
}

my %session = (
    'encapsulation'     => 'udp',
    'local-session-id'  => '10',
    'remote-session-id' => '20',
    'local-ip'          => '192.0.2.1',
    'remote-ip'         => '192.0.2.2',
    'local-udp-port'    => '5000',
    'remote-udp-port'   => '6000',
);
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

sub run_l2tp {
    my ( $action, $new, $orig, %env ) = @_;
    unlink $log;
    local $ENV{PATH}        = "$tmp/bin:$ENV{PATH}";
    local $ENV{STUB_NEW}    = $json->encode( $new  // {} );
    local $ENV{STUB_ORIG}   = $json->encode( $orig // {} );
    local @ENV{ keys %env } = values %env;
    my ( $rc, $text ) =
      capture( $^X, "-I$FindBin::Bin/lib", "$FindBin::Bin/../scripts/vyatta-l2tpeth.pl",
        $action, 'lttp1' );
    open my $fh, '<', $log or return ( $rc, $text, q{} );
    my $calls = do { local $/ = undef; <$fh> };
    close $fh or BAIL_OUT("close: $!");
    return ( $rc, $text, $calls );
}

my $register = "ifmgrctl register lttp1\n";
my $add =
    "ip l2tp add tunnel tunnel_id 10 peer_tunnel_id 20 encap udp local 192.0.2.1"
  . " remote 192.0.2.2 udp_sport 5000 udp_dport 6000\n"
  . "ip l2tp add session tunnel_id 10 session_id 10 peer_session_id 20 name lttp1"
  . " l2spec_type none\n";
my $del = "ip l2tp del session tunnel_id 10 session_id 10\n" . "ip l2tp del tunnel tunnel_id 10\n";

my ( $rc, $out, $calls ) = run_l2tp( 'SET', \%session );
is( $rc,    0,                'SET: exit 0' ) or diag $out;
is( $calls, $register . $add, 'SET: registered, tunnel and session added' );

( $rc, undef, $calls ) =
  run_l2tp( 'SET', { %session, 'local-cookie' => '0x1234', 'remote-cookie' => '0x5678' } );
my $cookies = "l2spec_type none cookie 0x1234 peer_cookie 0x5678\n";
is( substr( $calls, -length $cookies ), $cookies, 'SET with cookies: cookies passed' );

( $rc, undef, $calls ) =
  run_l2tp( 'SET', { %session, 'local-cookie' => '0x1234' } );
is( $calls, $register . $add, 'SET with only a local cookie: no cookies' );

my %partial = %session;
delete $partial{'remote-ip'};
( $rc, undef, $calls ) = run_l2tp( 'SET', \%partial );
is( $rc,    0,         'SET incomplete: exit 0' );
is( $calls, $register, 'SET incomplete: only registered' );

( $rc, $out, $calls ) = run_l2tp( 'SET', \%session, undef, STUB_LOCAL_IF => q{} );
isnt( $rc, 0, 'SET without the local address: fails' );
like(
    $out,
    qr{Local[ ]address[ ]192[.]0[.]2[.]1[ ]must[ ]exist}x,
    'SET without the local address: reported'
);

( $rc, $out ) = run_l2tp( 'SET', \%session, undef, STUB_LINK_DOWN => 1 );
like( $out, qr{Interface[ ]dp0s3[ ]must[ ]be[ ]up}x, 'SET with the link down: reported' );

( $rc, undef, $calls ) = run_l2tp( 'DELETE', undef, \%session );
is( $calls, $register . $del, 'DELETE: session and tunnel deleted' );

( $rc, undef, $calls ) = run_l2tp( 'ACTIVE', \%session, \%session );
is( $calls, $register, 'ACTIVE unchanged: nothing redone' );

( $rc, undef, $calls ) =
  run_l2tp( 'ACTIVE', \%session, { %session, 'remote-ip' => '192.0.2.9' } );
is( $calls, $register . $del . $add, 'ACTIVE changed: deleted and re-added' );

( $rc, undef, $calls ) =
  run_l2tp( 'ACTIVE', \%session, { %session, 'local-cookie' => '0x1', 'remote-cookie' => '0x2' } );
is( $calls, $register . $del . $add, 'ACTIVE cookies removed: re-added' );

( $rc, undef, $calls ) = run_l2tp( 'ACTIVE', \%session, \%session, STUB_STATUS => 'deleted' );
is( $calls, $register, 'ACTIVE on a deleted session: nothing done' );

($rc) = run_l2tp( 'SET', \%session, undef, STUB_RC => 1 );
is( $rc, 1, 'ifmgrctl failure: exit 1' );
