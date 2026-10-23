#! /usr/bin/perl

#
# Copyright (c) 2019-2021 AT&T Intellectual Property. All Rights Reserved.
# Copyright (c) 2014-2016, Brocade Communications Systems, Inc.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Address;
use Vyatta::Interface;
use Vyatta::Config;

my ( $action, $ifname ) = @ARGV;

# Register the interface to be managed with ifmgrd
system( "ifmgrctl", "register", $ifname ) == 0
  or exit 1;

# Get bridge information from configuration
my $intf = Vyatta::Interface->new($ifname);

my $cfg = Vyatta::Config->new( $intf->path() );

# The l2tp-session parameters, read with $get ('returnValue' for the
# candidate configuration, 'returnOrigValue' for the running one). The
# local session id doubles as the tunnel id.
sub session_params {
    my ($get) = @_;
    my %leaf = map { $_ => $cfg->$get("l2tp-session $_") } qw(
      encapsulation local-session-id remote-session-id local-ip remote-ip
      local-cookie remote-cookie local-udp-port remote-udp-port);
    my %p = (
        encap        => $leaf{'encapsulation'},
        tunnel       => $leaf{'local-session-id'},
        peer_tunnel  => $leaf{'remote-session-id'},
        session      => $leaf{'local-session-id'},
        peer_session => $leaf{'remote-session-id'},
        local_ip     => $leaf{'local-ip'},
        peer_ip      => $leaf{'remote-ip'},
        port         => [],
        cookie       => [],
    );
    $p{port} = [ "udp_sport", $leaf{'local-udp-port'}, "udp_dport", $leaf{'remote-udp-port'} ]
      if defined $leaf{'local-udp-port'};
    $p{cookie} = [ "cookie", $leaf{'local-cookie'}, "peer_cookie", $leaf{'remote-cookie'} ]
      if defined $leaf{'local-cookie'} && defined $leaf{'remote-cookie'};
    return \%p;
}

sub delete_tun_session {
    my ($old_session) = @_;
    system( "ip", "l2tp", "del", "session", "tunnel_id", $old_session, "session_id", $old_session )
      == 0
      or exit 1;
    system( "ip", "l2tp", "del", "tunnel", "tunnel_id", $old_session ) == 0
      or exit 1;
    return;
}

sub add_new_session {
    my ($p) = @_;

    # For IPv4 & IPv6, the local address must be on an interface that is up
    my ( $if_name, $link_up, $ip_tentative ) =
      Vyatta::Address::get_interface( $p->{local_ip} );
    die "Error: Local address $p->{local_ip} must exist before adding tunnel\n"
      unless ${$if_name};
    die "Error: Interface ${$if_name} must be up before adding tunnel\n"
      unless ${$link_up};

    # For IPv6 delay adding tunnel until local address is assigned
    if ( Vyatta::Address::is_ipv6( $p->{local_ip} ) ) {
        Vyatta::Address::ipv6_tentative_addr_dad_wait( ${$if_name}, $p->{local_ip} );
    }

    system(
        "ip",        "l2tp",        "add",            "tunnel",
        "tunnel_id", $p->{tunnel},  "peer_tunnel_id", $p->{peer_tunnel},
        "encap",     $p->{encap},   "local",          $p->{local_ip},
        "remote",    $p->{peer_ip}, @{ $p->{port} }
      ) == 0
      or exit 1;

    system(
        "ip",              "l2tp",             "add",        "session",
        "tunnel_id",       $p->{tunnel},       "session_id", $p->{session},
        "peer_session_id", $p->{peer_session}, "name",       $ifname,
        "l2spec_type",     "none",             @{ $p->{cookie} }
      ) == 0
      or exit 1;
    return;
}

# The parameters as one string, to tell whether any changed.
sub fingerprint {
    my ($p) = @_;
    return join "\0", map { ref $_ ? "@{$_}" : $_ // q{} } @{$p}{
        qw(tunnel peer_tunnel session peer_session local_ip peer_ip port
          cookie encap)
    };
}

my $new         = session_params('returnValue');
my $old_session = $cfg->returnOrigValue('l2tp-session local-session-id');

if ( $action eq 'SET' ) {

    # configd:defer-actions might call this with $action SET even if the
    # CLI is not yet completed and by-passes verification of the
    # l2tp-session leaf-node. In that case, gracefully stop here.
    exit 0
      if grep { !defined $new->{$_} }
      qw(tunnel peer_tunnel encap local_ip peer_ip session peer_session);

    # If the l2tp-session (static L2TP) does not exist, we have nothing to
    # do here. This is not an error since this would only happen if dynamic
    # L2TPv3 is being configured instead (control-connection). In such
    # case, the dynamic L2TPv3 VCI component will take care of the session
    # configuration.
    exit 0 if !$cfg->exists("l2tp-session");

    add_new_session($new);
}
elsif ( $action eq 'DELETE' ) {
    delete_tun_session($old_session) if defined $old_session;
}
elsif ( $action eq 'ACTIVE' ) {

    # configd:defer-actions might call this with $action ACTIVE even if the
    # l2tp interface got just deleted. In that case, gracefully stop here.
    exit 0 if $cfg->getNodeStatus('l2tp-session') eq 'deleted';

    # Delete and recreate the tunnel only if the l2tp-session parameters
    # change. If those are unchanged, do nothing and let the commit
    # algorithm apply rest of the changed config under l2tpeth.
    if ( defined $old_session
        && fingerprint($new) ne fingerprint( session_params('returnOrigValue') ) )
    {
        delete_tun_session($old_session);
        add_new_session($new);
    }
}

exit 0;
