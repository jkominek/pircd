#!/usr/bin/perl
# 
# Server.pm
# Created: Tue Sep 15 13:55:23 1998 by jay.kominek@colorado.edu
# Revised: Fri Oct  2 10:47:36 1998 by jay.kominek@colorado.edu
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

  $this->{name}        = shift;
  $this->{description} = shift;
  $this->{distance}    = shift;

  bless($this, $class);
  return $this;
}

############################
# DATA ACCESSING SUBROUTINES
############################

# Get the name of this IRC server
sub name {
  my $this = shift;
  return $this->{name};
}

# Get the name of this IRC server, appropriate for
# keying a hash
sub lcname {
  my $this = shift;
  my $tmp  = $this->{name};
  $tmp     =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $tmp;
}

sub description {
  my $this = shift;
  return $this->{description};
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

# Returns the parent server of this server.
# (if you keep finding the parent of the parent
# until there isn't one, (this server) and then
# go back one, you'll have the server that a message
# has to be sent through to be routed properly.)
sub parent {
  my $this = shift;
  return $this->{parent};
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
  $this->{users}->{$user->lcnick()} = $user;
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

  delete($this->{users}->{$nick});
}

# Adds a server to the list of ones on this one.
sub addchildserver {
  my $this  = shift;
  my $child = shift;

  $this->{children}->{$child->lcname()} = $child;
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
  delete($this->{children}->{$name});
}

1;
