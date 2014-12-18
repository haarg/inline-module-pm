use strict; use warnings;
package Inline::Module;
our $VERSION = '0.24';
our $API_VERSION = 'v2';

use Config();
use File::Path();
use File::Find();
use Carp 'croak';

# use XXX;

my $inline_build_path = './blib/Inline';

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

use constant DEBUG_ON => $ENV{PERL_INLINE_MODULE_DEBUG} ? 1 : 0;
sub DEBUG { if (DEBUG_ON) { print "DEBUG >>> ", sprintf(@_), "\n" }}

#------------------------------------------------------------------------------
# This import serves multiple roles:
# - -MInline::Module=autostub
# - ::Inline module's proxy to Inline.pm
# - Makefile.PL postamble
# - Makefile rule support
#------------------------------------------------------------------------------
sub import {
    my $class = shift;
    DEBUG_ON && DEBUG "Inline::Module::import(@_)";

    my ($stub_module, $program) = caller;

    if ($program eq 'Makefile.PL' && not -e 'INLINE.h') {
        no warnings 'once';
        *MY::postamble = \&postamble;
        return;
    }

    return unless @_;
    my $cmd = shift;

    return $class->handle_stub($stub_module, @_)
        if $cmd eq 'stub';
    return $class->handle_autostub(@_)
        if $cmd eq 'autostub';
    return $class->handle_distdir(@ARGV)
        if $cmd eq 'distdir';
    return $class->handle_fixblib()
        if $cmd eq 'fixblib';
    return $class->handle_makestub(@_)
        if $cmd eq 'makestub';

    die "Unknown Inline::Module::import argument '$cmd'"
}

sub check_api_version {
    my ($class, $stub_module, $api_version) = @_;
    if ($api_version ne $API_VERSION) {
        warn <<"...";
It seems that '$stub_module' is out of date.
It is using Inline::Module API version '$api_version'.
You have Inline::Module API version '$API_VERSION' installed.

Make sure you have the latest version of Inline::Module installed, then run:

    perl -MInline::Module=makestub,$stub_module

...
        # XXX 'exit' is used to get a cleaner error msg.
        # Try to redo this without 'exit'.
        exit 1;
    }
}

sub importer {
    my ($class, $stub_module) = @_;
    return sub {
        my ($class, $lang) = @_;
        return unless defined $lang;
        require File::Path;
        File::Path::mkpath($inline_build_path)
            unless -d $inline_build_path;
        require Inline;
        Inline->import(
            Config =>
            directory => $inline_build_path,
            ($lang eq 'C') ? (using => 'Inline::C::Parser::RegExp') : (),
            name => $stub_module,
            CLEAN_AFTER_BUILD => 0,
        );
        shift(@_);
        DEBUG_ON && DEBUG "Inline::Module::importer proxy to Inline::%s", @_;
        Inline->import_heavy(@_);
    };
}

#------------------------------------------------------------------------------
# The postamble methods:
#------------------------------------------------------------------------------
sub postamble {
    my ($makemaker, %args) = @_;

    my $inline = $args{inline}
        or croak "'postamble' section requires 'inline' key in Makefile.PL";
    croak "postamble 'inline' section requires 'module' key in Makefile.PL"
        unless $inline->{module};

    my $self = $Inline::Module::Self = Inline::Module->new;
    $self->default_args($inline, $makemaker);

    my $code_modules = $self->{module};
    my $stub_modules = $self->{stub};
    my @included_modules = $self->included_modules;

    my $section = <<"...";
distdir : distdir_inline

distdir_inline : create_distdir
\t\$(NOECHO) \$(ABSPERLRUN) -MInline::Module=distdir -e 1 -- \$(DISTVNAME) @$stub_modules -- @included_modules

pure_all ::
...
    for my $module (@$code_modules) {
        $section .=
            "\t\$(NOECHO) \$(ABSPERLRUN) -Iinc -Ilib -e 'use $module'\n";
    }
    $section .=
        "\t\$(NOECHO) \$(ABSPERLRUN) -Iinc -MInline::Module=fixblib -e 1";

    return $section;
}

sub default_args {
    my ($self, $args, $makemaker) = @_;
    $args->{module} = $makemaker->{NAME} unless $args->{module};
    $args->{module} = [ $args->{module} ] unless ref $args->{module};
    $args->{stub} ||= [ map "${_}::Inline", @{$args->{module}} ];
    $args->{stub} = [ $args->{stub} ] unless ref $args->{stub};
    $args->{ilsm} ||= 'Inline::C';
    $args->{ilsm} = [ $args->{ilsm} ] unless ref $args->{ilsm};
    %$self = %$args;
}

sub included_modules {
    my ($self) = @_;
    my $ilsm = $self->{ilsm};
    my @include = (
        'Inline',
        'Inline::denter',
        'Inline::Module',
        @$ilsm,
    );
    if (caller eq 'Module::Build::InlineModule') {
        push @include, 'Module::Build::InlineModule';
    }
    if (grep /:C$/, @$ilsm) {
        push @include,
            'Inline::C::Parser::RegExp';
    }
    if (grep /:CPP$/, @$ilsm) {
        push @include,
            'Inline::C',
            'Inline::CPP::Config',
            'Inline::CPP::Parser::RecDescent',
            'Parse::RecDescent';
    }
    return @include;
}

#------------------------------------------------------------------------------
# Class methods.
#------------------------------------------------------------------------------
sub handle_stub {
    my ($class, $stub_module, $api_version) = @_;
    $class->check_api_version($stub_module, $api_version);
    no strict 'refs';
    *{"${stub_module}::import"} = $class->importer($stub_module);
    return;
}

