#!/usr/bin/perl
# 
# Channel.pm
# Created: Tue Sep 15 13:49:42 1998 by jay.kominek@colorado.edu
# Revised: Sat Feb  6 10:10:51 1999 by jay.kominek@colorado.edu
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
# Channel object for The Perl Internet Relay Chat Daemon
#####################################################################

package Channel;
use Utils;
use User;
use Server;
use strict;
use UNIVERSAL qw(isa);

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
  $this->{bans} = \%tmp;
  $this->{creation} = time();

  bless($this, $class);
  return $this;
}

#####################################################################
# DATA ACCESSING SUBROUTINES
############################

# Get the name of this channel
sub name {
  my $this = shift;
  return $this->{'name'};
}

# Get the name of this channel in a form suitable for
# keying a hash.
sub lcname {
  my $this = shift;
  my $tmp  = $this->{'name'};
  $tmp     =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $tmp;
}

sub users {
  my $this = shift;
  my @tmp = values(%{$this->{'users'}});
  return @tmp;
}

sub userhash {
  my $this = shift;
  return $this->{'users'};
}

# Sends the user /names output
sub names {
  my $this = shift;
  my $user = shift;

  my @lists;
  my($index,$count) = (0,0);
  foreach(keys(%{$this->{'users'}})) {
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
    $user->senddata(":".$user->server->name." 353 ".$user->nick." = ".$this->name." :".join(' ',@{$lists[$_]})."\r\n");
  }
}

