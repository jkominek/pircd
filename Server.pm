#!/usr/bin/perl
# 
# Server.pm
# Created: Tue Sep 15 13:55:23 1998 by jay.kominek@colorado.edu
# Revised: Sat Feb  6 10:11:13 1999 by jay.kominek@colorado.edu
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
# Server object for The Perl Internet Relay Chat Daemon
#####################################################################

package Server;
use Utils;
use User;
use Channel;
use strict;
use UNIVERSAL qw(isa);

###################
# CLASS CONSTRUCTOR
###################

# Pass it its name.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };
  my $connection = shift;

  $this->{name}        = $connection->{name};
  $this->{description} = $connection->{description};
  $this->{distance}    = $connection->{distance};
  $this->{proto}       = $connection->{proto};
  $this->{server}      = $connection->{server};
  $this->{last_active} = time();

  print $this->{name}." has connected using ".$this->{proto}.", it is at a distance of ".$this->{distance}."\n";

  bless($this, $class);
  if(defined($connection->{'socket'})) {
    $this->{'socket'}    = $connection->{'socket'};
    $this->{outbuffer} = $connection->{outbuffer};
    $this->setupaslocal();
  }
  $this->{server}->addchildserver($this);
  return $this;
}

sub setupaslocal {


}

sub handle {
  my $this = shift;
  my $rawline = shift;

  my $line;
  foreach $line (split(/\x00/,$rawline)) {

    $line =~ s/\s+$//;

    $this->{last_active} = time();
    delete($this->{ping_waiting});

    my $command = "NULL";

    # Parsing stuff from a server is a bit more complicated than parsing
    # for a user.
    if(ref($this->{commands}->{$command})) {
      &{$this->{commands}->{$command}}($this,$line);
    } else {
      if($line =~ /[\w\d\s]/) {
	print "Received unknown command string \"$line\" from ".$this->nick."\n";
      }
    }
  }
}

#####################################################################
# SENDING THE SERVER STUFF
##########################

sub ping {
  my $this = shift;
  if($this->{'socket'}) {
    $this->{ping_waiting} = 1;
    $this->senddata("PING :".$this->{server}->name."\r\n");
  } else {

  }
}

############################
# DATA ACCESSING SUBROUTINES
############################

# Get the name of this IRC server
sub name {
  my $this = shift;
  return $this->{'name'};
}

# Get the name of this IRC server, appropriate for
# keying a hash
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

# Returns an array of all the users on
# the server
sub users {
  my $this = shift;
  my @foo = values(%{$this->{users}});
  return @foo;
}

# Returns an array of all the children servers
sub children {
  my $this = shift;
  my @foo = values(%{$this->{children}});
  return @foo;
}

sub last_active {
  my $this = shift;
  return $this->{'last_active'};
}

sub connected {
  my $this = shift;
  return $this->{'connected'};
}

sub ping_in_air {
  my $this = shift;
  if($this->{'ping_waiting'}) {
    return 1;
  } else {
    return 0;
  }
}

# Returns the parent server of this server.
# (if you keep finding the parent of the parent
# until there isn't one, (this server) and then
# go back one, you'll have the server that a message
# has to be sent through to be routed properly.)
sub parent {
  my $this = shift;
  return $this->{'parent'};
}

# Returns the number of hops to reach the local
# server from the server represented by this
# server object.
sub hops {
  my $this = shift;
  return ($this->parent->hops+1);
}

###############################
# DATA MANIPULATING SUBROUTINES
###############################

# Tells the server that this person is now on it
sub adduser {
  my $this = shift;
  my $user = shift;
  $this->{'users'}->{$user->lcnick()} = $user;
}

sub removeuser {
  my $this = shift;
  my $user = shift;

  # This allows us to remove a user by their nick
  # or their User object.
  my $nick;
  if(ref($user)) {
    $nick = $user->lcnick();
  } else {
    $nick = $user;
  }

  delete($this->{'users'}->{$nick});
}

# Adds a server to the list of ones on this one.
sub addchildserver {
  my $this  = shift;
  my $child = shift;

  $this->{'children'}->{$child->lcname()} = $child;
}

# Removes a server from the list of ones on this one.
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

#####################################################################
# RAW, LOW-LEVEL OR MISC SUBROUTINES
####################################

# Add a command to the hash of commandname->subroutine refs
sub addcommand {
  shift()->{'commands'}->{shift()} = shift();
}

sub senddata {
  my $this = shift;
  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',@_);
}

1;
