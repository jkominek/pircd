#!/usr/bin/perl
# 
# Channel.pm
# Created: Tue Sep 15 13:49:42 1998 by jay.kominek@colorado.edu
# Revised: Wed Jun  5 12:57:42 2002 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# Channel object for The Perl Internet Relay Chat Daemon
#####################################################################

package Channel;
use Utils;
use User;
use Server;
use strict;
use UNIVERSAL qw(isa);

use Tie::IRCUniqueHash;

#####################################################################
# CLASS CONSTRUCTOR
###################

# Expects to get the proper name of the channel as the first
# argument.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{'name'} = shift;
  my %tmp = ();
  $this->{'bans'} = \%tmp;
  $this->{'creation'} = shift || time();

  tie my %usertmp, 'Tie::IRCUniqueHash';
  $this->{'users'} = \%usertmp;
  tie my %opstmp,  'Tie::IRCUniqueHash';
  $this->{'ops'}   = \%opstmp;
  tie my %voicetmp,'Tie::IRCUniqueHash';
  $this->{'voice'} = \%voicetmp;
  tie my %jointimetmp,'Tie::IRCUniqueHash';
  $this->{'jointime'} = \%jointimetmp;

  bless($this, $class);
  return $this;
}

#####################################################################
# DATA ACCESSING SUBROUTINES
############################

sub users {
  my $this = shift;

  return values(%{$this->{'users'}});
}

# Sends the user /names output
sub names {
  my $this = shift;
  my $user = shift;

  my @lists;
  my($index,$count) = (0,0);
  foreach(sort
	  { $this->{'jointime'}->{$b} <=> $this->{'jointime'}->{$a} }
	  keys %{$this->{'users'}}) {
    if($count>60) { $index++; $count = 0; }
    my $nick = $this->{'users'}->{$_}->nick;
    if($this->isop($this->{'users'}->{$_})) {
      $nick = "@".$nick;
    } elsif($this->hasvoice($this->{'users'}->{$_})) {
      $nick = "+".$nick;
    }
    push(@{$lists[$index]},$nick);
  }
  foreach(0..$index) {
    $user->senddata(":".$user->server->{name}." 353 ".$user->nick." = ".$this->{name}." :".join(' ',@{$lists[$_]})."\r\n");
  }
}

sub isvalidchannelmode {
  my $mode = shift;
  if($mode =~ /\W/) { return 0; }
  if(grep {/$mode/} ("b","i","k",
		     "l","m","n",
		     "o","s","t",
		     "v")) {
    return 1;
  } else {
    return 0;
  }
}

# These functions manipulate binary modes on the channel.
# ismode returns 0 or 1 depending on whether or not the requested
#  mode is set on the channel now.
sub ismode {
  my $this = shift;
  my $mode = shift;
  if($this->{modes}->{$mode}==1) {
    return 1;
  } else {
    return 0;
  }
}

# do the dirty work for setmode and unsetmode
sub frobmode {
  my($this,$user,$mode,$val)=@_;

  if(!isvalidchannelmode($mode)) {
    $user->senddata(":".$user->server->{name}." 501 ".$user->nick." :Unknown mode flag \'$mode\'\r\n");
    return 0;
  }

  if($this->{'modes'}->{$mode}!=$val) {
    $this->{'modes'}->{$mode}=$val;
    return 1;
  } else {
    return 0;
  }
}

# setmode attempts to set the given mode to true. If the mode
#  is not already set, then it sets it. returns 1 if a mode
#  change was effected, 0 if the mode was already set.
sub setmode {
  frobmode(@_,1);
}

# unsetmode does the opposite of setmode.
sub unsetmode {
  frobmode(@_,0);
}

# These functions manipulate or view the ban list for $this channel
#  bans are stored as a hash, keyed on the mask. The value for that
#  hash{key} is a an array, the first item of which contains the name
#  of the person who set the ban, and the second item containing the
#  time the ban was set.
# XXX since when can a hash value be an array?
# setban takes a mask, and if it is not already present, adds it to
#  the list of bans on the channel.
sub setban {
  my $this = shift;
  my $user = shift;
  my $mask = shift;

  if(!defined($this->{'bans'}->{$mask})) {
    $this->{'bans'}->{$mask} = [$user->server->name,time()];
    return $mask;
  } else {
    return 0;
  }
}

