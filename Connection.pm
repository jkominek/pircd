#!/usr/bin/perl
# 
# Connection.pm
# Created: Tue Sep 15 14:26:26 1998 by jay.kominek@colorado.edu
# Revised: Thu Jul  1 14:21:56 1999 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
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

  $this->{'socket'}    = shift;
  $this->{'outbuffer'} = shift;
  $this->{'server'}    = shift;
  $this->{'connected'} = $this->{last_active} = time();

  print $this->{'socket'};
  print "\n";
  my($port,$iaddr)     = sockaddr_in(getpeername($this->{'socket'}));
  $this->{'host'}      = gethostbyaddr($iaddr,AF_INET) || inet_ntoa($iaddr);
  $this->{'host_ip'}   = inet_ntoa($iaddr);

  bless($this, $class);
  return $this;
}

# Get our socket
sub socket {
  my $this = shift;
  return $this->{'socket'};
}

sub setinitiated {
  my $this = shift;
  $this->{'initiated'} = 1;
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
	  $this->senddata(":".$this->server->name." 513 \r\n");
	}
      }
      last SWITCH;
    }
    if($line =~ /^NICK/i) {
      my($command,$str) = split(/\s+/,$line);
      $str =~ s/^://;
      if(defined($this->{nick})) {
	$this->senddata(":".$this->{nick}." NICK :$str\r\n");
	$this->{nick} = $str;
	last SWITCH;
      }
      if(defined(Utils::lookup($str))) {
	$this->sendnumeric($this->server,433,$str,"Nickname is already in use.");
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
	split(/\s+/,$line,7);
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
  &main::finishclient($this->{'socket'});
}

sub last_active {
  my $this = shift;
  return $this->{last_active};
}

sub ping {

}

sub ping_in_air {
  return 1;
}

sub readytofinalize {
  my $this = shift;
  if($this->{ready}) {
    return 1;
  } else {
    return 0;
  }
}

sub server {
  my $this = shift;
  return $this->{'server'};
}

sub finalize {
  my $this = shift;
  if($this->{nick}) {
    # Since we have a nick stored, that means that we're destined to
    # become a user.
    foreach my $mask (keys %{$this->server->{'klines'}}) {
      if($this->{'host'} =~ /$mask/) {
	my @kline = @{$this->server->{'klines'}->{$mask}};
	if($this->{'user'} =~ /$kline[0]/) {
	  $this->sendnumeric($this->server,465,"*** $kline[2]");
	  $this->senddata("ERROR :Closing Link: ".$this->{'nick'}."[".$this->{'host'}."] by ".$this->server->name." (K-lined)\r\n");
	  $this->{'socket'}->send($this->{'outbuffer'}->{$this->{'socket'}},0);
	  return undef;
	}
      }
    }

    # Okay, we're safe, keep going.
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

sub sendnumeric {
  my $this      = shift;
  my $from      = shift;
  my $numeric   = shift;
  my $msg       = pop;
  my @arguments = @_;

  my $fromstr;
  if($from->isa("User")) {
    $fromstr = $from->nick."!".$from->username."\@".$from->host;
  } elsif($from->isa("Server")) {
    $fromstr = $from->name;
  }

  if(length($numeric)<3) {
    $numeric = ("0" x (3 - length($numeric))).$numeric;
  }

  if($#arguments>0) {
    push(@arguments,'');
  }

  if(defined($msg)) {
    $msg=":".$msg;
    $this->senddata(":".join(' ',$fromstr,$numeric,'*',@arguments,$msg)."\r\n");
  } else {
    $this->senddata(":".join(' ',$fromstr,$numeric,'*',@arguments)."\r\n");
  }
}

sub senddata {
  my $this = shift;
  my $data = shift;

  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',$data);
}

1;
