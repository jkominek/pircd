#!/usr/bin/perl
# 
# Server.pm
# Created: Tue Sep 15 13:55:23 1998 by jay.kominek@colorado.edu
# Revised: Sun Feb  7 22:52:53 1999 by jay.kominek@colorado.edu
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

  $this->{name}        = $connection->{servername};
  $this->{description} = $connection->{description};
  $this->{distance}    = $connection->{distance};
  $this->{proto}       = $connection->{proto};
  $this->{server}      = $connection->{server};
  $this->{last_active} = time();

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
  my $this = shift;

  $this->addcommand('PING',    \&handle_ping);

  # Channel membership
  $this->addcommand('JOIN',    \&handle_join);
  $this->addcommand('PART',    \&handle_part);
  $this->addcommand('INVITE',  \&handle_invite);
  $this->addcommand('KICK',    \&handle_kick);
  # Channel status
  $this->addcommand('TOPIC',   \&handle_topic);
  $this->addcommand('MODE',    \&handle_mode);

  # User presence
  $this->addcommand('NICK',    \&handle_nick);
  $this->addcommand('KILL',    \&handle_kill);
  $this->addcommand('QUIT',    \&handle_quit);
  # User status
  $this->addcommand('AWAY',    \&handle_away);

  # Server presence
  $this->addcommand('SERVER',  \&handle_server);
  $this->addcommand('SQUIT',   \&handle_squit);

  # Communication
  $this->addcommand('PRIVMSG', \&handle_privmsg);
  $this->addcommand('NOTICE',  \&handle_notice);

  # Burst commands
  $this->addcommand('BU',      \&handle_burstuser);
  $this->addcommand('BC',      \&handle_burstchannel);

  # lookup and send password
  $this->senddata("PASS :password\r\n");

  ###################################################################
  # Start dumping the state of the entire network at the new server #
  my $server = $this->server;

  # Dump the server tree

  # This server has to be sent in the special fashion. All other
  # servers are spewed using the recursive method 'spewchildren'
  $this->senddata(join(' ',
		       $server->name,
		       1,
		       0,    # timestamp a
		       time, # timestamp b
		       "Px1",
		       ":".$server->description)."\r\n");
  my $childserver;
  foreach $childserver ($server->children()) {
    $this->spewchildren($childserver);
  }

  # Dump the users
  # For big networks, it would be a very good idea to generate all the
  # data that needs to be sent at one time, use Compress::Zlib on that
  # data and then spew it binaryily.

  # As it is, we will merely use the special burst user command
  my $user;
  foreach $user (values(%{Utils::users()})) {
    $this->senddata(join(' ',
			 ":".$user->server->name,
			 "BU", # Burst User. Only place of generation.
			 $user->nick,
			 $user->username,
			 $user->host,
			 $user->genmodestr,
			 $user->ircname)."\r\n");
  }

  # Burst channel information
  my $channel;
  foreach $channel (values(%{Utils::channels()})) {
    # :server.name BC #channel creationtime modestr modeargs
    #  nick @opnick +@opvoicenick +voicenick nick +voicenick2 @opnick2
    $this->senddata(join(' ',
			 ":".$this->parent->name,
			 "BC", # Burst Channel. Only place of generation.
			 $channel->name,
			 $channel->creation,
			 map { $_->nick } $channel->users()
			)."\r\n"
		   );
  }
}

sub spewchildren {
  my $this = shift;
  my $server = shift;
  $this->senddata(join(' ',
		       ":".$this->server->name,
		       "SERVER",
		       $server->name,
		       $server->distance+1,
		       0,    # timestamp a
		       time, # timestamp b
		       "Px1",
		       ":".$server->description)."\r\n");
  foreach($server->children()) {
    $this->spewchildren($_);
  }
}

sub handle {
  my $this = shift;
  my $rawline = shift;

  my $line;
  foreach $line (split(/\x00/,$rawline)) {
    $line =~ s/\s+$//;

    $this->{last_active} = time();
    delete($this->{ping_waiting});

    $line =~ /^\S+ (\S+) .+$/;
    my $command = $1;

    # Parsing stuff from a server is a bit more complicated than parsing
    # for a user.
    if(ref($this->{commands}->{$command})) {
      &{$this->{commands}->{$command}}($this,$line);
    } else {
      if($line =~ /[\w\d\s]/) {
	print "Received unknown command string \"$line\" from ".$this->name."\n";
      }
    }
  }
}

sub handle_ping {
  my $this = shift;
  print "handle_ping called\n";
}

sub handle_nick {
  my $this = shift;

}

sub handle_kill {
  my $this = shift;

}

sub handle_quit {
  my $this = shift;

}

sub handle_away {
  my $this = shift;

}

sub squit {
  my $this = shift;
  
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
  return $this->{'server'};
}

sub server {
  my $this = shift;
  return $this->{'server'};
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
  my $this    = shift;
  my $command = shift;
  my $subref  = shift;
  $this->{'commands'}->{$command} = $subref;
}

sub senddata {
  my $this = shift;
  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',@_);
}

1;
