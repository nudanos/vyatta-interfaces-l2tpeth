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
use Vyatta::Interface;
use Vyatta::Config;
use Vyatta::VPlaned;

use vyatta::proto::XConnectConfig;

die "$#ARGV Usage: $0 action dp_ifname\n" unless ( $#ARGV == 1 );

my ( $action, $ifname ) = @ARGV;

my $intf       = Vyatta::Interface->new($ifname);
my $cfg        = Vyatta::Config->new( $intf->path() );
my $l2tpifname = $cfg->returnValue('xconnect l2tpeth');

if ( defined($l2tpifname) ) {
    my $l2tpintf = Vyatta::Interface->new($l2tpifname);
    my $l2tpcfg  = Vyatta::Config->new( $l2tpintf->path() );
    if ( not( $l2tpcfg->exists("l2tp-session") ) ) {

        # This legacy Perl script handles xconnect for static L2TPv3 sessions
        # ("l2tp-session" defined for an l2tpeth interface). If the l2tpeth
        # interface being cross-connected represents in fact a dynamic L2TPv3
        # session, the xconnect configuration will be done by the L2TPv3 VCI
        # component.
        exit 0;
    }
}

# The cross-connected peer: the last configured of l2tpeth, vhost and
# dataplane, read with $get (returnValue or returnOrigValue).
sub peer {
    my ($get) = @_;
    my ($peer) =
      grep { defined } reverse map { $cfg->$get("xconnect $_") } qw(l2tpeth vhost dataplane);
    return $peer;
}

my $peer_ifname     = peer('returnValue');
my $old_peer_ifname = peer('returnOrigValue');
my $xconn_ttl       = $cfg->returnValue('xconnect ttl');

XConnectConfig::CommandType->import(":constants");

sub set_xconnect_port_l2tpeth {
    my ( $cmd, $new_ifname ) = @_;
    my $ctrl = Vyatta::VPlaned->new();
    my $ttl  = $xconn_ttl // "255";

    $ctrl->store( "interfaces dataplane $ifname xconnect",
        "l2tpeth -c $cmd $ifname $new_ifname $ttl" );
    return;
}

sub set_xconnect_port {
    my ( $cmd, $new_ifname ) = @_;
    my $ctrl = Vyatta::VPlaned->new();

    my $xconnect = XConnectConfig->new(
        {
            cmd        => $cmd,
            dp_ifname  => $ifname,
            new_ifname => $new_ifname,
        }
    );

    $ctrl->store_pb( "interfaces dataplane $ifname xconnect", $xconnect, "vyatta:xconnect" );
    return;
}

# What to tell the dataplane: (operation, peer), or () for nothing.
sub change {
    return ( 'add', $peer_ifname )        if $action eq 'SET';
    return ( 'remove', $old_peer_ifname ) if $action eq 'DELETE';
    return                                if !defined $old_peer_ifname;
    return ( 'remove', $old_peer_ifname ) if !defined $peer_ifname;
    return ( 'update', $peer_ifname );
}

my %pb_command = ( add => ADD(), remove => REMOVE(), update => UPDATE() );
my ( $op, $peer ) = change();
if ( defined $op ) {
    if ( defined $l2tpifname ) {
        set_xconnect_port_l2tpeth( $op, $peer );
    }
    else {
        set_xconnect_port( $pb_command{$op}, $peer );
    }
}

exit 0;