# Removes a ban mask from the current 
sub unsetban {
  my $this = shift;
  my $user = shift;
  my $mask = shift;

  if(defined($this->{bans}->{$mask})) {
    delete($this->{bans}->{$mask});
    return $mask;
  } else {
    return 0;
  }
}

# Takes a User object and returns true if that user
# is an op on this channel.
sub isop {
  my $this = shift;
  my $user = shift;
  if(defined($this->{ops}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}

sub setop {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(!defined($this->{ops}->{$ret->nick()})) {
    $this->{ops}->{$ret->nick()} = $user;
    return $ret->nick;
  } else {
    return 0;
  }
}

sub unsetop {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(defined($this->{ops}->{$ret->nick()})) {
    delete($this->{ops}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

# Takes a User object and tells you if it has a voice on
# this channel.
sub hasvoice {
  my $this = shift;
  my $user = shift;
  if(defined($this->{voice}->{$user->nick()})) {
    return 1;
  } else {
    return 0;
  }
}

sub setvoice {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(!defined($this->{'voice'}->{$ret->nick()})) {
    $this->{voice}->{$ret->nick()} = $user;
    return $ret->nick;
  } else {
    return 0;
  }
}

sub unsetvoice {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $ret    = Utils::lookupuser($target,1);
  if(!(ref($ret) && isa($ret,"User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return 0;
  }
  if(!defined($this->{'users'}->{$ret->nick()})) {
    $user->sendnumeric($user->server,441,$target,$this->{name},
		       "They aren't on the channel");
    return 0;
  }
  if(defined($this->{voice}->{$ret->nick()})) {
    delete($this->{voice}->{$ret->nick()});
    return $ret->nick;
  } else {
    return 0;
  }
}

#####################################################################
# DATA MANIPULATING SUBROUTINES
###############################

# handle a MODE command from a user - can be mode check or mode change
sub mode {
  my($this,$user,$modestr,@arguments)=@_;
  my @modebytes = split(//,$modestr);
  my(@accomplishedset,@accomplishedunset,@accomplishedargs);
  my $state = 1;
  my $arg;

  # if it's a mode check, send the nf0z
  if(!defined($modestr)) {
    my(@modes,@args);
    foreach(keys(%{$this->{'modes'}})) {
      next if(!$this->{'modes'}->{$_}); # don't show unset modes

      if($_ eq "k") {
	if($user->onchan($this)) {
	  push(@args,  $this->{'key'});
	}
      } elsif($_ eq "l") {
	push(@args,  $this->{'limit'});
      }
      
      push(@modes, $_);
    }
    $user->sendnumeric($user->server,324,($this->{name},"+".join('',@modes),@args),undef);
    $user->sendnumeric($user->server,329,($this->{name},$this->{'creation'}),undef);
    return;
  } elsif($modestr eq 'b' or ($modestr eq '+b' and $#arguments == -1)) {
    foreach(keys(%{$this->{'bans'}})) {
      my @bandata = @{$this->{'bans'}->{$_}};
      $user->sendnumeric($user->server,367,($this->{name},$_,@bandata),undef);
    }
    $user->sendnumeric($user->server,368,($this->{name}),"End of Channel Ban List");
    return;
  }

  if(!$this->isop($user) && !$user->ismode('g')) {
    $user->sendreply("482 $$this{name} :You're not a channel operator.");
    return;
  }

  foreach(@modebytes) {
    if($_ eq "+") {
      $state = 1;
    } elsif($_ eq "-") {
      $state = 0;
    } else {
      if($_=~/[bovlk]/ &&!($_ eq 'l' && !$state)) {
	$arg=shift(@arguments);
	next if(!defined($arg));
      } else {
	push(@accomplishedset,$_) if($state && $this->setmode($user,$_));
	push(@accomplishedunset,$_) if(!$state && $this->unsetmode($user,$_));
	next;
      }
      
      if($_ eq "b") {
	$arg=$this->setban($user,$arg) if($state);
	$arg=$this->unsetban($user,$arg) if(!$state);
      } elsif($_ eq "o") {
	$arg=$this->setop($user,$arg) if($state);
	$arg=$this->unsetop($user,$arg) if(!$state);
      } elsif($_ eq "v") {
	$arg=$this->setvoice($user,$arg) if($state);
	$arg=$this->unsetvoice($user,$arg) if(!$state);
      } elsif($_ eq "l") {
	if($arg =~ /\D/) {
	  $user->sendreply("467 $$this{name} :Channel limit value \"$arg\" is nonnumeric");
	  next;
	} else {
	  $this->setmode($user,'l');
	  $this->{'limit'} = $arg;
	}
      } elsif($_ eq "k") {
	if($state) {
	  if($this->ismode('k')) {
	    $user->sendreply("467 $$this{name} :Channel key already set");
	    undef $arg;
	  } else {
	    $this->setmode($user,'k');
	    $this->{'key'} = $arg;
	  }
	} else {
	  if($arg ne $this->{key} || !($this->unsetmode($user, "k"))) {
	    undef $arg;
	  }
	}
      }
      if($arg) {
	push(@accomplishedset,$_) if($state);
	push(@accomplishedunset,$_) if(!$state);
	push(@accomplishedargs,$arg);
      }
    }
  }

  if($#accomplishedset>=0 || $#accomplishedunset>=0) {
    my $changestr;
    if($#accomplishedset>=0) {
      $changestr = "+".join('',@accomplishedset);
    }
    if($#accomplishedunset>=0) {
      $changestr .= "-".join('',@accomplishedunset);
    }
    if($#accomplishedargs>=0) {
      $changestr .= join(' ','',@accomplishedargs);
    }
    User::multisend(":$$user{nick}!$$user{user}\@$$user{host}".
		    " MODE>$$this{name} $changestr",
		    values(%{$this->{'users'}}));
    foreach my $server ($user->server->children) {
      $server->mode($user,$this,$changestr);
    }
  }
}

sub topic {
  my $this = shift;
  my $user = shift;
  my $topic = shift;
  if(defined($user) && defined($topic)) {
    unless($this->ismode('t') && (!($this->isop($user) ||
				    $user->ismode('g')))) {
      $this->{'topic'}        = $topic;
      $this->{topicsetter}  = $user->nick;
      $this->{topicsettime} = time();
      foreach(keys(%{$this->{'users'}})) {
	if($this->{'users'}->{$_}->islocal()) {
	  $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." TOPIC ".$this->{name}." :$topic\r\n");
	}
      }
    } else {
      $user->senddata(":".$user->server->{name}." 482 ".$user->nick." ".$this->{name}." :You're not a channel operator\r\n");
    }
  } else {
    if($this->{'topic'}) {
      return ($this->{'topic'},$this->{topicsetter},$this->{topicsettime});
    } else {
      return undef;
    }
  }
}

# Called when a local user wants to try and join the channel
# (This one does checking and stuff)
sub join {
  my $this = shift;
  my $user = shift;
  my @keys = @_;
  my $hasinvitation = 0;

  my($fu,$bar) = ($user->nick,$this->{name});

  if(defined($this->{hasinvitation}->{$user})) {
    $hasinvitation = 1;
    delete($this->{hasinvitation}->{$user});
  }

  # Test to see if the user needs an invitation [and doesn't have
  # it/isn't godlike]
  if($this->ismode('i') && (!$hasinvitation) && !$user->ismode('g')) {
    Connection::sendreply($user, "473 $this->{name} :Cannot join channel (+i)");
    return;
  }

  # If the user is invited, [or godlike] then they can bypass the key,
  # limit, and bans
  unless($hasinvitation || $user->ismode('g')) {
    # Test to see if the user knows the channel key
    if($this->ismode('k')) {
      unless(grep {$_ eq $this->{key}} @keys) {
	Connection::sendreply($user, "475 $this->{name} :Cannot join channel (+k)");
	return;
      }
    }
  
    # Test to see if the channel is over the current population limit.
    if(($this->ismode('l')) &&
       ((1+scalar keys(%{$this->{'users'}}))>$this->{limit})) {
      Connection::sendreply($user, "471 $this->{name} :Cannot join channel (+l)");
      return;
    }

    # Test for bans, here
    my @banmasks = keys(%{$this->{bans}});
    my(@banregexps, $mask);
    $mask = $user->nick."!".$user->username."\@".$user->host;
    foreach(@banmasks) {
      my $regexp = $_;
      $regexp =~ s/\./\\\./g;
      $regexp =~ s/\?/\./g;
      $regexp =~ s/\*/\.\*/g;
      $regexp = "^".$regexp."\$";
      push(@banregexps,$regexp);
    }
    if(grep {$mask =~ /$_/} @banregexps) {
      $user->sendnumeric($user->server,474,$this->{name},"Cannot join channel (+b)");
      return;
    }
  }

  #do the actual join
  $this->force_join($user,$user->server);

  $user->sendnumeric($user->server,332,$this->{'name'},$this->{'topic'}) if defined $this->{'topic'};
  $user->sendnumeric($user->server,333,$this->{'name'},$this->{'topicsetter'},$this->{'topicsettime'},undef) if defined $this->{'topicsetter'};
  if(1==scalar keys(%{$this->{'users'}})) {
    $this->setop($user,$user->nick());
  }
  if(defined($this->{'topic'})) {
    $this->topic($user);
  }
  $this->names($user);
  $user->sendnumeric($user->server,366,$this->{name},"End of /NAMES list.");
}

# Called by (servers) to forcibly add a user, does no checking.
sub force_join {
  my $this = shift;
  my $user = shift;
  my $server = shift; # the server that is telling us about the
                      # user connecting has to tell us what it is
                      # so that when we propogate the join on,
                      # we don't tell it.

  Utils::channels()->{$this->{name}} = $this;
  $this->{'users'}->{$user->nick()} = $user;
  $this->{'jointime'}->{$user->nick()} = time;
  $user->{'channels'}->{$this->{name}} = $this;
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host} JOIN>:$$this{name}",
		  values(%{$this->{'users'}}));
  foreach my $iserver ($Utils::thisserver->children) {
    if($iserver ne $server) {
      $iserver->join($user,$this);
    }
  }
}

# This one is called when a user leaves
sub part {
  my($this,$user,$server)=@_;
  my @foo;

  foreach my $iserver ($Utils::thisserver->children) {
    if($iserver ne $server) {
      $iserver->part($user,$this);
    }
  }

  @foo=$this->notifyofquit($user);
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host} PART>$$this{name}",
		  @foo,$user);
}

sub kick {
  my($this,$user,$target,$excuse)=@_;
  my @foo;
  my $sap = Utils::lookupuser($target,1);

  if(!$this->isop($user) && !$user->ismode('g')) {
    Connection::sendreply($user,
			  "482>$$this{name} You are not a channel operator");
    return;
  }

  if((!defined($sap)) || (!$sap->isa("User"))) {
    $user->sendnumeric($user->server,401,$target,"No such nick");
    return;
  }

  if(!$sap->onchan($this)) {
    $user->sendnumeric($user->server,441,$target,"Nick $target is not on $$this{name}");
    return;
  }

  if($sap->ismode('k') && !$user->ismode('g')) {
    if($sap->ismode('g')) {
      $user->sendnumeric($user->server,484,$target,"Target is an unkickable godlike operator");
    } else {
      $user->sendnumeric($user->server,484,$target,"Target is channel service");
    }
    return;
  }

  # don't we have to communicate this to other servers somehow ???

  @foo=$this->notifyofquit($sap);
  User::multisend(":$$user{nick}!$$user{user}\@$$user{host}"
		  ." KICK>$$this{name} $$sap{nick} :$excuse",@foo,$sap);
}

sub invite {
  my $this   = shift;
  my $from   = shift;
  my $target = shift;
  
  if($target->onchan($this)) {
    $from->sendnumeric($from->server,443,$target->nick,$this->{name},"is already on channel");
    return;
  }
  if($this->isop($from) || $from->ismode('g')) {
    $this->{'hasinvitation'}->{$target} = 1;
    $target->addinvited($this);
    $target->invite($from,$this->{name});
    $from->sendnumeric($from->server,341,$target->nick,$this->{name},undef);
  } else {
    $from->sendnumeric($from->server,482,$this->{name},"You are not a channel operator");
  }
}

sub nickchange {
  my $this = shift;
  my $user = shift;

  if($this->{'ops'}->{$user->{'oldnick'}}) {
    delete $this->{'ops'}->{$user->{'oldnick'}};
    $this->{'ops'}->{$user->nick()} = $user;
  }
  
  if($this->{'voice'}->{$user->{'oldnick'}}) {
    delete $this->{'voice'}->{$user->{'oldnick'}};
    $this->{'voice'}->{$user->nick()} = $user;
  }
  
  $_ = $this->{'jointime'}->{$user->{'oldnick'}};
  delete($this->{'jointime'}->{$user->{'oldnick'}});
  $this->{'jointime'}->{$user->nick()} = $_;

  delete($this->{'users'}->{$user->{'oldnick'}});
  $this->{'users'}->{$user->nick()} = $user;

  return $this->{'users'};
}

#####################################################################
# COMMUNICATION SUBROUTINES
###########################

sub checkvalidtosend {
  my $this = shift;
  my $user = shift;

  if($this->ismode('n') && (!defined($this->{'users'}->{$user->nick()}))) {
    $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel.\r\n");
    return 0;
  }

  if($this->ismode('m')) {
    if((!$this->hasvoice($user)) && (!($this->isop($user) ||
				       $user->ismode('g')))) {
      $user->senddata(":".$user->server->{name}." 404 ".$user->nick." ".$this->{name}." Cannot send to channel.\r\n");
      return 0;
    }
  }

  return 1;
}

# Sends a private message or notice to everyone on the channel.
sub privmsgnotice {
  my $this = shift;
  my $string = shift;
  my $user = shift;
  my $msg  = shift;

  unless($this->checkvalidtosend($user)) {
    return;
  }

  foreach(keys(%{$this->{'users'}})) {
    if(($this->{'users'}->{$_} ne $user)&&($this->{'users'}->{$_}->islocal())) {
      $this->{'users'}->{$_}->senddata(
				       sprintf(":%s!%s\@%s %s %s :%s\r\n",
					       $user->nick,
					       $user->username,
					       $user->host,
					       $string,
					       $this->{name},
					       $msg));
    }
  }
  # We need something to disseminate the message to other servers
}

# This function does two things. First, it removes a user from a channel.
# Second, it figures out what other users on the channel should be informed,
# but it does not inform them. It returns a list of the other users on this
# server that should be informed.
# NB the user who was removed is *not* in the list returned.
sub notifyofquit {
  my($chan,$user)=@_;
  my @inform;

  # make the user go away
  delete($user->{'channels'}->{$chan->{'name'}});
  delete($chan->{'users'}->{$user->nick()});
  delete($chan->{'ops'}->{$user->nick()});
  delete($chan->{'voice'}->{$user->nick()});
  delete($chan->{'jointime'}->{$user->nick()});

  # if the channel is now empty, it needs to go away too.
  if(0==scalar keys(%{$chan->{'users'}})) {
    delete(Utils::channels()->{$chan->{name}});
#    return (undef);
  }

  # now find out who gets to know about it
  foreach(keys(%{$chan->{'users'}})) {
    push(@inform,$chan->{'users'}->{$_}) if($chan->{'users'}->{$_}->islocal());
  }

  return @inform;
}

1;
