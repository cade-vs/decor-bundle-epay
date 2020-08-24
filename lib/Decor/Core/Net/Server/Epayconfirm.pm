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
use Decor::Shared::Utils;
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

use parent qw( Decor::Core::Net::Server );

sub on_process_xt_message
{
  my $self = shift;
  my $mi   = shift;
  my $mo   = shift;
  my $socket = shift;


  my $xt = $mi->{ 'XT' };
  
  eval
  {
  return sub_confirm( $mi, $mo ) if uc $xt eq 'CONFIRM';
  die "unknown MESSAGE TYPE [$xt]\n";
  };
  if( $@ )
    {
    %$mo = ();
    $mo->{ 'XS'     } = "E_ERROR";
    $mo->{ 'XS_DES' } = $@;
    }

  return 1;
}

#-----------------------------------------------------------------------------

sub sub_confirm
{
  my $mi   = shift;
  my $mo   = shift;
  
  my $data      = uc $mi->{ 'DATA' };
  my $checksum  = uc $mi->{ 'CHECKSUM' };
  boom "empty DATA/CHECKSUM" if $data eq '' or $checksum eq '';

  my $epay_setup = $io->read_first1_hashref( 'EPAY_SETUP', '', { ORDERBY => '_ID DESC', LIMIT => 1 } );
  boom "cannot load EPAY_SETUP record" unless $epay_setup;
  
  my $secret_keyword = $epay_setup->{ 'KEYWORD' };

  my $hmac = hmac_hex( $data, $secret_keyword, \&sha1 );
  
  boom "invalid CHECKSUM" unless $hmac eq $checksum;

  my $ar = parse_ep_data( $data );
  
  my $res;
  my $io = new Decor::Core::DB::IO;
  for my $hr ( @$ar )
    {
    my $inv = $hr->{INVOICE};
    if( ! $io->read_first1_hashref( 'EPAY_CONFIRM', 'PAY_INVOICE = ?', { BIND => [ $inv ] } ) )
      {
      # NOTE: may have race condition but it is not expected epay to notify for the same invoice in parallel
      # NOTE: still damage will not be done if insert fails, epay will retry
      $io->insert( 'EPAY_CONFIRM', $hr );
      }
    $res .= "INVOICE=$inv:STATUS=OK\n";
    }
  
  $mo->{ 'RESULT' } = $res;
  $mo->{ 'XS'     } = 'OK';
}

#-----------------------------------------------------------------------------

my %EPAY_CONF_ATTR = (
                        INVOICE      => 1,
                        AMOUNT       => 1,
                        PAY_STATUS   => 1,
                        PAY_TIME     => 1,
                        STAN         => 1,
                        BCODE        => 1,
                        BIN          => 1,
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
      next unless $EPAY_CONF_ATTR{ $1 };
      $h{ $1 } = { $2 };
      }
    next unless exists $h{ 'INVOICE' } and $h{ 'STATUS' };
    if( $h{ 'PAY_TIME' } =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ )
      {
      $h{ 'PAY_TIME' } = type_revert( "$1-$2-$3T$4:$5:$6", { NAME => 'UTIME' } ); # ISO
      }
    else
      {
      delete $h{ 'PAY_TIME' };
      }  
    push @arr, \%h;   
    }
  
  return \@arr;
}


### EOF ######################################################################
1;