sub isvalidchannelmode {
  my $mode = shift;
  if(grep {/$mode/} ("b","i","k",
		     "l","m","n",
		     "o","p","s",
		     "t","v")) {
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

# setmode attempts to set the given mode to true. If the mode
#  is not already set, then it sets it, and returns 1, else it
#  returns 0.
sub setmode {
  my $this = shift;
  my $mode = shift;
  if(!&isvalidchannelmode($mode)) {
    $this->senddata(":".$this->server->name." 501 ".$this->nick." :Unknown mode flag \'$mode\'\r\n");
  }
  if(!$this->{modes}->{$mode}) {
    $this->{modes}->{$mode} = 1;
    return 1;
  } else {
    return 0;
  }
}

# unsetmode does the opposite of setmode.
sub unsetmode {
  my $this = shift;
  my $mode = shift;
  if(!&isvalidchannelmode($mode)) {
    $this->senddata(":".$this->server->name." 501 ".$this->nick." :Unknown mode flag \'$mode\'\r\n");
    return 0;
  }
  if($this->{modes}->{$mode}) {
    $this->{modes}->{$mode} = 0;
    return 1;
  } else {
    return 0;
  }
}

# These functions manipulate or view the ban list for $this channel
#  bans are stored as a hash, keyed on the mask. The value for that
#  hash{key} is a an array, the first item of which contains the name
#  of the person who set the ban, and the second item containing the
#  time the ban was set.
# setban takes a mask, and if it is not already present, adds it to
#  the list of bans on the channel.
sub setban {
  my $this = shift;
  my $user = shift;
  my $mask = shift;

  if(!defined($this->{bans}->{$mask})) {
    $this->{bans}->{$mask} = ($user->nick,time());
    return 1;
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
    return 1;
  } else {
    return 0;
  }
}

# Returns the hash of bans. Not a reference to it.
sub banlist {
  my $this = shift;

  return($this->{bans});
}

# Takes a User object and returns true if that user
# is an op on this channel.
sub isop {
  my $this = shift;
  my $user = shift;
  if(defined($this->{ops}->{$user->lcnick()})) {
    return 1;
  } else {
    return 0;
  }
}

sub setop {
  my $this   = shift;
  my $user   = shift;
  if(!defined($this->{ops}->{$user->lcnick()})) {
    $this->{ops}->{$user->lcnick()} = $user;
    return 1;
  } else {
    return 0;
  }
}

sub unsetop {
  my $this   = shift;
  my $user   = shift;
  if(defined($this->{ops}->{$user->lcnick()})) {
    delete($this->{ops}->{$user->lcnick()});
    return 1;
  } else {
    return 0;
  }
}

# Takes a User object and tells you if it has a voice on
# this channel.
sub hasvoice {
  my $this = shift;
  my $user = shift;
  if(defined($this->{voice}->{$user->lcnick()})) {
    return 1;
  } else {
    return 0;
  }
}

sub setvoice {
  my $this   = shift;
  my $user   = shift;
  if(!defined($this->{voice}->{$user->lcnick()})) {
    $this->{voice}->{$user->lcnick()} = $user;
    return 1;
  } else {
    return 0;
  }
}

sub unsetvoice {
  my $this   = shift;
  my $user   = shift;
  if(defined($this->{voice}->{$user->lcnick()})) {
    delete($this->{voice}->{$user->lcnick()});
    return 1;
  } else {
    return 0;
  }
}

#####################################################################
# DATA MANIPULATING SUBROUTINES
###############################

sub mode {
  my $this = shift;
  my $user = shift;
  my $modestr = shift;
  my @arguments = @_;
  my @modebytes = split(//,$modestr);
  my(@accomplishedset,@accomplishedunset,@accomplishedargs);

  if(!defined($modestr)) {
    my(@modes,@args);
    foreach(keys(%{$this->{modes}})) {
      if($_ eq "k") {      push(@args,  $this->{key});
      } elsif($_ eq "l") { push(@args,  $this->{limit});
      }                    push(@modes, $_);
    }
    $user->sendnumeric($user->server,324,($this->name,"+".join('',@modes),@args),undef);
    $user->sendnumeric($user->server,329,($this->name,$this->{creation}),undef);
    return;
  } elsif($modestr eq "b") {
    foreach(keys(%{$this->{bans}})) {
      my @bandata = $this->{bans}->{$_};
      $user->sendnumeric($user->server,367,($this->name,$_,@bandata),undef);
    }
    $user->sendnumeric($user->server,368,($this->name),"End of Channel Ban List");
    return;
  }

  if($this->isop($user)) {
    my $state = 1;
    foreach(@modebytes) {
      if($_ eq "+") {
	$state = 1;
      } elsif($_ eq "-") {
	$state = 0;
      } else {
	if($state) {
	  if($_ eq "b") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->setban($user,$arg))) {
	      push(@accomplishedset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "o") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->setop($user,$arg))) {
	      push(@accomplishedset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "v") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->setvoice($user,$arg))) {
	      push(@accomplishedset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "l") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->setmode("l"))) {
	      $this->{limit} = $arg;
	      push(@accomplishedset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "k") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->setmode("k"))) {
	      $this->{key} = $arg;
	      push(@accomplishedset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($this->setmode($_)) {
	    push(@accomplishedset,$_);
	  }
	} else {
	  if($_ eq "b") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->unsetban($user,$arg))) {
	      push(@accomplishedunset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "o") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->unsetop($user,$arg))) {
	      push(@accomplishedunset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "v") {
	    my $arg = shift(@arguments);
	    if(defined($arg) && ($this->unsetvoice($user,$arg))) {
	      push(@accomplishedunset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($_ eq "k") {
	    my $arg = shift(@arguments);
	    if(($arg eq $this->{key}) && ($this->unsetmode("k"))) {
	      push(@accomplishedunset,$_);
	      push(@accomplishedargs,$arg);
	    }
	  } elsif($this->unsetmode($_)) {
	    push(@accomplishedunset,$_);
	  }
	}
      }
    }
    if($#accomplishedset>=0 || $#accomplishedunset>=0) {
      my $changestr;
      if($#accomplishedset>=0) {
	$changestr = "+".join('',@accomplishedset);
      }
      if($#accomplishedunset>=0) {
	$changestr = $changestr."-".join('',@accomplishedunset);
      }
      if($#accomplishedargs>=0) {
	$changestr = $changestr.join(' ','',@accomplishedargs);
      }
      foreach(values(%{$this->{'users'}})) {
	if($_->islocal()) {
	  $_->senddata(":".$user->nick."!".$user->username."\@".$user->host." MODE ".$this->name." :$changestr\r\n");
	}
      }
    }
  } else {
    $user->senddata(":".$user->server->name." 482 ".$user->nick." ".$this->name." You're not a channel operator.\r\n");
  }
}

