#!/usr/bin/perl
# 
# Connection.pm
# Created: Tue Sep 15 14:26:26 1998 by jay.kominek@colorado.edu
# Revised: Sat Nov 20 03:53:47 1999 by tek@wiw.org
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

my $commands={
    PONG=>sub {
	my($this,$dummy,$response)=(shift,shift,shift);

	if($this->{doing_nospoof}>0) {
	    if($response eq $this->{doing_nospoof}) {
		$this->{doing_nospoof} = -1;
		if($this->{user}) {
		    delete($this->{doing_nospoof});
		    $this->{ready} = 1;
		}
	    } else {
		$this->senddata(":".$this->server->name.
				" 513 To connect, type /QUOTE PONG $this->{doing_nospoof}\r\n");
	    }
	}
    },
    NICK=>sub {
	my($this,$dummy,$str)=(shift,shift,shift);

	&donick($this,$dummy,$str);
    },
    USER=>sub {
	my($this,$dummy,$username,$host,$server,$ircname)=
	    (shift,shift,shift,shift,shift,shift);

	$this->{user} = "~$username";
	$this->{ircname}  = $ircname;
	if($this->{doing_nospoof}<0) {
	    $this->{ready} = 1;
	}
    },
    SERVER=>sub {
	my($this,$dummy,$command,$servername,$distance,$timea,$timeb,$proto,
	   $description)=
	       (shift,shift,shift,shift,shift,shift,shift,shift,shift);

	$this->{servername}  = $servername;
	$this->{proto}       = $proto;
	$this->{distance}    = $distance;
	$this->{description} = $description;
	if($this->{password}) {
	    $this->{ready} = 1;
	}
    },
    PASS=>sub {
	my($this,$dummy,$command,$password)=(shift,shift,shift,shift);
	
	# We don't actually do anything with the password yet
	$this->{password} = $password;

	if($this->{servername}) {
	    $this->{ready} = 1;
	}
    },
};

# Given a line of user input, process it and take appropriate action
sub handle {
    my($this, $line)=(shift,shift);

    Utils::do_handle($this,$line,$commands);
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

  if($#arguments>0) {
    push(@arguments,'');
  }

  defined($destnick=$this->{nick}) or $destnick='*';

  if(defined($msg)) {
    $this->senddata(":$fromstr $numeric $destnick ".join(' ',@arguments)." :$msg\r\n");
  } else {
    $this->senddata(":".join(' ',$fromstr,$numeric,'*',@arguments)."\r\n");
  }
}

# queue some data to be sent to the peer on this connection
sub senddata {
    my $this=shift;

  $this->{'outbuffer'}->{$this->{'socket'}} .= join('',@_);
}

# handle a NICK request
sub donick {
  my($this,$dummy,$newnick)=(shift,shift,shift);
  my $timeleft=$this->{'next_nickchange'}-time();
  my $channel;
  
  if ($timeleft>0) {
    $this->sendnumeric($this->server,438,$newnick,
		       "Nick change too fast. Please wait $timeleft more seconds.");
  } elsif (!Utils::validnick($newnick)) {
    $this->sendnumeric($this->server,432,$newnick,"Erroneous nickname.");
  } elsif (defined(Utils::lookup($newnick))) {
    $this->sendnumeric($this->server,433,$newnick,
		       "Nickname already in use");
  } elsif (!defined($this->{'nick'})) {
    $this->{'nick'}=$newnick;
    $this->{doing_nospoof} = int(rand()*4294967296);
    $this->senddata("PING :$this->{doing_nospoof}\r\n");
  } else {
    $this->{'oldnick'} = $this->{'nick'};
    $this->{'nick'}    = $newnick;
    $this->senddata(":".$this->{'oldnick'}." NICK :".$this->{'nick'}."\r\n");
    if ($this->isa('User')) {	# not just an unpromoted connection
      delete(Utils::users()->{$this->{'oldnick'}});
      Utils::users()->{$this->{'nick'}}=$this;
      $this->server->removeuser($this->{'oldnick'});
      $this->server->adduser($this);
      
      # So that no given user will receive the nick change twice -
      # we build this hash and then send the message to those users.
      my(%userlist);
      foreach my $channel (keys(%{$this->{'channels'}})) {
	my %storage = %{$this->{channels}->{$channel}->nickchange($this)};
	foreach (keys %storage) {
	  $userlist{$_} = $storage{$_};
	}
      }
      foreach my $user (keys %userlist) {
	next unless $userlist{$user}->islocal();
	$userlist{$user}->senddata(":".$this->{'oldnick'}." NICK :".
				   $this->{'nick'}."\r\n");
      }
      # FIXME should propogate to other servers
    }
    $this->{'next_nickchange'}=time()+30;
  }
}

1;
