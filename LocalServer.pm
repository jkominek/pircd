#!/usr/bin/perl
# 
# LocalServer.pm
# Created: Sat Sep 26 18:11:12 1998 by jay.kominek@colorado.edu
# Revised: Fri Mar  9 12:47:25 2001 by jay.kominek@colorado.edu
# Copyright 1998 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# Local Server object for The Perl Internet Relay Chat Daemon
#####################################################################

package LocalServer;
use User;
use Channel;
use Server;
use strict;
use Utils;
use vars qw(@ISA $VERSION);
use UNIVERSAL qw(isa);
@ISA=qw{Server};

use Tie::IRCUniqueHash;

$VERSION=$Utils::VERSION;

###################
# CLASS CONSTRUCTOR
###################

# Pass it the name of its configuration file

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  $this->{'conffile'} = shift || "server.conf";

  my(%opertmp,%usertmp,%childtmp);
  tie %opertmp,  'Tie::IRCUniqueHash';
  $this->{'opers'}    = \%opertmp;
  tie %usertmp,  'Tie::IRCUniqueHash';
  $this->{'users'}    = \%usertmp;
  tie %childtmp, 'Tie::IRCUniqueHash';
  $this->{'children'} = \%childtmp;

  $this->{'version'} = $Utils::VERSION;

  &loadconffile($this);

  bless($this, $class);
  return $this;
}

sub loadconffile {
  my $this = shift;

  # Clear everything out so that if things have been removed from
  # the configuration file, they actually disappear.
  $this->{'opers'} = { };
  $this->{'klines'} = [ ];
  $this->{'connections'} = { };
  $this->{'nets'} = { };
  $this->{'motd'} = [undef];
  $this->{'admin'} = [undef,undef,undef];
  $this->{'mechanics'} = { PINGCHECKTIME => 90,
                           PINGOUTTIME => 90,
                           FLOODOFFBYTES => 1,
                           FLOODOFFLINES => 10 };

  open(CONF,$this->{'conffile'});
  my @lines = <CONF>;
  close(CONF);
  my $line;
  my $i = 0;
 CONFPARSE: foreach $line (@lines) {
    $i++;
    chomp($line);

    # Machine line
    if($line =~ /^M:([\w\d\.]+):\*:([^:]+):(\d+)/) {
      $this->{'name'}        = $1;
      $this->{'description'} = $2;
      $this->{'port'}        = $3;
      next CONFPARSE;
    }
    # Admin line
    if($line =~ /^A:([^:]+):([^:]+):([^:]+)/) {
      @{$this->{'admin'}} = ($1,$2,$3);
      next CONFPARSE;
    }
    # MOTD line
    if($line =~ /^MOTD:(.+)$/) {
      if(open(MOTD,$1)) {
	@{$this->{'motd'}} = <MOTD>;
	close(MOTD);
	chomp(@{$this->{'motd'}});
      } else {
	@{$this->{'motd'}} = ($1);
      }
      next CONFPARSE;
    }
    # OPER line
    if($line =~ /^O:([^:]+):([^:]+):([^:]+)$/) {
      my($nick,$mask,$password) = ($1,$2,$3);
      $mask =~ s/\./\\\./g;
      $mask =~ s/\?/\./g;
      $mask =~ s/\*/\.\*/g;
      $this->{'opers'}->{ $nick }->{'mask'} = $mask;
      $this->{'opers'}->{ $nick }->{'password'} = $password;
      next CONFPARSE;
    }
    # Port line
    if($line =~ /^P:([^:]+):([^:]+)$/) {
      if($2) {
	# SSL socket
	push @{ $this->{'sslports'} }, $1;
      } else {
	# Normal socket
	push @{ $this->{'ports'} }, $1;
      }
      next CONFPARSE;
    }
    # Kill Line
    if($line =~ /^(I?)K:([^:]+):([^:]+):([^.]+)$/) {
      my($inverse,$mask,$reason,$usermask) = ($1,$2,$3,$4);
      $mask =~ s/\./\\\./g;
      $mask =~ s/\?/\./g;
      $mask =~ s/\*/\.\*/g;
      $usermask =~ s/\./\\\./g;
      $usermask =~ s/\?/\./g;
      $usermask =~ s/\*/\.\*/g;
      $inverse = ($inverse eq 'I');
      push @{ $this->{'klines'} }, [$inverse,$usermask,$mask,$reason];
      next CONFPARSE;
    }
    # Connection Line
    if($line =~ /^C:([^:]+):([^:]+):([^:]+):?(\d*)$/) {
      my($server,$address,$password,$port) = ($1,$2,$3,$4 || 0);
      $this->{'connections'}->{$server} = [$server,$address,$password,$port];
      next CONFPARSE;
    }
    # Network Line
    if($line =~ /^N:([^:]+):([^:]+):([^:]+)$/) {
      my($server,$address,$password) = ($1,$2,$3);
      $this->{'nets'}->{$server}     = [$server,$address,$password];
      next CONFPARSE;
    }
    # Mechanics Line
    if($line =~ /^MECH:(\d+)?:(\d+)?:(\d+)?:(\d+)?$/) {
      my($pc,$po,$fb,$fl) = ($1,$2,$3,$4);
      if(!defined($pc)) { $pc = $this->{'mechanics'}->{PINGCHECKTIME}; }
      if($pc < 0) { die('Bad ping check time in mechanics line'); }
      if(!defined($po)) { $po = $this->{'mechanics'}->{PINGOUTTIME}; }
      if($po <= 0) { die('Bad ping out time in mechanics line'); }
      if(!defined($fb)) { $fb = $this->{'mechanics'}->{FLOODOFFBYTES}; }
      if($fb <= 0) { die('Bad flood bytes in mechanics line'); }
      if(!defined($fl)) { $fl = $this->{'mechanics'}->{FLOODOFFLINES}; }
      if($fl <= 0) { die('Bad flood lines time in mechanics line'); }
      $this->{'mechanics'} = { PINGCHECKTIME => $pc,
                               PINGOUTTIME => $po,
                               FLOODOFFBYTES => $fb,
                               FLOODOFFLINES => $fl };
      next CONFPARSE;
    }
    die('Line '.$i.' in '.$this->{'conffile'}.' invalid.');
  }
}