sub handle_makestub {
    my ($class, @args) = @_;

    my @modules;
    for my $arg (@args) {
        if ($arg =~ /::/) {
            push @modules, $arg;
        }
        else {
            croak "Unknown 'makestub' argument: '$arg'";
        }
    }
    my $dest = 'lib';

    for my $module (@modules) {
        my $code = $class->proxy_module($module);
        my $path = $class->write_module($dest, $module, $code);
        print "Created stub module '$path' (Inline::Module $VERSION)\n";
    }

    exit 0;
}

sub handle_autostub {
    my ($class, @args) = @_;

    # Don't mess with Perl tools, while using PERL5OPT and autostub:
    return unless
        $0 eq '-e' or
        defined $ENV{_} and $ENV{_} =~ m!/prove[^/]*$!;
    # Don't autostub in the distdir:
    return if -e './inc/Inline/Module.pm';

    DEBUG_ON && DEBUG "Inline::Module::autostub(@_)";

    require lib;
    lib->import('lib');

    my %autostub_modules;
    for my $arg (@args) {
        if ($arg =~ m!::!) {
            $autostub_modules{$arg} = 1;
        }
        else {
            croak "Unknown 'autostub' argument: '$arg'";
        }
    }

    push @INC, sub {
        my ($self, $module) = @_;
        delete $ENV{PERL5OPT};

        $module =~ s!\.pm$!!;
        $module =~ s!/!::!g;
        $autostub_modules{$module} or return;

        my $code = $class->proxy_module($module);
        open my $fh, '<', \$code;
        return $fh;
    }
}

sub handle_distdir {
    my ($class, $distdir, @args) = @_;
    my (@inlined_modules, @included_modules);

    while (@args and ($_ = shift(@args)) ne '--') {
        push @inlined_modules, $_;
    }
    while (@args and ($_ = shift(@args)) ne '--') {
        push @included_modules, $_;
    }

    my @manifest; # files created under distdir
    for my $module (@inlined_modules) {
        my $code = $class->dyna_module($module);
        $class->write_module("$distdir/lib", $module, $code);
        $code = $class->proxy_module($module);
        $class->write_module("$distdir/inc", $module, $code);
        $module =~ s!::!/!g;
        push @manifest, "lib/$module.pm", "inc/$module.pm";
    }
    for my $module (@included_modules) {
        my $code = $class->read_local_module($module);
        $class->write_module("$distdir/inc", $module, $code);
        $module =~ s!::!/!g;
        push @manifest, "inc/$module.pm";
    }

    $class->add_to_manifest($distdir, @manifest);

    return @manifest; # return a list of the files added
}

sub handle_fixblib {
    my ($class) = @_;
    my $ext = $Config::Config{dlext};
    -d 'blib'
        or die "Inline::Module::fixblib expected to find 'blib' directory";
    File::Find::find({
        wanted => sub {
            -f or return;
            if (m!^($inline_build_path/lib/auto/.*)\.$ext$!) {
                my $blib_ext = $_;
                $blib_ext =~ s!^$inline_build_path/lib!blib/arch! or die;
                my $blib_ext_dir = $blib_ext;
                $blib_ext_dir =~ s!(.*)/.*!$1! or die;
                File::Path::mkpath $blib_ext_dir;
                link $_, $blib_ext;
            }
        },
        no_chdir => 1,
    }, $inline_build_path);
}

sub read_local_module {
    my ($class, $module) = @_;
    eval "require $module; 1" or die $@;
    my $file = $module;
    $file =~ s!::!/!g;
    my $filepath = $INC{"$file.pm"};
    open IN, '<', $filepath
        or die "Can't open '$filepath' for input:\n$!";
    my $code = do {local $/; <IN>};
    close IN;
    return $code;
}

sub proxy_module {
    my ($class, $module) = @_;

    return <<"...";
# DO NOT EDIT
#
# GENERATED BY: Inline::Module $Inline::Module::VERSION
#
# This module is for author-side development only. When this module is shipped
# to CPAN, it will be automagically replaced with content that does not
# require any Inline framework modules (or any other non-core modules).
#
# To regenerate this stub module, run this command:
#
#   perl -MInline::Module=makestub,$module

use strict; use warnings;
package $module;
use Inline::Module stub => '$API_VERSION';
1;
...
}

sub dyna_module {
    my ($class, $module) = @_;
    return <<"...";
# DO NOT EDIT
#
# GENERATED BY: Inline::Module $Inline::Module::VERSION

use strict; use warnings;
package $module;
use base 'DynaLoader';
bootstrap $module;

1;
...

# XXX - think about this later:
# our \$VERSION = '0.0.5';
# bootstrap $module \$VERSION;
}

sub write_module {
    my ($class, $dest, $module, $code) = @_;

    my $filepath = $module;
    $filepath =~ s!::!/!g;
    $filepath = "$dest/$filepath.pm";
    my $dirpath = $filepath;
    $dirpath =~ s!(.*)/.*!$1!;
    File::Path::mkpath($dirpath);

    unlink $filepath;
    open OUT, '>', $filepath
        or die "Can't open '$filepath' for output:\n$!";
    print OUT $code;
    close OUT;

    return $filepath;
}

sub add_to_manifest {
    my ($class, $distdir, @files) = @_;
    my $manifest = "$distdir/MANIFEST";

    # XXX Module::Build thing.
    # XXX Call Module::Build->_add_to_manifest
    my $chmod = 0;
    if (not -w $manifest) {
        chmod 0644, $manifest;
        $chmod = 1;
    }

    open my $out, '>>', $manifest
        or die "Can't open '$manifest' for append:\n$!";
    for my $file (@files) {
        print $out "$file\n";
    }
    close $out;

    if ($chmod) {
        chmod 0444, $manifest;
    }
}

1;