sub topic {
  my $this = shift;
  my $user = shift;
  my $topic = shift;
  if(defined($user) && defined($topic)) {
    unless($this->ismode('t') && (!$this->isop($user))) {
      $this->{'topic'}        = $topic;
      $this->{topicsetter}  = $user->nick;
      $this->{topicsettime} = time();
      foreach(keys(%{$this->{'users'}})) {
	if($this->{'users'}->{$_}->islocal()) {
	  $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." TOPIC ".$this->name." :$topic\r\n");
	}
      }
    } else {
      $user->senddata(":".$user->server->name." 482 ".$user->nick." ".$this->name." :You're not a channel operator\r\n");
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

  my($fu,$bar) = ($user->nick,$this->name);

  # Test to see if the user is banned from the channel
  my @banmasks = keys(%{$this->banlist()});
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
    $user->senddata(":".$user->server->name." 474 ".$user->nick." ".$this->name." :Channot join channel (+b)\r\n");
    return;
  }

  if(defined($this->{hasinvitation}->{$user})) {
    $hasinvitation = 1;
    delete($this->{hasinvitation}->{$user});
  }

  # Test to see if the user needs and invitation
  if($this->ismode('i') && (!$hasinvitation)) {
    $user->sendnumeric($user->server,473,$user->nick,$this->name,"Channel join channel (+i)");
    return;
  }

  # If the user is invited, then they can bypass the key, limit, and bans
  if(!$hasinvitation) {
    # Test to see if the user knows the channel key
    if($this->ismode('k')) {
      unless(grep {/^$this->{key}$/} @keys) {
	$user->senddata(":".$user->server->name." 475 ".$user->nick." ".$this->name." :Cannot join channel (+k)\r\n");
	return;
      }
    }
  
    # Test to see if the channel is over the current population limit.
    if(($this->ismode('l')) &&
       ((1+scalar keys(%{$this->{'users'}}))>$this->{limit})) {
      $user->senddata(":".$user->server->name." 471 ".$user->nick." ".$this->name." :Cannot join channel (+l)\r\n");
      return;
    }

    # Test for bans, here
  }

  $user->{channels}->{$this->lcname()} = $this;
  $this->{'users'}->{$user->lcnick()}    = $user;
  if(1==scalar keys(%{$this->{'users'}})) {
    $this->setop($user);
  }
  foreach(keys(%{$this->{'users'}})) {
    if($this->{'users'}->{$_}->islocal()) {
      $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." JOIN :".$this->name."\r\n");
    }
  }
  if(defined($this->{'topic'})) {
    $this->topic($user);
  }
  $this->names($user);
  $user->sendnumeric($user->server,366,$user->nick,$this->name,"End of /NAMES list.");
  # Now tell all the servers..
}

# Called by (servers) to forcibly add a user, does no checking.
sub force_join {
  my $this = shift;
  my $user = shift;
  my $server = shift; # the server that is telling us about the
                      # user connecting has to tell us what it is
                      # so that when we propogate the join on,
                      # we don't tell it.

  Utils::channels()->{$this->lcname()} = $this;
  $this->{'users'}->{$user->lcnick()} = $user;
  foreach(keys(%{$this->{'users'}})) {
    if($this->{'users'}->{$_}->islocal()) {
      $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." JOIN :".$this->name."\r\n");
    }
  }
  # Now tell all the other servers..
}