# Things That Do Things

sub rehash {
  my($this,$from)=(shift,shift);
  my $user;

  foreach $user (values(%{$this->{'users'}})) {
    if($user->ismode('s')) {
      $user->privmsgnotice("NOTICE",$this,"*** Notice -- ".$from->{nick}." is rehashing Server config file");
    }
  }
  &loadconffile($this);
}

sub opernotify {
  my $this = shift;
  my $msg  = shift;

  my $user;
  foreach $user (values(%{$this->{'users'}})) {
    if($user->ismode('o')) {
      $user->privmsgnotice("NOTICE",$this,"*** Notice --- $msg");
    }
  }
  Utils::syslog('info',$msg);
}

############################
# DATA ACCESSING SUBROUTINES
############################

# Provides the name of this IRC server
sub name {
  my $this = shift;
  return $this->{'name'};
}

sub description {
  my $this = shift;
  return $this->{'description'};
}

sub users {
  my $this = shift;
  my @foo = values(%{$this->{'users'}});
  return @foo;
}

sub children {
  my $this = shift;
  my @foo  = values(%{$this->{'children'}});
  return @foo;
}

sub parent {
  # We're the local server. We don't have a parent
  # (from our perspective)
  return undef;
}

sub hops {
  return 0;
}

sub creation {
  return time();
}

# Returns the MOTD of the server as an array of lines.
sub getmotd {
  my $this = shift;
  return @{$this->{'motd'}};
}

# Same thing as getmotd, except for the admin information
sub getadmin {
  my $this = shift;
  return @{$this->{'admin'}} if defined $this->{'admin'};
  return ('','','');
}

sub getopers {
  my $this = shift;
  my @foo = keys %{$this->{'opers'}};
  return $this->{'opers'};
}

sub lookupconnection {
  my $this   = shift;
  my $server = shift;
  return $this->{'connections'}->{$server};
}

sub lookupnetwork {
  my $this   = shift;
  my $server = shift;
  return $this->{'nets'}->{$server};
}

###############################
# DATA MANIPULATING SUBROUTINES
###############################

sub adduser {
  my $this = shift;
  my $user = shift;
  $this->{'users'}->{$user->nick()} = $user;
}

sub removeuser {
  my $this = shift;
  my $user = shift;

  my $nick;
  if(ref($user)) {
    $nick = $user->nick();
  } else {
    $nick = $user;
  }

  delete($this->{'users'}->{$nick});
}

sub addchildserver {
  my $this  = shift;
  my $child = shift;
  $this->{'children'}->{$child->name()} = $child;
}

sub removechildserver {
  my $this  = shift;
  my $child = shift;

  my $name;
  if(ref($child)) {
    $name = $child->name();
  } else {
    $name = $child;
  }
  delete($this->{'children'}->{$name});
}

1;
