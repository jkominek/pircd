#!/usr/bin/perl
# 
# IRCUniqueHash.pm
# Created: Wed Apr 21 09:44:03 1999 by jay.kominek@colorado.edu
# Revised: Wed Apr 21 09:59:55 1999 by jay.kominek@colorado.edu
# Copyright 1999 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use this file.
#
#####################################################################
# A hash class which enforces IRC-style unique name spaces
#####################################################################

package Tie::IRCUniqueHash;
use strict;

sub TIEHASH {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $this  = { };

  bless $this, $class;
  return $this;
}

sub FETCH {
  my $this = shift;
  my $key  = shift;

  return $this->{'data'}->{&irclc($key)};
}

sub STORE {
  my $this = shift;
  my($key,$value) = @_;

  $this->{'data'}->{&irclc($key)} = $value;
}

sub DELETE {
  my $this = shift;
  my $key  = shift;

  delete($this->{'data'}->{&irclc($key)});
}

sub CLEAR {
  my $this = shift;

  %{$this->{'data'}} = ( );
}

sub EXISTS {
  my $this = shift;
  my $key  = shift;

  return exists $this->{'data'}->{&irclc($key)};
}

sub FIRSTKEY {
  my $this = shift;

  keys %{$this->{'data'}};
  return each %{$this->{'data'}};
}

sub NEXTKEY {
  my $this = shift;
  my $lastkey = shift;

  return each %{$this->{'data'}};
}

sub irclc {
  my $str = shift;
  $str =~ tr/A-Z\[\]\\/a-z\{\}\|/;
  return $str;
}

1;
