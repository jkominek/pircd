#!/usr/bin/perl
# 
# Utils.pm
# Created: Wed Sep 23 21:56:44 1998 by jay.kominek@colorado.edu
# Revised: Fri Feb 12 12:18:04 1999 by jay.kominek@colorado.edu
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

# We store these structures in a globalish location,
# to let everything get at the same data.
my %users    = ();
my %servers  = ();
my %channels = ();

my $syslogsetup = 0;

sub version {
  return "pircd-alpha-nine";
}

sub lookup {
  my $name = shift;
  chomp $name;
  # Because of IRC's crazy scandanavian origins, {}| is considered
  # the lower case form of []\ and so we have to use our own tr///;
  # to do the same thing as lc() would. *sigh*
  $name = &irclc($name);

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
  $name = &irclc($name);
  return $users{$name};
}

# This only looks up channels
sub lookupchannel {
  my $name = shift;
  chomp $name;
  $name = &irclc($name);
  return $channels{$name};
}

# This only looks up servers.
sub lookupserver {
  my $name = shift;
  chomp $name;
  $name = &irclc($name);
  return $servers{$name};
}

sub users    { return \%users;    }
sub channels { return \%channels; }
sub servers  { return \%servers;  }

# Log something
sub syslog {
  my $data = shift;

  if(!$syslogsetup) {
    openlog('pircd','ndelay,pid','daemon');
    $syslogsetup = 1;
  }

  syslog(@_);
}

sub irclc ($) {
  my $data = shift;
  $data =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $data;
}

1;
