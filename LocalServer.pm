#!/usr/bin/perl
# 
# LocalServer.pm
# Created: Sat Sep 26 18:11:12 1998 by jay.kominek@colorado.edu
# Revised: Sun Jun 27 23:39:58 1999 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# Local Server object for The Perl Internet Relay Chat Daemon
#####################################################################

package LocalServer;
use User;
use Channel;
use Server;
use strict;
use Utils;
use vars qw(@ISA);
use UNIVERSAL qw(isa);
@ISA=qw{Server};

use Tie::IRCUniqueHash;

###################
# CLASS CONSTRUCTOR
###################

# Pass it the name of its configuration file

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{'conffile'} = shift || "server.conf";

  my(%opertmp,%usertmp,%childtmp);
  tie %opertmp,  'Tie::IRCUniqueHash';
  $this->{'opers'}    = \%opertmp;
  tie %usertmp,  'Tie::IRCUniqueHash';
  $this->{'users'}    = \%usertmp;
  tie %childtmp, 'Tie::IRCUniqueHash';
  $this->{'children'} = \%childtmp;

  &loadconffile($this);

  bless($this, $class);
  return $this;
}

sub loadconffile {
  my $this = shift;

  open(CONF,$this->{'conffile'});
  my @lines = <CONF>;
  close(CONF);
  my $line;
 CONFPARSE: foreach $line (@lines) {
    chomp($line);

    # Machine line
    if($line =~ /^M:([\w\d\.]+):\*:([^:]+):(\d+)/) {
      $this->{'name'}        = $1;
      $this->{'description'} = $2;
      $this->{'port'}        = $3;
      next CONFPARSE;
    }
    # Admin line
    if($line =~ /^A:([^:]+):([^:]+):([^:]+)/) {
      @{$this->{'admin'}} = ($1,$2,$3);
      next CONFPARSE;
    }
    # MOTD line
    if($line =~ /^MOTD:(.+)$/) {
      if(open(MOTD,$1)) {
	@{$this->{'motd'}} = <MOTD>;
	close(MOTD);
	chomp(@{$this->{'motd'}});
      } else {
	@{$this->{'motd'}} = ($1);
      }
      next CONFPARSE;
    }
    # OPER line
    if($line =~ /^O:([^:]+):([^:]+):([^:]+)$/) {
      my($nick,$mask,$password) = ($1,$2,$3);
      $mask =~ s/\./\\\./g;
      $mask =~ s/\?/\./g;
      $mask =~ s/\*/\.\*/g;
      $this->{'opers'}->{ $nick }->{'mask'} = $mask;
      $this->{'opers'}->{ $nick }->{'password'} = $password;
      next CONFPARSE;
    }
    # Kill Line
    if($line =~ /^K:([^:]+):([^:]+):([^.]+)$/) {
      my($mask,$reason,$usermask) = ($1,$2,$3);
      $mask =~ s/\./\\\./g;
      $mask =~ s/\?/\./g;
      $mask =~ s/\*/\.\*/g;
      $usermask =~ s/\./\\\./g;
      $usermask =~ s/\?/\./g;
      $usermask =~ s/\*/\.\*/g;
      $this->{'klines'}->{$mask} = [$usermask,$mask,$reason];
      next CONFPARSE;
    }
    # Connection Line
    if($line =~ /^C:([^:]+):([^:]+):([^:]+):?(\d*)$/) {
      my($server,$address,$password,$port) = ($1,$2,$3,$4 || 0);
      $this->{'connections'}->{$server} = [$server,$address,$password,$port];
      next CONFPARSE;
    }
    # Network Line
    if($line =~ /^N:([^:]+):([^:]+):([^:]+)$/) {
      my($server,$address,$password) = ($1,$2,$3,$4);
      $this->{'nets'}->{$server}     = [$server,$address,$password];
      next CONFPARSE;
    }
  }
}

# Things That Do Things

sub rehash {
  my $this = shift;
  my $from = shift;
  my $user;
  foreach $user (values(%{$this->{'users'}})) {
    if($user->ismode('s')) {
      $user->notice($this,"*** Notice -- ".$from->nick." is rehashing Server config file");
    }
  }
  &loadconffile($this);
}

sub opernotify {
  my $this = shift;
  my $msg  = shift;

  my $user;
  foreach $user (values(%{$this->{'users'}})) {
    if($user->ismode('o')) {
      $user->notice($this,"*** Notice --- $msg");
    }
  }
  Utils::syslog('info',$msg);
}

############################
# DATA ACCESSING SUBROUTINES
############################

# Provides the name of this IRC server
sub name {
  my $this = shift;
  return $this->{'name'};
}

sub lcname {
  my $this = shift;
  my $tmp  = $this->{'name'};
  $tmp     =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $tmp;
}

sub description {
  my $this = shift;
  return $this->{'description'};
}

sub users {
  my $this = shift;
  my @foo = values(%{$this->{'users'}});
  return @foo;
}

sub children {
  my $this = shift;
  my @foo  = values(%{$this->{'children'}});
  return @foo;
}

sub parent {
  # We're the local server. We don't have a parent
  # (from our perspective)
  return undef;
}

sub hops {
  return 0;
}

sub version {
  return &Utils::version;
}

sub creation {
  return time();
}

# Returns the MOTD of the server as an array of lines.
sub getmotd {
  my $this = shift;
  return @{$this->{'motd'}};
}

# Same thing as getmotd, except for the admin information
sub getadmin {
  my $this = shift;
  return @{$this->{'admin'}};
}

sub getopers {
  my $this = shift;
  my @foo = keys %{$this->{'opers'}};
  print "getopers: @foo\n";
  return $this->{'opers'};
}

sub lookupconnection {
  my $this   = shift;
  my $server = shift;
  return $this->{'connections'}->{$server};
}

sub lookupnetwork {
  my $this   = shift;
  my $server = shift;
  return $this->{'nets'}->{$server};
}

###############################
# DATA MANIPULATING SUBROUTINES
###############################

sub adduser {
  my $this = shift;
  my $user = shift;
  $this->{'users'}->{$user->nick()} = $user;
}

sub removeuser {
  my $this = shift;
  my $user = shift;

  my $nick;
  if(ref($user)) {
    $nick = $user->nick();
  } else {
    $nick = $user;
  }

  delete($this->{'users'}->{$nick});
}

sub addchildserver {
  my $this  = shift;
  my $child = shift;
  $this->{'children'}->{$child->name()} = $child;
}

sub removechildserver {
  my $this  = shift;
  my $child = shift;

  my $name;
  if(ref($child)) {
    $name = $child->name();
  } else {
    $name = $child;
  }
  delete($this->{'children'}->{$name});
}

1;
