#!/usr/bin/perl
# 
# Connection.pm
# Created: Tue Sep 15 14:26:26 1998 by jay.kominek@colorado.edu
# Revised: Sat Feb  6 10:07:43 1999 by jay.kominek@colorado.edu
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
# Connection object for The Perl Internet Relay Chat Daemon
#####################################################################

package Connection;
use Utils;
use Socket;
use strict;
use UNIVERSAL qw(isa);

# Class constructor
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{'socket'}      = shift;
  $this->{outbuffer}   = shift;
  $this->{server}      = shift;
  $this->{connected} = $this->{last_active} = time();

  my($port,$iaddr)     = sockaddr_in(getpeername($this->{'socket'}));
  $this->{host}        = gethostbyaddr($iaddr,AF_INET) || inet_ntoa($iaddr);
  $this->{host_ip}     = inet_ntoa($iaddr);

  bless($this, $class);
  return $this;
}

# Get our socket
sub socket {
  my $this = shift;
  return $this->{'socket'};
}

# Handle some data
sub handle {
  my $this = shift;
  my $line = shift;
  my $time = time();

  $line =~ s/\s+$//;

  $this->{last_active} = $time;

 SWITCH: {
    if($line =~ /^PONG/i) {
      my($command,$response) = split(/\s+/,$line);
      if($this->{doing_nospoof}>0) {
	$response =~ s/^://;
	if($response eq $this->{doing_nospoof}) {
	  $this->{doing_nospoof} = -1;
	  if($this->{user}) {
	    delete($this->{doing_nospoof});
	    $this->{ready} = 1;
	  }
	} else {
	  $this->senddata(":".$this->server->name." 513 ");
	}
      }
      last SWITCH;
    }
    if($line =~ /^NICK/i) {
      my($command,$str) = split(/\s+/,$line);
      $str =~ s/^://;
      if(defined($this->{nick})) {
	$this->senddata(":$this->{nick} NICK :$str\r\n");
	$this->{nick} = $str;
	last SWITCH;
      }
      if(defined(Utils::lookup($str))) {
	$this->senddata(":".$this->{server}->name." 433 * $str :Nickname is already in use.\r\n");
	last SWITCH;
      }
      $this->{nick} = $str;
      $this->{doing_nospoof} = int(rand()*4294967296);
      $this->senddata("PING :$this->{doing_nospoof}\r\n");
      last SWITCH;
    }
    if($line =~ /^USER/i) {
      my($command,$username,$host,$server,$ircname) = split(/\s+/,$line,5);
      $ircname =~ s/^://;
      $this->{user} = "~$username";
      $this->{ircname}  = $ircname;
      if($this->{doing_nospoof}<0) {
	$this->{ready} = 1;
      }
      last SWITCH;
    }
    if($line =~ /^SERVER/i) {
      my($command,$servername,$distance,$timea,$timeb,$proto,$description) =
	split(/\s+/,$line);
      $description =~ s/^://;
      $this->{servername}  = $servername;
      $this->{proto}       = $proto;
      $this->{distance}    = $distance;
      $this->{description} = $description;
      if($this->{password}) {
	$this->{ready} = 1;
      }
      last SWITCH;
    }
    if($line =~ /^PASS/i) {
      my($command,$password) = split(/\s+/,$line);
      $password =~ s/^://;
      # We don't actually do anything with the password yet
      $this->{password} = $password;
      if($this->{servername}) {
	$this->{ready} = 1;
      }
      last SWITCH;
    }
  }
}

sub quit {
  my $this = shift;
  my $msg  = shift;
}

sub last_active {
  my $this = shift;
  return $this->{last_active};
}

sub ping {

}

sub ping_in_air {
  return 0;
}

sub readytofinalize {
  my $this = shift;
  if($this->{ready}) {
    return 1;
  } else {
    return 0;
  }
}

sub finalize {
  my $this = shift;
  if($this->{nick}) {
    # Since we have a nick stored, that means that we're destined to
    # become a user.
    my $user = User->new($this);

    # We used to have to tell User objects that they were local, but
    # now they figure it out for themselves based on the fact that they
    # have sockets. Pretty clever of them, eh?

    return $user;
  } elsif($this->{servername}) {
    # We're trying to finalize as an IRC server
    my $server = Server->new($this);

    return $server;
  }
  return undef;
}

sub senddata {
  my $this = shift;
  my $data = shift;

  $this->{outbuffer}->{$this->{'socket'}} .= join('',$data);
}

1;
