#!/usr/bin/perl
# 
# User.pm
# Created: Tue Sep 15 12:56:51 1998 by jay.kominek@colorado.edu
# Revised: Sun Nov 21 20:23:36 1999 by tek@wiw.org
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#  
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# User object for The Perl Internet Relay Chat Daemon
#####################################################################

use strict;

package User;
use Utils;
use Server;
use Channel;

use UNIVERSAL qw(isa);

use Tie::IRCUniqueHash;

my $commands = {'PONG'    => sub { },
		'PRIVMSG' => \&handle_privmsg,
		'NOTICE'  => \&handle_notice,
		'JOIN'    => \&handle_join,
		'CHANNEL' => \&handle_join,
		'PART'    => \&handle_part,
		'TOPIC'   => \&handle_topic,
		'KICK'    => \&handle_kick,
		'INVITE'  => \&handle_invite,
		'WHOIS'   => \&handle_whois,
		'WHO'     => \&handle_who,
		'WHOWAS'  => \&handle_whowas,
		'ISON'    => \&handle_ison,
		'USERHOST' => \&handle_userhost,
		'LUSERS'  => \&handle_lusers,
		'LIST'    => \&handle_list,
		'NAMES'   => \&handle_names,
		'STATS'   => \&handle_stats,
		'VERSION' => \&handle_version,
		'TIME'    => \&handle_time,
		'INFO'    => \&handle_info,
		'MOTD'    => \&handle_motd,
		'ADMIN'   => \&handle_admin,
		'MAP'     => \&handle_map,
		'LINKS'   => \&handle_links,
		'TRACE'   => \&handle_trace,
		'MODE'    => \&handle_mode,
		'OPER'    => \&handle_oper,
		'AWAY'    => \&handle_away,
		'NICK'    => \&handle_nick,
		'SQUIT'   => \&handle_squit,
		'CONNECT' => \&handle_connect,
		'KILL'    => \&handle_kill,
		'WALLOPS' => \&handle_wallops,
		'REHASH'  => \&handle_rehash,
		'QUIT'    => \&handle_quit
	       };

#####################################################################
# CLASS CONSTRUCTOR
###################

# You just pass this the connection object that it is spawned from.
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };
  my $connection = shift;

  # The connection object that we're spawned from has
  #  lots of information that we need to know to be who
  #  we are.
  $this->{'nick'}        = $connection->{'nick'};
  $this->{'user'}        = $connection->{'user'};
  $this->{'host'}        = $connection->{'host'};
  $this->{'ircname'}     = $connection->{'ircname'};
  $this->{'server'}      = $connection->{'server'};
  $this->{'connected'}   = $connection->{'connected'};
  $this->{'last_active'} = time();
  $this->{'modes'}       = { };

  tie my %channeltmp, 'Tie::IRCUniqueHash';
  $this->{'channels'}      = \%channeltmp;
  tie my %invitetmp,  'Tie::IRCUniqueHash';
  $this->{'hasinvitation'} = \%invitetmp;

  bless($this, $class);
  $this->server->adduser($this);
  if(defined($connection->{'socket'})) {
    $this->{'socket'}    = $connection->{'socket'};
    $this->{'outbuffer'} = $connection->{'outbuffer'};
    foreach my $server ($this->server->children) {
      $server->nick($this);
    }
    $this->sendsplash();
  }
  return $this;
}

# Send the "splash" screen information junk stuff.
sub sendsplash {
  my $this = shift;

  $this->sendnumeric($this->server,1,
   "Welcome to the Internet Relay Network ".$this->nick);
  $this->sendnumeric($this->server,2,
   "Your host is ".$this->server->{name}.", running version ".$this->server->VERSION);
  $this->sendnumeric($this->server,3,
   "This server was created ".scalar gmtime($this->server->creation));
  $this->sendnumeric($this->server,4,($this->server->{name},$this->server->VERSION,"dioswkg","biklmnopstv"),undef);
  # Send them LUSERS output
  $this->handle_lusers("LUSERS");
  $this->notice($this->server,"Highest connection count: 0 (0 clients)");
  # Send them the MOTD upon connection
  $this->handle_motd("MOTD");
}

# Given a line of user input, process it and take appropriate action
sub handle {
    my($this, $line)=(shift,shift);

    Utils::do_handle($this,$line,$commands);
}

#####################################################################
# VARIOUS COMMAND HANDLERS

