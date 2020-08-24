#!/usr/bin/perl
##############################################################################
##
##  Decor application machinery core
##  2014-2020 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
##
##  This is custom http handler to process ePay.bg confirmations
##  It just redirects confirmation data to the core
##
##############################################################################
use strict;
use CGI;
use lib '/usr/local/decor/shared/lib';
use Decor::Shared::Net::Client;
use Data::Dumper;

my $data     = CGI::param('encoded');
my $checksum = CGI::param('checksum');

my $core = new Decor::Shared::Net::Client;
$core->connect( '127.0.0.1:42111', 'app1', { 'MANUAL' => 1 } );

my $res = $core->tx_msg( { XT => 'CONFIRM', 'DATA' => $data, 'CHECKSUM' => $checksum } );

print STDERR Dumper( $data, $checksum, $res );

my $res = $res->{ 'RESDATA' };

print "Content-type: text/plain\n\n$res\n";
