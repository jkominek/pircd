#!/usr/bin/perl
# 
# LocalServer.pm
# Created: Sat Sep 26 18:11:12 1998 by jay.kominek@colorado.edu
# Revised: Sat Feb  6 10:08:58 1999 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 1, or (at your option) any
# later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 675 Mass Ave, Cambridge, MA 02139, USA.
# 
#####################################################################
# Local Server object for The Perl Internet Relay Chat Daemon
#####################################################################

package LocalServer;
use User;
use Channel;
use Server;
use strict;
use vars qw(@ISA);
use UNIVERSAL qw(isa);
@ISA=qw{Server};

###################
# CLASS CONSTRUCTOR
###################

# Pass it the name of its configuration file

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{conffile} = (shift||"server.conf");
  &loadconffile($this);

  bless($this, $class);
  return $this;
}

sub loadconffile {
  my $this = shift;

  open(CONF,$this->{conffile});
  my @lines = <CONF>;
  close(CONF);
  my $line;
 CONFPARSE: foreach $line (@lines) {
    chomp($line);

    # Machine line
    if($line =~ /^M:([\w\d\.]+):\*:([^:]+):(\d+)/) {
      $this->{name}        = $1;
      $this->{description} = $2;
      $this->{port}        = $3;
      next CONFPARSE;
    }
    # Admin line
    if($line =~ /^A:([^:]+):([^:]+):([^:]+)/) {
      @{$this->{admin}} = ($1,$2,$3);
      next CONFPARSE;
    }
    # MOTD line
    if($line =~ /^MOTD:(.+)$/) {
      if(open(MOTD,$1)) {
	@{$this->{motd}} = <MOTD>;
	close(MOTD);
	chomp(@{$this->{motd}});
      } else {
	@{$this->{motd}} = ($1);
      }
      next CONFPARSE;
    }
    # OPER line
    if($line =~ /^O:([^:]+):([^:]+):([^:]+)$/) {
      my($nick,$mask,$password) = ($1,$2,$3);
      $mask =~ s/\./\\\./g;
      $mask =~ s/\?/\./g;
      $mask =~ s/\*/\.\*/g;
      $this->{opers}->{$nick}->{mask} = $mask;
      $this->{opers}->{$nick}->{password} = $password;
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
  my %tmp = ();
  if(defined($this->{'opers'})) {
    return $this->{'opers'};
  } else {
    return \%tmp;
  }
}

###############################
# DATA MANIPULATING SUBROUTINES
###############################

sub adduser {
  my $this = shift;
  my $user = shift;
  $this->{'users'}->{$user->lcnick()} = $user;
}

sub removeuser {
  my $this = shift;
  my $user = shift;

  my $nick;
  if(ref($user)) {
    $nick = $user->lcnick();
  } else {
    $nick = $user;
  }

  delete($this->{'users'}->{$nick});
}

sub addchildserver {
  my $this  = shift;
  my $child = shift;
  $this->{'children'}->{$child->lcname()} = $child;
}

sub removechildserver {
  my $this  = shift;
  my $child = shift;

  my $name;
  if(ref($child)) {
    $name = $child->lcname();
  } else {
    $name = $child;
  }
  delete($this->{'children'}->{$name});
}

1;
