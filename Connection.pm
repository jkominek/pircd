#!/usr/bin/perl
# 
# Connection.pm
# Created: Tue Sep 15 14:26:26 1998 by jay.kominek@colorado.edu
# Revised: Fri Mar  9 12:44:54 2001 by jay.kominek@colorado.edu
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

  $this->{'ssl'} = $this->{'socket'}->isa("IO::Socket::SSL");

  my($port,$iaddr)     = sockaddr_in(getpeername($this->{'socket'}));
  $this->{'host'}      = gethostbyaddr($iaddr,AF_INET) || inet_ntoa($iaddr);
  $this->{'host_ip'}   = inet_ntoa($iaddr);

  bless($this, $class);
  return $this;
}

my $commands={
    PONG=>sub {
	my($this,$dummy,$response)=@_;

	if($this->{doing_nospoof}>0) {
	    if($response eq $this->{doing_nospoof}) {
		$this->{doing_nospoof} = -1;
		if($this->{user}) {
		    delete($this->{doing_nospoof});
		    $this->{ready} = 1;
		}
	    } else {
	      $this->sendreply(
		   "513 :To connect, type /QUOTE PONG $this->{doing_nospoof}");
	    }
	}
    },
    NICK=>sub {
	my($this,$dummy,$str)=@_;

	&donick($this,$dummy,$str);
    },
    USER=>sub {
	my($this,$dummy,$username,$host,$server,$ircname)=@_;

	$this->{user} = "~$username";
	$this->{ircname}  = $ircname;
	if($this->{doing_nospoof}<0) {
	    $this->{ready} = 1;
	}
    },
    SERVER=>sub {
	my($this,$dummy,$servername,$distance,$timea,$timeb,$proto,
	   $description)=@_;

	$this->{servername}  = $servername;
	$this->{proto}       = $proto;
	$this->{distance}    = $distance;
	$this->{description} = $description;
	if($this->{password}) {
	    $this->{ready} = 1;
	}
    },
    PASS=>sub {
	my($this,$dummy,$password)=@_;
	
	# We don't actually do anything with the password yet
	$this->{password} = $password;

	if($this->{servername}) {
	    $this->{ready} = 1;
	}
    },
    QUIT=>sub {
        my($this,$dummy,$excuse)=@_;
	$this->quit($excuse);
    },
};

# Given a line of user input, process it and take appropriate action
sub handle {
    my($this, $line)=@_;

    Utils::do_handle($this,$line,$commands);
}

# excuses should always be discarded for Connections.
# people who don't completely connect to the server/network should
# not be allowed to transmit any data via it.
sub quit {
  my($this,$msg)=@_;
  &main::finishclient($this->{'socket'});
}

