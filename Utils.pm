#!/usr/bin/perl
# 
# Utils.pm
# Created: Wed Sep 23 21:56:44 1998 by jay.kominek@colorado.edu
# Revised: Wed Jun  5 13:01:40 2002 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
# 
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# Methods to access global data structures, and the data structures
# themselves.
#####################################################################

package Utils;
#use User;
#use Server;
#use Channel;
use Sys::Syslog ();
use UNIVERSAL qw(isa);
use strict;
use vars qw($VERSION %params);

use Tie::IRCUniqueHash;
# We store these structures in a globalish location,
# to let everything get at the same data.
tie my %users,    'Tie::IRCUniqueHash';
tie my %servers,  'Tie::IRCUniqueHash';
tie my %channels, 'Tie::IRCUniqueHash';
    my @nickhistory;

my $syslogsetup = 0;

$VERSION="pircd-beta-0";
%params=(syslog=>0,		# use syslog for log messages?
	 logfile=>undef,	# filename for log, use STDERR if undef
	 );


sub lookup {
  my $name = shift;
  chomp $name;

  # If it starts with a # or &, then it is a channel that we're
  # trying to look up.
  if(($name =~ /^\#/) || ($name =~ /^\&/)) {
    if($channels{$name}) {
      return $channels{$name};
    } else {
      return undef;
    }
  } elsif($name =~ /\./) {
    # If it has a period in it, then it has to be a server. Assuming
    # we did proper checking on new nicks. Which we don't.
    if($servers{$name}) {
      return $servers{$name};
    } else {
      return undef;
    }
  } elsif($users{$name}) {
    # If its anything else, then it must be a user.
    return $users{$name};
  } else {
    return undef;
  }
}

# This only looks up users, in case you know exactly what you're
# looking for.
sub lookupuser {
  my $name = shift;
  my $dochase = shift;
  chomp $name;
  my $user = $users{$name};
  if($dochase && !defined($user)) {
    my $irclctarget = irclc($name);
    for(my $i=0;$i<=$#Utils::nickhistory;$i++) {
      last if (time-$Utils::nickhistory[$i]->{'time'}>15);
      if($irclctarget eq irclc($Utils::nickhistory[$i]->{'nick'})) {
	$user = $users{$Utils::nickhistory[$i]->{'newnick'}};
	last;
      }
    }
  }
  return $user;
}

# This only looks up channels
sub lookupchannel {
  my $name = shift;
  chomp $name;
  return $channels{$name};
}

# This only looks up servers.
sub lookupserver {
  my $name = shift;
  chomp $name;
  return $servers{$name};
}

sub users    { return \%users;    }
sub channels { return \%channels; }
sub servers  { return \%servers;  }

# Log something
sub syslog {
  my $data = shift;
  my $date = localtime();

  if(!$syslogsetup) {
    if($params{syslog}) {
      Sys::Syslog::openlog('pircd','ndelay,pid','daemon');
    } elsif($params{logfile}) {
      open(STDERR, ">>$params{logfile}") 
	or die "Unable to open $params{logfile}: $!";
    }
    $syslogsetup = 1;
  }

  if($params{syslog}) {
    unshift @_, $date;
    Sys::Syslog::syslog(@_);
  } else {
    print STDERR "$date: $data: ",shift,"\n";
  }
}

sub irclc ($) {
  my $data = shift;
  $data =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $data;
}

# Called when a line of input has been read from a connection. Given a class
# object, the line of input, and a ref to a hash of handler functions, parses
# out the command and data from the input line and calls the appropriate
# handler function. Updates the 'last_active' and 'ping_waiting' values on the
# class object. 
# The handler function is called with the given class object as the first
# argument, the entire given line as the second argument, and one additional
# argument for each (irc) argument on the given line.
sub do_handle {
    my($object, $line, $handlers)=(shift,shift,shift);
    my $command;
    my $args;
    my @arglist;
    my $func;
    my($foo,$bar);

    $object->{'last_active'} = time();
    undef $object->{'ping_waiting'};

    # The command that we key on is the first string of alphabetic
    #  characters (and _, but we'll ignore that)
    # note that we leave the leading whitespace in $args. the * after the space
    # character is just to make the regex still match an argumentless line.
    # since the \w+ greedily grabs everything up to a space, there will always
    # be a leading space in $args if $args is non-empty.
    ($command,$args)=$line =~ /^(\w+)( *.*)/;

    $func=$handlers->{uc($command)};

    if(defined($func)) {
	@arglist=();
	if(scalar(($foo,$bar)=split(/ +:/,$args,2))==2) {
	    # if an arg starts with a colon, the entire part of the line
	    # following the colon must be treated as a single arg
	    $args=$foo;
	    push @arglist, $bar;
	}
#	} else {
	    # we needed the leading whitespace on the first arg for the above
	    # check, but it'd just fuck the below split to hell, so if the
	    # check wasn't true, get rid of the whitespace.
	    $args=~s/^ +//;
#	}
	unshift @arglist,split(/ +/,$args);
#	print "arglist is ".join(':',@arglist)."\n";
        &{$func}($object,$line,@arglist);
    } elsif($line!~/^\s*$/) {
#       Utils::syslog('notice',"Received unknown command string '$line' from $$object{nick}");
        $object->sendnumeric($object->server,421,($command),"Unknown command");
    }
}

# returns 1 if the given string would be a valid irc nick, undef otherwise
sub validnick {
    my $str=shift;

    return undef if(length($str)<1 || length($str)>32);

    # valid characters given in rfc1459 2.3.1
    return undef if($str=~/[^A-Za-z0-9-\[\]\\\`\^\{\}\_]/);

    return 1;
}

1;
