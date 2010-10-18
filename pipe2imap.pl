#!/usr/bin/perl

##############################################################################
#                                                                            #
# Copyright 2009, Mike Cardwell [https://secure.grepular.com/]               #
#                                                                            #
# This program is free software; you can redistribute it and/or modify       #
# it under the terms of the GNU General Public License as published by       #
# the Free Software Foundation; either version 2 of the License, or          #
# any later version.                                                         #
#                                                                            #
# This program is distributed in the hope that it will be useful,            #
# but WITHOUT ANY WARRANTY; without even the implied warranty of             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              #
# GNU General Public License for more details.                               #
#                                                                            #
# You should have received a copy of the GNU General Public License          #
# along with this program; if not, write to the Free Software                #
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA #
#                                                                            #
##############################################################################

our $VERSION = '1.01';

use strict;
use warnings;
use IMAP::Client;

my @exit_codes = (
   'Success',
   'Bad args',
   'Missing required args',
   'IMAP connection failure',
   'IMAP login failure',
   'Failed to select imap folder',
   'Failed to append message',
   'Failed to create imap folder',
   'Failed to read password from passfile',
   'Failed to subscribe to folder',
);

if( int(@ARGV) == 0 || grep( /^(-h|--help)$/i, @ARGV ) ){
   print "Example:\n";
   print "   cat email.txt|pipe2imap.pl --user username --pass password --folder \"INBOX\"\n\n";
   print "Required arguments:\n";
   print "   --user username         : The username to log in to IMAP with\n";
   print "   --pass password         : The password to log in to IMAP with\n";
   print "   --passfile path         : Path to a file containing the password. Can be used instead of --pass\n";
   print "   --folder folder         : Folder to write to\n\n";
   print "Optional arguments:\n";
   print "   --debug num             : Set a debug level from 1-9\n";
   print "   --ssl or --tls          : If you don't choose one of these it defaults to an\n";
   print "                           : unencrypted connection\n";
   print "   --host ip.address       : Defaults to 127.0.0.1\n";
   print "   --port port             : Defaults to 143 or 993 depending on ssl/tls\n";
   print "   --authas user           : To authenticate as a user other than the one in\n";
   print "                           : --user (If this doesn't make sense to you, you\n";
   print "                           : don't need it)\n"; 
   print "   --create u1=p1 u2=p2    : If this is set, the destination folder is created if\n";
   print "                           : it doesn't already exist. There are 0 or more optional\n";
   print "                           : args which define standard imap acls. Eg: \"mike=lr\"\n";
   print "                           : would give user mike read permissions.\n";
   print "   --create-subscribe      : Subscribe to the folder created by the --create option\n";
   print "   --flags flag1 flag2 ... : Set the message flags, eg \\seen or Junk\n";
   print "   --quiet                 : Don't print results to STDOUT\n";
   print "\n";
   print "Exit codes:\n";
   print "   $_ - $exit_codes[$_]\n" for 0..$#exit_codes;   
   exit 0;
}

## Parse the arguments
  my %options;
  {
     my @req = qw( user folder );
     my @opt = qw( create create-subscribe debug host port ssl tls authas flags quiet pass passfile );
     
     my @arg = @ARGV;
     while( @arg ){
        my $key = shift @arg;
        if( $key =~ /^--(.+)$/ ){
           $key = $1;

           fin(1) unless grep($key eq $_, @req, @opt, );

  	   my @values = @{$options{$key}||[]};
           push @values, shift @arg while( int(@arg) && $arg[0]!~/^--/ );
	   push @values, 1 unless int(@values);
	   $options{$key}=\@values;
        } else {
           fin(1);
        }
     }

     fin(2) unless exists $options{pass} || $options{passfile};
     foreach my $key ( @req ){
        fin(2) unless exists $options{$key};
     }
  }

my $pass;
if( $options{passfile} ){
   open my $in, '<', $options{passfile}[0] or fin(8);
   chomp( $pass = <$in> );
   close $in;
} else {
   $pass = $options{pass}[0];
}

my $user   = $options{user}[0];
my $folder = $options{folder}[0];
my $connect_methods = exists $options{ssl} ? 'SSL' : exists $options{tls} ? 'STARTTLS' : 'PLAIN';

## Connect via IMAP
  my $imap;
  {
     my %args = ( ConnectMethod => $connect_methods );
     $args{PeerAddr} = exists $options{host} ? $options{host}[0] : '127.0.0.1';
     if( exists $options{port} ){
        $args{IMAPPort}  = $options{port}[0];
        $args{IMAPSPort} = $options{port}[0];
     }     

     $imap = new IMAP::Client();
     $imap->debuglevel( $options{debug}[0] ) if exists $options{debug};
     $imap->connect( %args ) or fin(3);
     if( exists $options{authas} ){
        $imap->authenticate( $user, $pass, $options{authas}[0] ) or fin(4);
     } else {	
        $imap->login( $user, $pass, ) or fin(4);
     }
  }

## Select the folder
  {
     unless( $imap->select( $folder ) ){
        if( exists $options{create} ){
           if( $imap->create( $folder ) ){
              foreach( @{$options{create}} ){
                 next unless /^(.+)=(.+)$/;
                 $imap->setacl( $folder, $1, $2, );
              }
              fin(5) unless $imap->select( $folder );
              if( exists $options{'create-subscribe'} ){
                 fin(9) unless $imap->subscribe( $folder );
              }
           } else {
              fin(7);
           }
        } else {
           fin(5);
        }
     }
  }

## Append the message
  {
     my $message;
     {
        local $/ = undef;
	$message = <STDIN>;
        $message =~ s/^From( \S+){5} \d+\r?\n//;
     }

     my $flags = '('.join(' ',@{$options{flags}||[]}).')';
     if( $imap->append( $folder, $message, $flags, ) ){
        $imap->close;
        fin(6);
     }
  }

## Success
  $imap->close;
  fin(0);

sub fin {
   my $code = shift;

   warn $exit_codes[$code]."\n" unless exists $options{quiet};
   exit $code;
}