sub last_active {
  my $this = shift;
  return $this->{last_active};
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
    my $banned = 0;
    my $reason;
    foreach my $ref (@{$this->server->{'klines'}}) {
      my $mask = $ref->[2];
      if($this->{'host'} =~ /$mask/) {
	my @kline = @{$ref};
	if($this->{'user'} =~ /$kline[1]/) {
	  if($kline[0]) {
	    $banned = 0;
	  } else {
	    $banned = 1;
	    $reason = $kline[3];
	  }
	}
      }
    }

    if($banned) {
      $this->sendnumeric($this->server,465,"*** $reason");
      $this->senddata("ERROR :Closing Link: ".$this->{'nick'}."[".$this->{'host'}."] by ".$this->server->name." (K-lined)\r\n");
      $this->{'socket'}->send($this->{'outbuffer'}->{$this->{'socket'}},0);
      return undef;
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

# send a numeric response to the peer
sub sendnumeric {
  my $this      = shift;
  my $from      = shift;
  my $numeric   = shift;
  my $msg       = pop;
  my @arguments = @_;
  my $destnick;
  my $fromstr;

  if($from->isa("User")) {
    $fromstr = $from->nick."!".$from->username."\@".$from->host;
  } elsif($from->isa("Server")) {
    $fromstr = $from->name;
  }

  if(length($numeric)<3) {
    $numeric = ("0" x (3 - length($numeric))).$numeric;
  }

  $destnick = '*' unless defined($destnick=$this->{nick});

  $this->senddata(":".join(' ',$fromstr,$numeric,$destnick,@arguments,defined($msg)?":".$msg:( ))."\r\n");
}

# send one or more reply line to a peer
# this is a nicer substitute for sendnumeric and wrapper for senddata.
# each argument is a string, which is sent as a reply line. if the string
# starts with a colon, that is used as the "from", otherwise the server name
# is used. the rest if the string is a code, then a space, then data.
# if the code contains a ">", then whatever follows the > is used as the
# destination nick. otherwise, the destination nick will automatically be set
# based on the destination object.
# if the first passed argument after the destination user is also a user
# object, then the default source will be the nick!user@host of that user
# object (instead of the server name).
# sendreply will insert the destination nick between the code and the data.
# if part of the data is a multi-word argument, the colon must be explicitly
# included; sendreply won't magically add one in.
sub sendreply {
  my($this,$src,@replies)=@_;
  my($reply,$fromstr,$repcode,$data,$destnick);

  ($src,@replies)=(undef,$src,@replies) if(!ref($src) || !isa($src,"User"));
  
  defined($destnick=$this->{nick}) or $destnick='*';
  
  foreach $reply (@replies) {
    if($reply=~/^:/) {
      ($fromstr,$reply)=$reply=~/(\S+)\s+(.*)/;
    } elsif(defined($src)) {
      $fromstr=":$$src{nick}!$$src{user}\@$$src{host}";
    } else {
      $fromstr=":${$$this{'server'}}{'name'}";
    }
    ($repcode,$data)=$reply=~/(\S*)(.*)/;
    if($repcode=~/>/) {
      ($repcode,$destnick)=$repcode=~/([^>]+)>(.*)/;
    }
    $this->senddata("$fromstr $repcode $destnick$data\r\n");
  }
}

# queue some data to be sent to the peer on this connection
sub senddata {
    my $this=shift;

  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',@_);
}

# handle a NICK request
sub donick {
  my($this,$dummy,$newnick)=@_;
  my $timeleft=$this->{'next_nickchange'}-time();
  my $channel;

  if($newnick eq $this->{'nick'}) {
    return; # silently discard stupid nick changes
  }
  if ($timeleft>0) {
    $this->sendnumeric($this->server,438,$newnick,
		       "Nick change too fast. Please wait $timeleft more seconds.");
  } elsif (!Utils::validnick($newnick)) {
    $this->sendnumeric($this->server,432,$newnick,"Erroneous nickname.");
  } elsif (defined(Utils::lookup($newnick)) && (Utils::irclc($newnick) ne Utils::irclc($this->{'nick'}))) {
    $this->sendnumeric($this->server,433,$newnick,
		       "Nickname already in use");
  } elsif (!defined($this->{'nick'})) {
    $this->{'nick'}=$newnick;
    $this->{doing_nospoof} = int(rand()*4294967296);
    $this->senddata("PING :$this->{doing_nospoof}\r\n");
  } else {
    $this->{'oldnick'} = $this->{'nick'};
    $this->{'nick'}    = $newnick;
    $this->senddata(":$$this{oldnick}!$$this{user}\@$$this{host} NICK :".$this->{'nick'}."\r\n");
    if ($this->isa('User')) {	# not just an unpromoted connection
      unshift @Utils::nickhistory, { 'nick' => $this->{'oldnick'},
				     'newnick' => $this->{'nick'},
				     'username' => $this->username,
				     'host' => $this->host,
				     'ircname' => $this->ircname,
				     'server' => $this->server->name,
				     'time' => time };
      delete(Utils::users()->{$this->{'oldnick'}});
      Utils::users()->{$this->{'nick'}}=$this;
      $this->server->removeuser($this->{'oldnick'});
      $this->server->adduser($this);

      # So that no given user will receive the nick change twice -
      # we build this hash and then send the message to those users.
      my %userlist;
      foreach my $channel (keys(%{$this->{'channels'}})) {
	my %storage = %{$this->{channels}->{$channel}->nickchange($this)};
	foreach (keys %storage) {
	  $userlist{$_} = $storage{$_} if $storage{$_} != $this;
	}
      }
      foreach my $user (keys %userlist) {
	next unless $userlist{$user}->islocal();
	$userlist{$user}->senddata(":$$this{oldnick}!$$this{user}\@$$this{host} NICK :$$this{nick}\r\n");
      }
      # FIXME should propogate to other servers
    }
    $this->{'next_nickchange'}=time()+30;
  }
}

1;
