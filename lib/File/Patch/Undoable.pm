package File::Patch::Undoable;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Builtin::Logged qw(system);
use File::Temp qw(tempfile);
use SHARYANTO::Proc::ChildError qw(explain_child_error);

our $VERSION = '0.01'; # VERSION

our %SPEC;

$SPEC{patch} = {
    v           => 1.1,
    summary     => 'Patch a file, with undo support',
    description => <<'_',

On do, will patch file with the supplied patch. On undo, will apply the reverse
of the patch.

Note: Symlink is currently not permitted (except for the patch file). Patching
is currently done with the `patch` program.

Unfixable state: file does not exist or not a regular file (directory and
symlink included), patch file does not exist or not a regular file (but symlink
allowed).

Fixed state: file exists, patch file exists, and patch has been applied.

Fixable state: file exists, patch file exists, and patch has not been applied.

_
    args        => {
        # naming the args 'path' and 'patch' can be rather error prone
        file => {
            summary => 'Path to file to be patched',
            schema => 'str*',
            req    => 1,
            pos    => 0,
        },
        patch => {
            summary => 'Path to patch file',
            description => <<'_',

Patch can be in unified or context format, it will be autodetected.

_
            schema => 'str*',
            req    => 1,
            pos    => 1,
        },
        reverse => {
            summary => 'Whether to apply reverse of patch',
            schema => [bool => {default=>0}],
            cmdline_aliases => {R=>{}},
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
    deps => {
        prog => 'patch',
    },
};
sub patch {
    my %args = @_;

    # TMP, schema
    my $tx_action  = $args{-tx_action} // '';
    my $dry_run    = $args{-dry_run};
    my $file       = $args{file};
    defined($file) or return [400, "Please specify file"];
    my $patch      = $args{patch};
    defined($patch) or return [400, "Please specify patch"];
    my $rev        = !!$args{reverse};

    my $is_sym  = (-l $file);
    my @st      = stat($file);
    my $exists  = $is_sym || (-e _);
    my $is_file = (-f _);
    my $patch_exists  = (-e $patch);
    my $patch_is_file = (-f _);

    my @cmd;

    if ($tx_action eq 'check_state') {
        return [412, "File $file does not exist"] unless $exists;
        return [412, "File $file is not a regular file"] if $is_sym||!$is_file;
        return [412, "Patch $patch does not exist"] unless $patch_exists;
        return [412,"Patch $patch is not a regular file"] unless $patch_is_file;

        # check whether patch has been applied by testing the reverse patch
        @cmd = ("patch", "--dry-run", "-sf", "-r","-", ("-R")x!$rev,
                $file, "-i",$patch);
        system @cmd;
        if (!$?) {
            return [304, "Patch $patch already applied to $file"];
        } elsif (($? >> 8) == 1) {
            $log->info("(DRY) Patching file $file with $patch ...") if $dry_run;
            return [200, "File $file needs to be patched with $patch", undef,
                    {undo_actions=>[
                        [patch=>{file=>$file, patch=>$patch, reverse=>!$rev}],
                    ]}];
        } else {
            return [500, "Can't patch: ".explain_child_error()];
        }

    } elsif ($tx_action eq 'fix_state') {
        $log->info("Patching file $file with $patch ...");

        # first patch to a temporary output first, because patch can produce
        # half-patched file.
        my ($tmpfh, $tmpname) = tempfile(DIR=>".");

        @cmd = ("patch", "-sf","-r","-", ("-R")x!!$rev,
                $file, "-i",$patch, "-o", $tmpname);
        system @cmd;
        if ($?) {
            unlink $tmpname;
            return [500, "Can't patch: ".explain_child_error()];
        }

        # now rename the temp file to the original file
        unless (rename $tmpname, $file) {
            unlink $tmpname;
            return [500, "Can't rename $tmpname -> $file: $!"];
        }

        return [200, "OK"];
    }
    [400, "Invalid -tx_action"];
}

1;
# ABSTRACT: Patch a file, with undo support


__END__
=pod

=head1 NAME

File::Patch::Undoable - Patch a file, with undo support

=head1 VERSION

version 0.01

=head1 FAQ

=head2 Why use the patch program? Why not use a Perl module like Text::Patch?

The B<patch> program has many nice features that L<Text::Patch> lacks, e.g.
applying reverse patch (needed to check fixed state and to undo), autodetection
of patch type, ignoring whitespace and fuzz factor, etc.

=head1 SEE ALSO

L<Rinci::Transaction>

L<Text::Patch>, L<PatchReader>, L<Text::Patch::Rred>

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 patch(%args) -> [status, msg, result, meta]

Patch a file, with undo support.

On do, will patch file with the supplied patch. On undo, will apply the reverse
of the patch.

Note: Symlink is currently not permitted (except for the patch file). Patching
is currently done with the C<patch> program.

Unfixable state: file does not exist or not a regular file (directory and
symlink included), patch file does not exist or not a regular file (but symlink
allowed).

Fixed state: file exists, patch file exists, and patch has been applied.

Fixable state: file exists, patch file exists, and patch has not been applied.

This function is idempotent (repeated invocations with same arguments has the same effect as single invocation). This function supports transactions.


Arguments ('*' denotes required arguments):

=over 4

=item * B<file>* => I<str>

Path to file to be patched.

=item * B<patch>* => I<str>

Path to patch file.

Patch can be in unified or context format, it will be autodetected.

=item * B<reverse> => I<bool> (default: 0)

Whether to apply reverse of patch.

=back

Special arguments:

=over 4

=item * B<-tx_action> => I<str>

For more information on transaction, see L<Rinci::Transaction>.

=item * B<-tx_action_id> => I<str>

For more information on transaction, see L<Rinci::Transaction>.

=item * B<-tx_recovery> => I<str>

For more information on transaction, see L<Rinci::Transaction>.

=item * B<-tx_rollback> => I<str>

For more information on transaction, see L<Rinci::Transaction>.

=item * B<-tx_v> => I<str>

For more information on transaction, see L<Rinci::Transaction>.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

