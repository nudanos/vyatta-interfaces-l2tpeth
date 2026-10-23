# Test stub for the generated XConnectConfig protobuf module.
## no critic (Modules::RequireFilenameMatchesPackage, Modules::ProhibitMultiplePackages) reason: the generated module defines these packages
package XConnectConfig;
use strict;
use warnings;

sub new { my ( $class, $fields ) = @_; return bless { %{$fields} }, $class; }

package XConnectConfig::CommandType;
sub ADD    { return 'ADD' }
sub REMOVE { return 'REMOVE' }
sub UPDATE { return 'UPDATE' }

sub import {
    my $caller = caller;
    no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict) reason: exporting the constants
    *{"${caller}::$_"} = \&{$_} foreach qw(ADD REMOVE UPDATE);
    return;
}

1;
