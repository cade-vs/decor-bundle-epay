package epay_api;
use strict;

use MIME::Base64;
use Digest::SHA1 qw(sha1);
use Digest::HMAC qw(hmac_hex);
use Time::JulianDay;
use Encode qw( encode decode );

use Decor::Core::DB::Record;

###################################
sub prepare_payment_form {
	my $sum      = shift;
	my $descr    = shift;
	my $invoice  = shift;
	my $exp_date = shift || local_julian_day(time())+3;
	
	my ($year, $month, $day) = inverse_julian_day($exp_date);
	my $exp_date_txt   = "$day.$month.$year";  
	
	my $text;

	my $ep = new Decor::Core::DB::Record;

	$ep->select('EPAY_SETUP','_ID > 0',{'ORDERBY' => '_ID DESC'});
	die "!!!!!EPAY SETUP NOT FOUND!!!!" unless $ep->next();

	# XXX ePay.bg URL (https://demo.epay.bg/ if POST to DEMO system)
	my $submit_url = $ep->read('DEMO') ? 'https://demo.epay.bg/' : 'https://epay.bg/';
	# XXX Secret word with which merchant make CHECKSUM on the ENCODED packet
	my $secret     = $ep->read('KEYWORD');
	my $min        = $ep->read('MIN');
	my $url_ok     = $ep->read('URL_OK');
	my $url_cancel = $ep->read('URL_CANCEL');


my $data = <<DATA;
MIN=$min
INVOICE=$invoice
AMOUNT=$sum
EXP_TIME=$exp_date_txt
DESCR=$descr
DATA

	# XXX Packet:
	#     (MIN or EMAIL)=     REQUIRED
	#     INVOICE=            REQUIRED
	#     AMOUNT=             REQUIRED
	#     EXP_TIME=           REQUIRED
	#     DESCR=              OPTIONAL

	my $ENCODED  = encode_base64(encode('UTF-8', $data ), '');
	my $CHECKSUM = hmac_hex($ENCODED, $secret, \&sha1);

	$text .= qq[

	<form action="$submit_url" method=POST>
	<input type=hidden name=PAGE       value="paylogin">
	<input type=hidden name=ENCODED    value="$ENCODED">
	<input type=hidden name=CHECKSUM   value="$CHECKSUM">
	<input type=hidden name=URL_OK     value="$url_ok">
	<input type=hidden name=URL_CANCEL value="$url_cancel">

	<h2>[~Payment info]</h2>
	<center>
	<table class=view cellspacing=0 cellpadding=0> 
	<tr><td class='view-header'><b>[~Description]</b></td><td class='view-value'>$descr</td></tr>
	<tr><td class='view-header'><b>[~Invoice]</b></td><td class='view-value'>$invoice</td></tr>
	<tr><td class='view-header'><b>[~Amount]</b></td><td class='view-value'>$sum</td></tr>
	</table>
	<p>

	<input type="image" src="https://online.datamax.bg/epaynow/a03.gif" alt="Плащане on-line">
	</center>
	</form>
	];

	return $text;	
	
	
}



1;