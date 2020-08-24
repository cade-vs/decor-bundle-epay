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
##  This is custom server module to process ePay.bg confirmations
##  Decor app environment is preloaded. 
##  Check DECOR_ROOT/core/bin/decor-core-app-server.pl
##
##  To run this server module:
##
##  ./decor-core-app-server.pl -e app1 -u EPayConfirm
##
##  For more information, check docs/custom-server-modules.txt
##
##############################################################################
package Decor::Core::Net::Server::Epayconfirm;
use strict;
use Exception::Sink;
use Decor::Core::Subs;
use Decor::Core::Log;
use Decor::Shared::Utils;
use Decor::Shared::Types;
use Decor::Core::Env;
use Decor::Core::Log;
use Decor::Core::DB::Record;
use Decor::Core::Subs::Env;
use Decor::Core::Profile;
use Decor::Core::Describe;
use Decor::Core::Menu;
use Decor::Core::Code;
use Decor::Core::DSN;

use MIME::Base64;
use Digest::SHA1 qw( sha1 );
use Digest::HMAC qw( hmac_hex );
use Data::Dumper;

use parent qw( Decor::Core::Net::Server );

sub on_process_xt_message
{
  my $self = shift;
  my $mi   = shift;
  my $mo   = shift;
  my $socket = shift;


  my $xt = $mi->{ 'XT' };
  
  return sub_confirm( $mi, $mo ) if uc $xt eq 'CONFIRM';
  die "E_UNKNOWNMESSAGE: unknown MESSAGE TYPE [$xt]\n";

  return 1;
}

#-----------------------------------------------------------------------------

sub sub_confirm
{
  my $mi   = shift;
  my $mo   = shift;
  
  my $data      =    $mi->{ 'DATA' };
  my $checksum  = uc $mi->{ 'CHECKSUM' };
  boom "empty DATA/CHECKSUM" if $data eq '' or $checksum eq '';

  my $io = new Decor::Core::DB::IO;

  my $epay_setup = $io->read_first1_hashref( 'EPAY_SETUP', '', { ORDERBY => '_ID DESC', LIMIT => 1 } );
  boom "E_EPAYSETUP: cannot load EPAY_SETUP record" unless $epay_setup;
  
  my $secret_keyword = $epay_setup->{ 'KEYWORD' };

  my $hmac = uc hmac_hex( $data, $secret_keyword, \&sha1 );

  print STDERR Dumper( $data, $secret_keyword, "$hmac eq $checksum" );
  
  boom "E_CHECKSUM: invalid CHECKSUM" unless $hmac eq $checksum;

  $data = decode_base64( $data );

  my $ar = parse_ep_data( $data );

  print STDERR Dumper( $data, $secret_keyword, $data, $ar );
  
  my $res;
  for my $hr ( @$ar )
    {
    my $inv = $hr->{INVOICE};
    if( ! $io->read_first1_hashref( 'EPAY_CONFIRM', 'INVOICE = ?', { BIND => [ $inv ] } ) )
      {
      # NOTE: may have race condition but it is not expected epay to notify for the same invoice in parallel
      # NOTE: still damage will not be done if insert fails, epay will retry
      $io->insert( 'EPAY_CONFIRM', $hr );
      }
    $res .= "INVOICE=$inv:STATUS=OK\n";
    }
  
  $mo->{ 'RESULT_DATA' } = $res;
  $mo->{ 'XS'     } = 'OK';
}

#-----------------------------------------------------------------------------

my %EPAY_CONF_ATTR = (
                        STATUS       => 'PAY_STATUS',
                        INVOICE      => 'INVOICE',
                        AMOUNT       => 'AMOUNT',
                        PAY_TIME     => 'PAY_TIME',
                        STAN         => 'STAN',
                        BCODE        => 'BCODE',
                        BIN          => 'BIN',
                     );

sub parse_ep_data
{
  my $data = shift;

  my @arr;
  
  my @data = split( /\n+/, $data );
  
  
LINE: for my $line ( @data )
    {
    my %h;
    my @line = split( /:/, $line );
    for my $attr ( @line )
      {
      next LINE unless $attr =~ /([A-Z_0-9]+)=(.+)/;
      next unless exists $EPAY_CONF_ATTR{ uc $1 };
      $h{ $EPAY_CONF_ATTR{ uc $1 } } = $2;
      }
    print STDERR "\n\nnext unless exists $h{ 'INVOICE' } and exists $h{ 'STATUS' }\n\n";
    next unless exists $h{ 'INVOICE' } and exists $h{ 'PAY_STATUS' };
    print STDERR "\n\nnext unless exists $h{ 'INVOICE' } and exists $h{ 'STATUS' } ++++++++++ OK \n\n";
    if( $h{ 'PAY_TIME' } =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ )
      {
      $h{ 'PAY_TIME' } = type_revert( "$1-$2-$3T$4:$5:$6", { NAME => 'UTIME' } ); # ISO
      }
    else
      {
      delete $h{ 'PAY_TIME' };
      }  
    print STDERR "\n\nOK OK OK PUSH ARR++++++++++++++++++++\n\n";
    push @arr, \%h;   
    }
  
  return \@arr;
}


### EOF ######################################################################
1;