# This one is called when a user leaves
sub part {
  my $this = shift;
  my $user = shift;
  my $server = shift;

  delete($user->{channels}->{$this->lcname()});
  foreach(keys(%{$this->{'users'}})) {
    if($this->{'users'}->{$_}->islocal()) {
      $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." PART :".$this->name."\r\n");
    }
  }
  delete($this->{'users'}->{$user->lcnick()});

  if(0==scalar keys(%{$this->{'users'}})) {
    delete(Utils::channels()->{$this->lcname()});
  }

  # Hmm. Need some way to determine if
  # we need to propogate the parting,
  # based on where it came from.
}

sub kick {
  my $this   = shift;
  my $user   = shift;
  my $target = shift;
  my $excuse = shift;

  if($this->isop($user)) {
    my $sap = Utils::lookup($target);
    if((!defined($sap)) || (!$sap->isa("User"))) {
      $user->sendnumeric($user->server,401,$target,"No such nick");
      return;
    }
    delete($sap->{channels}->{$this->lcname()});
    foreach(keys(%{$this->{'users'}})) {
      if($this->{'users'}->{$_}->islocal()) {

	$user->nick;

	$sap->nick;

	$this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." KICK ".$this->name." ".$sap->nick." :$excuse\r\n");
      }
    }
    delete($this->{'users'}->{$sap->lcnick()});
    if(0==scalar keys(%{$this->{'users'}})) {
      delete(Utils::channels()->{$this->lcname()});
    }
  } else {
    $user->sendnumeric($user->server,482,$this->name,"You are not a channel operator");
  }
}

sub invite {
  my $this   = shift;
  my $from   = shift;
  my $target = shift;

  if($this->isop($from)) {
    
    $this->{hasinvitation}->{$target} = 1;
    $target->addinvited($this);
    $target->invite($from,$this->name());
  } else {
    $target->sendnumeric($from->server,482,$this->name(),"You are not a channel operator");
  }
}

#####################################################################
# COMMUNICATION SUBROUTINES
###########################

sub checkvalidtosend {
  my $this = shift;
  my $user = shift;

  if($this->ismode('n') && (!defined($this->{'users'}->{$user->lcnick()}))) {
    $user->senddata(":".$user->server->name." 404 ".$user->nick." ".$this->name." Cannot send to channel.\r\n");
    return 0;
  }

  if($this->ismode('m')) {
    if((!$this->hasvoice($user)) && (!$this->isop($user))) {
      $user->senddata(":".$user->server->name." 404 ".$user->nick." ".$this->name." Cannot send to channel.\r\n");
      return 0;
    }
  }

  return 1;
}

# Sends a 'private message' to everyone on the channel.
sub privmsg {
  my $this = shift;
  my $user = shift;
  my $msg  = shift;

  unless($this->checkvalidtosend($user)) {
    return;
  }

  foreach(keys(%{$this->{'users'}})) {
    if(($this->{'users'}->{$_} ne $user)&&($this->{'users'}->{$_}->islocal())) {
      $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." PRIVMSG ".$this->name." :$msg\r\n");
    }
  }
  # We need something to disseminate the message to other servers
}

sub notice {
  my $this = shift;
  my $user = shift;
  my $msg  = shift;

  unless($this->checkvalidtosend($user)) {
    return;
  }

  foreach(keys(%{$this->{'users'}})) {
    if(($this->{'users'}->{$_} ne $user)&&($this->{'users'}->{$_}->islocal())) {
      $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." NOTICE ".$this->name." :$msg\r\n");
    }
  }
  # We need something to disseminate the message to other servers
}

# This is to tell us that a user has quit
sub notifyofquit {
  my $this = shift;
  my $user = shift;
  my $msg  = shift;

  delete($this->{'users'}->{$user->lcnick()});
  foreach(keys(%{$this->{'users'}})) {
    $this->{'users'}->{$_}->senddata(":".$user->nick."!".$user->username."\@".$user->host." QUIT :$msg\r\n");
  }

  if(0==scalar keys(%{$this->{'users'}})) {
    delete(Utils::channels()->{$this->lcname()});
  }
}

1;
