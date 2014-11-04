use strict; use warnings;
package Inline::Module;
our $VERSION = '0.02';

use File::Path;
use Inline();

# use XXX;

###
# The purpose of this module is to support:
#
#   perl-inline-module create lib/Foo/Inline.pm
###

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub run {
    my ($self) = @_;
    $self->get_opts;
    my $method = "do_$self->{command}";
    die usage() unless $self->can($method);
    $self->$method;
}

sub do_create {
    my ($self) = @_;
    my @modules = @{$self->{args}};
    die "The 'create' command requires at least on module name to create\n"
        unless @modules >= 1;
    for my $module (@modules) {
        $self->create_module($module);
    }
}

sub create_module {
    my ($self, $module) = @_;
    die "Invalid module name '$module'"
        unless $module =~ /^[A-Za-z]\w*(?:::[A-Za-z]\w*)*$/;
    my $filepath = $module;
    $filepath =~ s!::!/!g;
    $filepath = "lib/$filepath.pm";
    my $dirpath = $filepath;
    if (-e $filepath) {
        warn "'$filepath' already exists\n";
        # TODO uncomment this and support 'recreate' command.
#         return;
    }
    $dirpath =~ s!(.*)/.*!$1!;
    File::Path::mkpath($dirpath);
    open OUT, '>', $filepath
        or die "Can't open '$filepath' for output:\n$!";
    print OUT $self->proxy_module($module);
    print "Inline module '$module' created as '$filepath'\n";
}

sub import {
    my $class = shift;
    return unless @_;
    my ($inline_module) = caller;
    # XXX exit here is to get cleaner error msg. Try to redo without exit.
    $class->check_api_version($inline_module, @_)
        or exit 1;
    my $importer = sub {
        require File::Path;
        File::Path::mkpath('./blib') unless -d './blib';
        # TODO try to not use eval here:
        eval "use Inline Config => " .
            "directory => './blib', " .
            "name => '$inline_module'";

        my $class = shift;
        Inline->import_heavy(@_);

        my $file = $inline_module;
        $file =~ s/.*:://;
        my $name_path = $inline_module;
        $name_path =~ s!::!/!g;
        File::Path::mkpath("blib/lib/$name_path");
        open OUT, '>', "blib/lib/$name_path.pm"
            or die $!;
        print OUT <<"...";
use strict; use warnings;
package $inline_module;
use DynaLoader;
our \@ISA = qw( DynaLoader );
bootstrap $inline_module;

# XXX - think about this later:
# our \$VERSION = '0.0.5';
# bootstrap $inline_module \$VERSION;

1;
...
        close OUT;
    };
    no strict 'refs';
    *{"${inline_module}::import"} = $importer;

}

sub check_api_version {
    my ($class, $inline_module, $api_version, $inline_module_version) = @_;
    if ($api_version ne 'v1' or $inline_module_version ne $VERSION) {
        warn <<"...";
It seems that '$inline_module' is out of date.

Make sure you have the latest version of Inline::Module installed, then run:

    perl-inline-module recreate $inline_module

...
        return;
    }
    return 1;
}

sub proxy_module {
    my ($self, $module) = @_;
    return <<"...";
# DO NOT EDIT:
#
# This file was generated by: Inline::Module $Inline::Module::VERSION
#
# This module is for author-side development only. When this module is shipped
# to CPAN, it will be replaced with content that does not require any Inline
# framework modules (or any other non-core modules).

use strict;
use warnings;
package $module;
use base 'Inline';

use Inline::Module 'v1' => '$VERSION';

1;
...
}

sub get_opts {
    my ($self) = @_;
    my $argv = $self->{argv};
    die usage() unless @$argv >= 1;
    my ($command, @args) = @$argv;
    $self->{command} = $command;
    $self->{args} = \@args;
    delete $self->{argv};
}

sub usage {
    <<'...';
Usage:
        perl-inline-module <command> [<arguments>]

Commands:
        perl-inline-module create Module::Name::Inline

...
}

1;
