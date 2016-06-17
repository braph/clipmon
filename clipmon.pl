#!/usr/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

=begin COPYRIGHT

	clipmon - run actions depending on the content of your clipboard
	Copyright (C) 2015 Benjamin Abendroth
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.

=end COPYRIGHT

=cut

use strict;
use warnings;
use autodie;

use Tie::IxHash;
use Getopt::Long qw(:config gnu_getopt auto_version);
use Config::General qw(ParseConfig);
use Text::ParseWords qw(shellwords);

use constant DEFAULT_CONFIG => $ENV{HOME} . '/.config/clipmon.rc';

$main::VERSION = '0.2';

# options with default settings
my %options = (
   'sleep'        => 1,
   'clipboards'   => 'clipboard,primary',
   'daemon'       => 0,
   'shot'         => 0,
   'rules'        => undef
);

my $clipboard_function;
my %clipboard_functions;

$clipboard_functions{xsel} = sub {
   return `xsel -o --$_[0]`;
};
$clipboard_functions{xclip} = sub {
   return `xclip -o -selection $_[0]`;
};

for ('xsel', 'xclip') {
   if (! system('which', $_)) {
      $clipboard_function = $clipboard_functions{$_};
      last;
   }
}

die "You need to have xclip or xsel to be installed\n"
   if not $clipboard_function;

exit main();

sub checkOptions
{
   die "Option 'sleep' is invalid\n"
      if $options{sleep} !~ /^\d+$/;

   $options{clipboards} = [ split ',', $options{clipboards} ]
      unless ref $options{clipboards};

   for (@{$options{clipboards}}) {
      die "Option 'clipboards': '$_' is not a valid clipboard\n"
         unless /^(primary|secondary|clipboard)$/;
   }
}

sub checkRules
{
   my $rules = $options{rules} or die "No rules found\n";

   while (my ($name, $rule) = each %$rules)
   {
      for (keys %$rule) {
         die "Unknown option in rule '$name': $_\n"
            if ! /^(match|exec|continue)$/;
      }


      die "Rule '$name': 'match' not set\n"
         if ! exists $rule->{match};

      $rule->{match} = forceArray($rule->{match});
      for my $match (@{ $rule->{match} }) {
         $match = qr($match);
      }

      $rule->{exec} = forceArray($rule->{exec});
   }
}

sub print_help
{
   require Pod::Usage;
   Pod::Usage::pod2usage(-exitstatus => 0, -verbose => 2);
}

sub init
{
   my $rcFile = DEFAULT_CONFIG;

   # process "pseudo options" first
   Getopt::Long::Configure qw(pass_through);
   GetOptions(
      'help|h'    => \&print_help,
      'config=s'  => \$rcFile
   );

   tie my %rcHash, 'Tie::IxHash';
   %rcHash = ParseConfig(
      -ConfigFile => $rcFile,
      -InterPolateEnv => 'no',
      -Tie => 'Tie::IxHash',
      -AllowMultiOptions => 'yes'
   );

   for (keys %rcHash) {
      die "Config file: Unknown option: $_\n"
         if ! exists $options{$_};
   }

   %options = (%options, %rcHash);
   eval { checkOptions; 1 } or die "Config file: $@";
   eval { checkRules; 1 }   or die "Config file: $@";

   # now read (and overwrite) the "real options"
   Getopt::Long::Configure qw(no_pass_through);
   GetOptions(\%options,
      'sleep=i',
      'clipboards|c=s',
      'daemon|d!',
      'shot|s!'
   ) or exit 1;

   eval { checkOptions; 1 } or die "Commandline: $@";
}

sub main
{
   init;

   (fork == 0 || exit 0) if $options{daemon};

   my $oldOut = '';

   while() {
      for my $board (@{$options{clipboards}}) {
         print "$oldOut\n";
         my $out = $clipboard_function->($board) or next;
         processBoard($oldOut = $out) if $oldOut ne $out;
      }

      exit 0 if $options{shot};
      sleep $options{sleep};
   }
}

sub forceArray
{
   my $array = shift || return [];
   return $array if ref $array eq 'ARRAY';
   return [ $array ] unless ref $array;
   die "not an array";
}

sub get_execve
{
   my ($exec, $underscore) = @_;

   my @execve = shellwords($exec);
   for my $arg (@execve) {
      $arg =~ s/(?<=[^\$])\$_/$underscore/g;
   }

   return @execve;
}

sub processBoard
{
   my $input = shift;

   while (my ($name, $rule) = each %{$options{rules}}) {
      for my $match (@{$rule->{match}}) {
         if ($input =~ /$match/) {
            for my $exec (@{$rule->{exec}}) {
               my @execve = get_execve($exec, $input);
               exec @execve if fork == 0;
            }

            return unless $rule->{continue};
            last;
         }
      }
   }
}

__END__

=pod

=head1 NAME

clipmon.pl - trigger actions while monitoring clipoard

=head1 SYNOPSIS

=over

clipmon.pl [I<OPTION>]...

=back

=head1 OPTIONS

=head2 Basic Startup Options

=over

=item B<--help>

Display this help text and exit.

=item B<--version>

Display the script version and exit.

=item B<--config> I<file>

Use config file given in I<file>.

=back

=head2 General Options

=over

=item B<--clipboards|-c>

Comma separated list of clipboards to use.
Valid values: B<secondary>, B<primary>, B<clipboard>.

=item B<--daemon|-d>

Fork to background.

=item B<--shot|-s>

Match clipboard, run actions and exit immediatly.

=item B<--sleep> I<SECONDS>

Sleep I<SECONDS> seconds between each clipboard poll.
Defaults to B<1>.

=back   

=head1 CONFIGURATION

=over

Syntax:

<rule>
   match = perlre
   exec = command arg1 arg2 argN
   continue # optional
</rule>

=back

=head1 FILES

=over

=item I<~/.config/clipmon/clipmon.rc>

Default configuration file. See B<--config>.

=back

=head1 AUTHOR

Written by Benjamin Abendroth.

=cut

