#!/usr/bin/perl
# 
# Utils.pm
# Created: Wed Sep 23 21:56:44 1998 by jay.kominek@colorado.edu
# Revised: Sun Oct 31 14:07:43 1999 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
# 
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# Methods to access global data structures, and the data structures
# themselves.
#####################################################################

package Utils;
use User;
use Server;
use Channel;
use Sys::Syslog;
use UNIVERSAL qw(isa);
use strict;

use Tie::IRCUniqueHash;
# We store these structures in a globalish location,
# to let everything get at the same data.
tie my %users,    'Tie::IRCUniqueHash';
tie my %servers,  'Tie::IRCUniqueHash';
tie my %channels, 'Tie::IRCUniqueHash';

my $syslogsetup = 0;

sub version {
  return "pircd-alpha-twelve";
}

sub lookup {
  my $name = shift;
  chomp $name;

  # If it starts with a # or &, then it is a channel that we're
  # trying to look up.
  if(($name =~ /^\#/) || ($name =~ /^\&/)) {
    if($channels{$name}) {
      return $channels{$name};
    } else {
      return undef;
    }
  } elsif($name =~ /\./) {
    # If it has a period in it, then it has to be a server. Assuming
    # we did proper checking on new nicks. Which we don't.
    if($servers{$name}) {
      return $servers{$name};
    } else {
      return undef;
    }
  } elsif($users{$name}) {
    # If its anything else, then it must be a user.
    return $users{$name};
  } else {
    return undef;
  }
}

# This only looks up users, in case you know exactly what you're
# looking for.
sub lookupuser {
  my $name = shift;
  chomp $name;
  return $users{$name};
}

# This only looks up channels
sub lookupchannel {
  my $name = shift;
  chomp $name;
  return $channels{$name};
}

# This only looks up servers.
sub lookupserver {
  my $name = shift;
  chomp $name;
  return $servers{$name};
}

sub users    { return \%users;    }
sub channels { return \%channels; }
sub servers  { return \%servers;  }

# Log something
sub syslog {
  my $data = shift;

  if(!$syslogsetup) {
#    openlog('pircd','ndelay,pid','daemon');
    open(STDERR, ">>pircd.log") or die "Unable to open pircd.log: $!";
    $syslogsetup = 1;
  }

#  syslog(@_);
  print STDERR "$data: ",shift,"\n";
}

sub irclc ($) {
  my $data = shift;
  $data =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $data;
}

1;
