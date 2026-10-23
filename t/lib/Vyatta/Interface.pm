# Test stub for Vyatta::Interface: only the configuration path.
package Vyatta::Interface;
use strict;
use warnings;

sub new { my ( $class, $name ) = @_; return bless { name => $name }, $class; }
sub path { my ($self) = @_; return "interfaces l2tpeth $self->{name}"; }

1;