#####################################################################
# One-to-One, One-to-Many communication

# PRIVMSG target :message
# Where target is either a user or a channel

# do the work for the privmsg and notice handlers
sub msg_or_notice {
    my($this,$string,$targetstr,$msg)=(shift,shift,shift,shift);
    my $target;

  foreach $target (split(/,/,$targetstr)) {
    if($this->ismode('o') && ($target =~ /^\$/)) {
      my $matchingservers = $target;
      $matchingservers =~ s/^\$//;
      $matchingservers =~ s/\./\\\./g;
      $matchingservers =~ s/\?/\./g;
      $matchingservers =~ s/\*/\.\+/g;
      foreach my $server (values(%{Utils::servers()})) {
	if($server->{name} =~ /$matchingservers$/) {
	  if($server eq $this->server) {
	    my @users = $this->server->users();
	    foreach my $user (@users) {
	      $user->senddata(":".$this->nick."!".$this->username."\@".$this->host." $string $target :".$msg."\r\n");
	    }
	  } else {
	    # The server is remote. Dispatch the global privmsg/notice
	  }
	}
      }
    } elsif($this->ismode('o') && ($target =~ /^\#/)) {
      my $matchingusers = $target;
      $matchingusers =~ s/^\$//;
      $matchingusers =~ s/\./\\\./g;
      $matchingusers =~ s/\?/\./g;
      $matchingusers =~ s/\*/\.\+/g;
      foreach my $user ($this->server->users()) {
	if($user->host =~ /$matchingusers/) {
	  $user->senddata(":".$this->nick."!".$this->username."\@".$this->host." $string $target :".$msg."\r\n");
	}
      }
      # dispatch globally.
    } else {
      # ..lookup the associated object..
      my $tmp = Utils::lookup($target);
      if(isa($tmp,"User")||isa($tmp,"Channel")) {
	  # ..and if it is a user or a channel (since they're the only things
	  #  that can handle receiving a private message), dispatch it to them.
	  if($string eq "PRIVMSG") {
	      $tmp->privmsg($this,$msg);
	  } else {
	      $tmp->notice($this,$msg);
	  }
      } else {
      # Complain that the..   ..doesn't exist.
	if(($target =~ /^\#/)||($target =~ /^\&/)) {
	  #              ..channel..
	  $this->sendnumeric($this->server,403,($target),"No such channel");
	} else {
	  #               ..user..
	  $this->sendnumeric($this->server,401,($target),"No such nick");
	}
      }
    }
  }
}

# PRIVMSG
sub handle_privmsg {
    my($this,$dummy,$targetstr,$msg)=(shift,shift,shift,shift);

#    print "about to msg_or_notice '$this' PRIVMSG '$targetstr' '$msg'\n";
#    print "d '$dummy' rest '".join(':',@_)."'\n";
    msg_or_notice($this,'PRIVMSG',$targetstr,$msg);
}

# NOTICE
sub handle_notice {
    my($this,$dummy,$targetstr,$msg)=(shift,shift,shift,shift);

    msg_or_notice($this,'NOTICE',$targetstr,$msg);
}

#####################################################################
# Channel Membership
#  These functions directly manipulate the current user's membership
# on the channel in question.

# JOIN #channel1,#channel2,..,#channeln-1,#channeln
# JOIN #channel1,#channel2,..,#channeln-1,#channeln :key1,key2,..,keyn-1,keyn
# Or s/JOIN/CHANNEL/ those.
sub handle_join {
  my($this,$dummy,$channelstr,$keystr)=(shift,shift,shift,shift);
  my @channels = split(/,/,$channelstr);
  my @keys     = split(/,/,$keystr);

  # For each channel they want to join..
  foreach my $channel (@channels) {
    # ..look it up..
    my $tmp = Utils::lookup($channel);
    # ..if it is a channel..
    if(defined($tmp) && $tmp->isa("Channel")) {
      # ..then ask to join it, passing on all the keys
      $tmp->join($this,@keys);
    } else {
      # ..otherwise, complain about their stupidity.
      if(($channel =~ /^\#/) || ($channel =~ /^\&/)) {
	my $chanobj = Channel->new($channel);
	Utils::channels()->{$chanobj->{name}} = $chanobj;
	$chanobj->join($this);
      } else {
	$this->sendnumeric($this->server,403,($channel),"No such channel");
      }
    }
  }
}

# PART #channel1,#channel2,..,#channeln-1,#channeln
sub handle_part {
  my($this,$dummy,$channelstr)=(shift,shift,shift);
  my $channel;

  foreach $channel (split(/,/,$channelstr)) {
    my $channeltmp = Utils::irclc($channel);
    my $tmp = Utils::channels()->{$channeltmp};
    if(defined($tmp)) {
      if(defined($this->{channels}->{$tmp->{name}})) {
	$tmp->part($this,$this->server);
      } else {
	$this->sendnumeric($this->server,403,$tmp->{name},"You're not on that channel.");
      }
    } else {
      $this->sendnumeric($this->server,403,$channel,"No such channel.");
    }
  }
}

#####################################################################
# Other channel related stuffs
#  Misc commands for channels that don't deal with the current users
# membership on the channel.

# TOPIC #channel
# TOPIC #channel :useful information about the channel
sub handle_topic {
  my($this,$dummy,$channel,$topic)=(shift,shift,shift,shift);
  my @channels = split(/,/,$channel);
  my $ret = Utils::lookup($channel);

  if((!defined($ret)) || (!$ret->isa("Channel"))) {
    $this->sendnumeric($this->server,403,$channel,"No such channel.");
    return;
  }
  foreach(@channels) {
    if(defined($topic)) {
      $ret->topic($this,$topic);
    } else {
      my @topicdata = $ret->topic;
      if($#topicdata==2) {
	$this->sendnumeric($this->server,332,$ret->{name},$topicdata[0]);
	$this->sendnumeric($this->server,333,$ret->{name},$topicdata[1],$topicdata[2],undef);
      } else {
	$this->sendnumeric($this->server,331,$ret->{name},"No topic is set");
      }
    }

    # Note: It might be better to put the if outside of
    # the foreach loop so that we have fewer comparisons.
  }
}

# KICK #channel1,#channel2,..,#channeln nick1,nick2,..,nickn :excuse
sub handle_kick {
  my($this,$dummy,$chanstr,$nickstr,$excuse)=(shift,shift,shift,shift,shift);
  my(@channels) = split(/,/,$chanstr);
  my(@nicks)    = split(/,/,$nickstr);

  $excuse =~ s/^://;

  if($chanstr eq "*") {
    # untested
    @channels = values(%{$this->{channels}});
  }

  # ..for each of the targetted channels..
  foreach my $channel (@channels) {
    # ..look up the associated object..
    my $ret = Utils::lookup($channel);
    # ..if it exists and is a channel..
    if(defined($ret)&&$ret->isa("Channel")) {
      # ..then for every given nick..
      foreach(@nicks) {
	# ..ask the channel to kick them off.
	$ret->kick($this,$_,$excuse);
      }
    }
  }
}

# INVITE
sub handle_invite {
  my($this,$dummy,$nick,$channel)=(shift,shift,shift,shift);
  my $waste;

    ($channel,$waste)         = split(/,/,$channel);
  
  my $tmpchan = Utils::lookupchannel($channel);
  my $user    = Utils::lookupuser($nick);
  if($user && isa($user,"User")) {
    if($tmpchan && isa($tmpchan,"Channel")) {
      $tmpchan->invite($this,$user);
    } else {
      # it is valid to invite people to channels that do not exist
      $user->invite($this,$channel);
    }
  } else {
    $this->sendnumeric($this->server,401,$this->{name},$nick,"No such nick");
  }
}

#####################################################################
# Informational Commands
#  This provide the user with various different bits of information
# about the state of things on the network.

# WHOIS server.foo.bar nick1,nick2,..,nickn-1,nickn
# WHOIS nick1,nick2,..,nickn-1,nickn
sub handle_whois {
  my $this = shift;
  my($command,@excess) = split(/\s+/,shift);

  if($excess[1]) {
    # They're trying to request the information
    # from another server.
  } else {
    my @targets = split(/,/,$excess[0]);
    foreach(@targets) {
      my $user = Utils::lookup($_);
      if(defined($user) && isa($user, "User")) {
	# *** Nick is user@host (Irc Name)
	$this->sendnumeric($this->server,311,($user->nick,$user->username,$user->host,"*"),$user->ircname);
	# *** on channels: #foo @#bar +#baz
	my @names;
	if(scalar keys(%{$user->{channels}})>0) {
	  foreach(keys(%{$user->{channels}})) {
	    my $channel = Utils::channels()->{$_};
	    unless($channel->ismode('s') &&
		   !defined($channel->{users}->{$this->nick()}) &&
		   !$this->ismode('g')) {
	      my $tmpstr = $channel->{name};
	      if($channel->isop($user)) {
		$tmpstr = "@".$tmpstr;
	      } elsif($channel->hasvoice($user)) {
		$tmpstr = "+".$tmpstr;
	      }
	      push(@names,$tmpstr);
	    }
	  }
	  $this->sendnumeric($this->server,319,($user->nick),join(' ',@names));
	}
	# *** on IRC via server foo.bar.org ([1.2.3.4] Server Name)
	$this->sendnumeric($this->server,312,($user->nick,$user->server->{name}),$user->server->description);
	# *** Nick is an IRC Operator
	#  ... or ...
	# *** Nick is a god-like IRC Operator
	if($user->ismode('o')) {
	  $this->sendnumeric($this->server,313,$user->nick,"is ".(($user->ismode('g'))?"a god-like":"an")." IRC Operator\r\n");
	}
	# *** Nick is away: excuse
	if($user->away()) {
	  $this->sendnumeric($this->server,301,$user->nick,$user->away);
	}
	# *** Nick has been 3 minutes and 42 seconds idle
	if($user->islocal()) {
	  $this->sendnumeric($this->server,317,($user->nick,time()-$user->last_active,$user->connected),"seconds idle, signon time");
	}
      }
    }
    $this->sendnumeric($this->server,318,$excess[0],"End of /WHOIS list.");
  }
}

# WHO targets
sub handle_who {
  my($this,$dummy,$targets)=(shift,shift,shift);
  my $target;

  foreach $target (split(/,/,$targets)) {
    my $ret = Utils::lookup($target);
    if(defined($ret)) {
      if($ret->isa("User")) {
	$this->sendnumeric($this->server,352,("*",$ret->username,$ret->host,$ret->server->{name},$ret->nick,"H"),$ret->server->hops." ".$ret->ircname);
      } elsif($ret->isa("Channel")) {
	unless(($ret->ismode('s'))&&(!defined($ret->{users}->{$this->nick()}))&&(!$this->ismode('g'))) {
	  my @users = $ret->users();
	  foreach my $user (@users) {
	    $this->sendnumeric($this->server,352,($ret->{name},$user->username,$user->host,$user->server->{name},$user->nick,"H"),$user->server->hops." ".$user->ircname);
	  }
	}
      } elsif($ret->isa("Server")) {
	my @users = $ret->users();
	my $user;
	foreach $user (@users) {
	  # ?
	}
      }
    }
  }
  $this->sendnumeric($this->server,315,$targets,"End of /WHO list.");
}

# WHOWAS nicks
sub handle_whowas {
  my($this,$dummy,$targets)=(shift,shift,shift);
  my $target;

  foreach $target (split(/,/,$targets)) {

  }
}

# ISON nick nick nick
sub handle_ison {
  my($this,$dummy,$targets)=(shift,shift,shift);
  my @ison;

  foreach my $target (split(/\s+/,$targets)) {
    my $ret = Utils::lookup($target);
    if(defined($ret) && $ret->isa("User")) {
      push(@ison,$ret->nick);
    }
  }
  $this->sendnumeric($this->server,303,join(' ',@ison));
}

# USERHOST nick nick nick
sub handle_userhost {
  my($this,$dummy,$targets)=(shift,shift,shift);
  my $target;
  my @results;

  foreach $target (split(/\s+/,$targets)) {
    my $ret = Utils::lookup($target);
    if(defined($ret) && $ret->isa("User")) {
      push(@results,$ret->nick."=".(defined($ret->away)?"-":"+").$ret->username."\@".$ret->host);
    }
  }
  $this->sendnumeric($this->server,302,join(' ',@results));
}

# LUSERS
sub handle_lusers {
  my $this = shift;
  $this->sendnumeric($this->server,251,"There are ".$this->server->users." users and 0 invisible on 1 server(s)");
  $this->sendnumeric($this->server,252,0,"operator(s) online");
  $this->sendnumeric($this->server,253,(scalar keys(%{Utils::channels()})),"channels formed");
  $this->sendnumeric($this->server,255,"I have ".$this->server->users." user(s) and ".$this->server->children." server(s)\r\n");
}

# LIST
sub handle_list {
  my $this = shift;
  $this->sendnumeric($this->server,321,("Channel","Users"),"Name");
  my %channels = %{Utils::channels()};
  foreach my $channel (keys(%channels)) {
    unless($channels{$channel}->ismode('s') &&
	   !defined($channels{$channel}->{users}->{$this->nick()}) &&
	   !$this->ismode('g')) {
      my @topicdata = $channels{$channel}->topic;
      $this->sendnumeric($this->server,322,
			 ($channels{$channel}->{name},
			  scalar $channels{$channel}->users),$topicdata[0]);
    }
  }
  $this->sendnumeric($this->server,323,"End of /LIST");
}

# NAMES
sub handle_names {
  my($this,$dummy,$channels)=(shift,shift,shift);
  my $chan;
  my @chanlist;
  my $foo;
  my $waswildcard=0;

  if(defined($channels)) {
    foreach $chan (split(/,/,$channels)) {
      $foo=Utils::lookup($chan);
      if(defined($foo) && $foo->isa("Channel")) {
         push @chanlist, $foo;
      }
    }
  } else {
    @chanlist=values(%{Utils::channels()});
    $waswildcard=1;
  }

  if($#chanlist==-1) {
    die "FIXME: need to return empty RPL_ENDOFNAMES for chan not found";
  }

  foreach $chan (@chanlist) {
    unless($chan->ismode('s') &&
           !defined($chan->{users}->{$this->nick()}) &&
	   !$this->ismode('g')) {
      $chan->names($this);
      $this->sendnumeric($this->server,366,"*","End of /NAMES list.");
    }
  }

  if($waswildcard) {
    # FIXME also print list of lusers on no channel
    $this->sendnumeric($this->server,366,"*","End of /NAMES list.");
  }
}

# STATS
sub handle_stats {
  my($this,$dummy,$request,$server)=(shift,shift,shift,shift);

  for(uc($request)) {
      /^O/ && do {
	  my %opers = %{$this->server->getopers()};
	  foreach my $nick (keys(%opers)) {
	      $this->sendnumeric($this->server,243,"O",$opers{$nick}->{mask},"*",$nick,0,10,undef);
	  }
      };
      /^[CN]/ && do {
	  # no network-fu!
      };
  }

  # TODO
  $this->sendnumeric($this->server,219,$request,"End of /STATS report.");
}

# VERSION
sub handle_version {
  my $this = shift;
  $this->sendnumeric($this->server->{name},351,($this->server->version,$this->server->{name}),"some crap");
}

# TIME
sub handle_time {
  my($this,$dummy,$server)=(shift,shift,shift);

  if(!defined($server)) {
    my $time = time();
    $this->sendnumeric($this->server,391,($this->server->{name},$time,0),scalar gmtime($time));
  } else {
    # They want to request the time from a remote server.
  }
}

# INFO
sub handle_info {
  my $this = shift;
  # TODO
}

# MOTD
sub handle_motd {
  my $this = shift;
  $this->sendnumeric($this->server,375,"- ".$this->server->{name}." Message of the Day -");
  foreach($this->server->getmotd) {
    $this->sendnumeric($this->server,372,"- $_");
  }
  $this->sendnumeric($this->server,376,"End of /MOTD command.");
}

# ADMIN
sub handle_admin {
  my $this = shift;
  $this->sendnumeric($this->server,256,"Administrative info about ".$this->server->{name});
  my @admindata = $this->server->getadmin();
  $this->sendnumeric($this->server,257,$admindata[0]);
  $this->sendnumeric($this->server,258,$admindata[1]);
  $this->sendnumeric($this->server,259,$admindata[2]);
}

# MAP
sub handle_map {
  my $this = shift;

  my $server = $this->server;
  my @atdepth;

  $this->sendnumeric($this->server,5,$server->{name});
  foreach($server->children) {
    &map_children_disp($this,$_,2);
  }
  $this->sendnumeric($this->server,7,"End of /MAP");
}

sub map_children_disp {
  my $this   = shift;
  my $server = shift;
  my $depth  = shift;

  $this->sendnumeric($this->server,5,(" "x$depth).$server->{name});
  foreach($server->children) {
    &map_children_disp($this,$_,$depth+2);
  }
}

# LINKS
sub handle_links {
  my $this = shift;
  # TODO
}

# TRACE
sub handle_trace {
  my $this = shift;
  # TODO
}

#####################################################################
# State accessing commands
#  These commands allow a user to manipulate their state, or (in the
# case of MODE) the state of channels.

# MODE target :modebytes modearguments
sub handle_mode {
  my($this,$dummy,$target,$modestr)=(shift,shift,shift,shift);
  my @arguments=@_;
  my @modebytes = split(//,$modestr);
  my(@accomplishedset, @accomplishedunset);

  my $ret = Utils::lookup($target);
  if((!defined($ret))||(!ref($ret))) {
    $this->sendnumeric($this->server,403,($target),"No such channel.");
    return;
  }
  if($ret->isa("User")) {
    # We're going to try and change a user's modes.
    if($ret eq $this) {
      # We're trying to change our own modes
      my($state,$byte) = (1,'');
      MODEBYTE: foreach $byte (@modebytes) {
	if($byte eq "+") {
	  $state = 1;
	} elsif($byte eq "-") {
	  $state = 0;
	} else {
	  if(!$this->ismode('o')) {
	    if(grep {/$byte/} ("o","k","g")) {
	      next MODEBYTE;
	    }
	  }
	  if($state) {
	    if($this->setmode($byte)) {
	      push(@accomplishedset,$byte);
	    }
	  } else {
	    if($this->unsetmode($byte)) {
	      push(@accomplishedunset,$byte);
	      if($byte eq 'o') {
		if($this->unsetmode('g')) {
		  push(@accomplishedunset,'g'); }
		if($this->unsetmode('k')) {
		  push(@accomplishedunset,'k'); }
	      }
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
	$this->senddata(":".$this->nick." MODE ".$this->nick." $changestr\r\n");
	foreach my $server ($this->server->children) {
	  $server->mode($this,$this,$changestr);
	}
      }
    } else {
      # We're trying to change someone else's modes,
      # which is generally considered bad form.
      $this->sendnumeric($this->server,502,"Can't change modes for other users.");
    }
  } elsif($ret->isa("Channel")) {
    # In the spirit of letting the channel object handle
    # most of the checking in regards to itself, we simply
    # send the mode change request to it, and let it sort
    # out whether or not we're op'd and what not.
    $ret->mode($this,$modestr,@arguments);
  }
}

# OPER nick :password
sub handle_oper {
  my($this,$dummy,$nick,$password)=(shift,shift,shift,shift);

  if($this->ismode('o')) {
    return;
  }

  my $opers = $this->server->{'opers'};

  my $mymask = $this->nick."!".$this->username."\@".$this->host;
  if(defined($opers->{$nick})) {
    my %info  = %{ $opers->{$nick} };
    if($mymask =~ /$info{mask}$/i) {
      if(crypt($password,$info{password}) eq $info{password}) {
	$this->setmode('o');
	$this->setmode('w');
	$this->setmode('s');
	$this->senddata(":".$this->nick." MODE ".$this->nick." :+ows\r\n");
	$this->sendnumeric($this->server,381,"Your are now an IRC Operator");
      } else {
	$this->sendnumeric($this->server,464,"Password Incorrect.");
      }
    } else {
      $this->sendnumeric($this->server,491,"No O-lines for your host mask.");
    }
  } else {
    $this->sendnumeric($this->server,491,"No O-lines for your nick.");
  }
}

# AWAY
# AWAY :my excuse
sub handle_away {
  my $this = shift;
  my($command,$msg) = split(/\s+/,shift,2);
  $msg =~ s/^://;
  if($msg) {
    $this->{awaymsg} = $msg;
    $this->sendnumeric($this->server,306,"You have been marked as away.");
  } else {
    delete($this->{awaymsg});
    $this->sendnumeric($this->server,305,"You are no longer marked as away.");
  }
}

# NICK :mynewnick
sub handle_nick {
  my($this,$dummy,$newnick)=(shift,shift,shift);

  Connection::donick($this,$dummy,$newnick);
}

#####################################################################
# Oper-ish Stuff
#  These commands are available only to users who are +o.  They deal
# with the maintenance of the local server and the network as a whole.
#

# SQUIT
sub handle_squit {
  my $this = shift;
  my($command,$tserver) = split/\s+/,shift,2;

}

# CONNECT
sub handle_connect {
  my $this = shift;
  my($command,$tserver,$port,$sserver) = split/\s+/,shift,4;
  if(!defined($sserver)) {
    my $tserverinfo = $this->server->lookupconnection($tserver);
    if(!ref($tserverinfo)) {
     $this->notice($this->server,"Connect: Host $tserver not listed in configuration");
     return;
    }
    $port = $port || $$tserverinfo[2] || 6667;
    my $socket =
      IO::Socket::INET->new(PeerAddr => $$tserverinfo[1],
			    PeerPort => $port,
			    Proto    => 'tcp');
    if(defined($socket)) {
      &main::addinitiatedclient($socket,
				"PASS :$$tserverinfo[2]\r\n" .
				"SERVER ".$this->server->{name}." 1 0 ".time." Px1 :".$this->server->description."\r\n");
    } else {
      $this->notice($this->server,"Failed to connect to $tserver port $port");
    }
  } else {
    # Forward the connect request to another server
  }
}

# KILL nick :excuse
sub handle_kill {
  my $this = shift;
  my($command,$target,$excuse) = split/\s+/,shift,3;
  $excuse =~ s/^://;
  # Look the user up, call $user->kill($this,$excuse)
  # Of course, that requires Users have a kill method.
  # So you'll have to write that, too.
}

# WALLOPS :wibble
sub handle_wallops {
  my $this = shift;
  my($command,$message) = split(/\s+/,shift,2);
  my($user,$server);

  if(!$this->ismode('o')) {
    $this->sendnumeric($this->server,481,"Permission Denied- You're not an IRC operator");
    return;
  }

  $message =~ s/^://;
  foreach $user ($this->server->users()) {
    if($user->ismode('w')) {
      $user->senddata(":".$this->nick."!".$this->username."\@".$this->host." WALLOPS :$message\r\n");
    }
  }
  foreach $server ($this->server->children) {
    $server->wallops($this,$message);
  }
}

# REHASH
sub handle_rehash {
  my $this = shift;
  if($this->ismode('o')) {
    $this->sendnumeric($this->server,382,("server.conf"),"Rehashing");
    $this->server->opernotify($this->nick." is rehashing the server configuration file.");
    $this->server->rehash();
  } else {
    $this->sendnumeric($this->server,481,"Permission Denied- You're not an IRC operator");
  }
}

# ***

# QUIT
# QUIT :my excuse
sub handle_quit {
  my $this = shift;
  my($command,$msg) = split(/\s+/,shift,2);
  $msg =~ s/^://;
  foreach my $server ($this->server->children) {
    $server->uquit($this,$msg);
  }
  $this->quit($msg);
}

#####################################################################
# DATA ACCESSING SUBROUTINES
############################

# Get the nick of this user
sub nick {
  my $this = shift;
  return $this->{'nick'};
}

sub username {
  my $this = shift;
  return $this->{'user'};
}

sub ircname {
  my $this = shift;
  return $this->{'ircname'};
}

sub host {
  my $this = shift;
  return $this->{'host'};
}

sub islocal {
  my $this = shift;
  if(defined($this->{'socket'})) {
    return 1;
  } else {
    return 0;
  }
}

sub server {
  my $this = shift;
  return $this->{'server'};
}

sub isoper {
  my $this = shift;
  return 0;
}

sub isvalidusermode {
  my $mode = shift;
  if(grep {/$mode/} ("d","i","o","s","w","k","g")) {
    return 1;
  } else {
    return 0;
  }
}

sub ismode {
  my $this = shift;
  my $mode = shift;
  if($this->{modes}->{$mode}==1) {
    return 1;
  } else {
    return 0;
  }
}

sub setmode {
  my $this = shift;
  my $mode = shift;
  if(!&isvalidusermode($mode)) {
    $this->senddata(":".$this->server->{name}." 501 ".$this->nick." :Unknown mode flag \'$mode\'\r\n");
    return 0;
  }
  if(!$this->{modes}->{$mode}) {
    $this->{modes}->{$mode} = 1;
    return 1;
  } else {
    return 0;
  }
}

sub unsetmode {
  my $this = shift;
  my $mode = shift;
  if(!&isvalidusermode($mode)) {
    $this->senddata(":".$this->server->{name}." 501 ".$this->nick." :Unknown mode flag \'$mode\'\r\n");
    return 0;
  }
  if($this->{modes}->{$mode}) {
    delete($this->{modes}->{$mode});
    return 1;
  } else {
    return 0;
  }
}

sub genmodestr {
  my $this = shift;
  my %modestr = %{$this->{modes}};
  return ("+".join('',keys(%modestr)));
}

# Last time this user was active
sub last_active {
  my $this = shift;
  return $this->{last_active};
}

sub connected {
  my $this = shift;
  return $this->{connected};
}

sub away {
  my $this = shift;
  return $this->{awaymsg};
}

# We don't want to ping someone we've already pung.
sub ping_in_air {
  my $this = shift;
  if($this->{ping_waiting}) {
    return 1;
  } else {
    return 0;
  }
}

#####################################################################
# SENDING THIS USER STUFF
#########################

# Sends this user a private message
sub privmsg {
  my $this = shift;
  my $from = shift;
  my $msg  = shift;

  if($this->{'socket'}) {
    if(isa($from,"User")) {
      $this->senddata(":".$from->nick."!".$from->username."\@".$from->host." PRIVMSG ".$this->nick." :$msg\r\n");
    } elsif(isa($from,"Server")) {
      $this->senddata(":".$from->{name}." PRIVMSG ".$this->nick." :$msg\r\n");
    }
  } else {
    # They're not a local user, so we'll have to
    # route it through a server.
    # $this->server->privmsg($from,$this,$msg);
  }
}

# Sends this user a notice
sub notice {
  my $this = shift;
  my $from = shift;
  my $msg  = shift;

  if($this->{'socket'}) {
    if(isa($from,"User")) {
      $this->senddata(":".$from->nick."!".$from->username."\@".$from->host." NOTICE ".$this->nick." :$msg\r\n");
    } elsif(isa($from,"Server")) {
      $this->senddata(":".$from->{name}." NOTICE ".$this->nick." :$msg\r\n");
    }
  } else {
    # They're not a local user, so we'll have to
    # route it through a server.
    # $this->server->notice($from,$this,$msg);
  }
}

sub invite {
  my($this,$from,$channel) = @_;
  if($this->{'socket'}) {
    # local user
    $this->senddata(":".$from->nick."!".$from->username."\@",$from->host." INVITE ".$this->nick." :$channel\r\n");
  } else {
    # dispatch to the relevent server

  }
}

sub addinvited {
  my($this,$channel) = @_;
  $this->{hasinvitation}->{$channel->{name}} = 1;
}

# Sends the person a ping to test connectivity.
sub ping {
  my $this = shift;
  if($this->{'socket'}) {
    # If they're not a local user, its not our problem
    $this->{ping_waiting} = 1;
    $this->senddata("PING :".$this->{'server'}->{name}."\r\n");
  }
}

# This happens when the person quits.
sub quit {
  my $this = shift;
  my $msg  = shift;
  my($channame);
  # Remove them from all appropriate structures, etc
  # and announce it to local channels
  foreach $channame (keys(%{$this->{'hasinvitation'}})) {
    my $channel = Utils::lookupchannel($channame);
    if(ref($channel) && isa($channel,"Channel")) {
      delete($channel->{'hasinvitation'}->{$this});
    }
  }
  # Notify all the channels they're in of their disconnect
  # So that no given user will receive the signoff message twice,
  # we build this hash and then send the message to those users.
  my(%userlist);
  foreach my $channel (keys(%{$this->{'channels'}})) {
    my %storage = %{$this->{channels}->{$channel}->notifyofquit($this,$msg)};
    foreach(keys %storage) { $userlist{$_} = $storage{$_} }
  }
  foreach my $user (keys %userlist) {
    next unless $userlist{$user}->islocal();
    $userlist{$user}->senddata(":".$this->nick."!".$this->username."\@".$this->host." QUIT :$msg\r\n");
  }
  # Tell connected servers that they're gone
  $this->server->removeuser($this);
  # Remove us from the User hash
  delete(Utils::users()->{$this->nick()});
  # Disconnect them
  if($this->islocal()) {
    &main::finishclient($this->{'socket'});
  }
}

#####################################################################
# RAW, LOW-LEVEL OR MISC SUBROUTINES
####################################

# Adds a command to the hash of commandname->subroutine refs
sub addcommand {
  my $this    = shift;
  my $command = shift;
  my $subref  = shift;

  $this->{commands}->{$command} = $subref;
}

sub sendnumeric {
  Connection::sendnumeric(@_);
}

# Does the actual queueing of a bit of data
sub senddata {
  Connection::senddata(@_);
}

1;
