# Author:  <wblake@CB95043>
# Created: June 13, 2022
# Version: 0.01
#
# Usage: perl [-g] [-x] [-i] CircAPITest.pl item_file.csv
# -g Debug/verbose -q quiet
#
# Expects Input csv file with a header row
# itemid
# 
# Example First Two Lines of an Input File:
#
# ITEMID
# 21982030026524
#
#

#use 5.36.0;
use strict;
use diagnostics;
use integer;
use say;
use Getopt::Std;
use Log::Report mode=>'DEBUG';
use Data::Dumper ;
use Time::HiRes qw( gettimeofday tv_interval);
use Parallel::ForkManager;


# See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
use LWP::UserAgent;
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Transport::SOAPHTTP;
use MIME::Base64 'encode_base64';

use constant API_CHUNK_SIZE => 16;
use constant CARLX_ID_WB0=> 'wb0';
use constant USER_AUTH => 'frederick';
use constant PASS_AUTH => 'SwV3QEtjMwSs7fuL';
use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'CBA';
use constant ITEM_RETURN_DATE => '2022-06-15';
use constant WSDL_FILE => 'CirculationAPI.wsdl';

#Command line input variable handling
our ($opt_g,$opt_x,$opt_q);
getopts('gx:q');

#use if defined($opt_g), "Log::Report", mode=>'DEBUG';
#BEGIN { require Data::Dumper if defined($opt_g) }

 my $local_filename=$0;
 $local_filename =~ s/.+\\([A-z]+.pl)/$1/;
 
if ( defined($opt_g) ) {
     say "[$local_filename" . ":" . __LINE__ . "]Debug Mode $opt_g." ;
}

my $quiet_mode = 0;

if ( defined($opt_q)) {
     $quiet_mode =1 ;
     say "[$local_filename" . ":" . __LINE__ . "]Quiet Mode $quiet_mode." ;
}

#Time::HiRes qw( gettimeofday tv_interval) related variables
my $t0;
my $elapsed;

# Authentication
my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);   

sub basic_auth($$)
{   my ($request, $trace) = @_;
    
    $request->authorization_basic(USER_AUTH, PASS_AUTH);
    $ua->request($request);     # returns $response
}

# Results and trace from XML::Compile::WSDL et al.
#my %CheckinItemRequest;

my %CheckinItemRequest = (
 ItemID => '',
 Alias=>CARLX_ID_WB0,
 ReturnDate=>ITEM_RETURN_DATE,
     Modifiers=> {
        InstitutionCode=>INSTITUTE_CODE,
        StaffID=>CARLX_ID_WB0,
        EnvBranch=>FCPL_BRANCH,
        DebugMode=>1,
        ReportMode=>0,
        Projection=>'Brief',
        RequestOrigin=>1
        }
             );

my $wsdl = XML::Compile::WSDL11->new(WSDL_FILE);
my $trans = XML::Compile::Transport::SOAPHTTP
    ->new(timeout => 500, address => $wsdl->endPoint);
    
unless (defined $wsdl)
{  die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}
          
$wsdl->compileCalls(user_agent => $ua, transport_hook =>\&basic_auth);
 

my $call1 = $wsdl->compileClient('CheckinItem',
  transport_hook => \&basic_auth);
my $call2 = $wsdl->compileClient('CheckoutItem', 
  transport_hook => \&basic_auth);

unless ((defined $call1) && (defined $call2) )
  { die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1, $call2\n" ;}

  say "[$local_filename" . ":" . __LINE__ . "] ARGV[0] $ARGV[0] " ;
 
# Use wc -l to get line count of input file $ARGV[0]
  my $nr = qx/wc -l $ARGV[0]/ ;
  if ($? != 0) {
    die "[$local_filename" . ":" . __LINE__ . "]shell returned $?";
  }
  
  $nr =~ s/^([0-9]+).*/$1/;
  chomp($nr);
  
  #[$local_filename" . ":" . __LINE__ . "]DBI Call lapsed time $elapsed."
  my $num_chunks = $nr/API_CHUNK_SIZE;
  my $mods = $nr%API_CHUNK_SIZE;
  
  say "[$local_filename" . ":" . __LINE__ . "]Linecount " . $nr . " Burst Size " . API_CHUNK_SIZE . " Bursts " . $num_chunks . " Mod " . $mods;
  
  my (@items) ;
  my $pid;

  # Results and trace from XML::Compile::WSDL et al.
  my (@result1,@trace1);
  
  # Read the input file and ignore the first line having column headings
  $_ = <>;
  chomp;
   my $pm =  new Parallel::ForkManager(API_CHUNK_SIZE);
     
  for (my $current_block=0; $current_block<$num_chunks;$current_block++ )
  {
    if ($quiet_mode==0) {
    say "[$local_filename" . ":" . __LINE__ . "]Burst $current_block";
    }
    #time the operation length in seconds
    #$t0 = [gettimeofday]; 
    for my $current_line (0..API_CHUNK_SIZE-1)
    {
     say " [$local_filename" . ":" . __LINE__ . "]Current line " . ($current_block * API_CHUNK_SIZE + $current_line + 1);
     $_ = <>;
     next if ( (not defined $_ ) || ($_=~/^ *$/) || ($_ =~/^\s*$/));
     chomp ;
    ($items[$current_line] ) = $_ ;
    }
    for (my $current_line=0; $current_line<API_CHUNK_SIZE; $current_line++)
      {
        $pid = $pm->start and next;
    
       ($items[$current_line] ) = $_ ;
    
       $CheckinItemRequest{ItemID}=$items[$current_line] ;
    
       ($result1[$current_line],$trace1[$current_line]) = $call1->(%CheckinItemRequest);
       
        if ( $quiet_mode == 0) {    
          say "[$local_filename" . ":" . __LINE__ . "]Burst $current_block proc $current_line API returned";
        }
        my $MyResponseStatusCode = ($result1[$current_line]->{CheckinItemResponse}->{ResponseStatuses}->{cho_ResponseStatus}[0]->{ResponseStatus}->{Code});
        #say "[$local_filename" . ":" . __LINE__ . "]MyResponseStatusCode " . $MyResponseStatusCode ;
       
        if ( defined($opt_g) ) {
           say "[$local_filename" . ":" . __LINE__ . "]Debug Mode $opt_g." ;
           $pm->finish (0,  {entry_line=>$current_line,result=>\$MyResponseStatusCode});
         }
        else {
          $pm->finish;
         }
            if ( $quiet_mode==0) {   
         say "[$local_filename" . ":" . __LINE__ . "]Burst $current_block waiting...";
        }
       $pm->wait_all_children;
       if ( $quiet_mode==0) {
        say "[$local_filename" . ":" . __LINE__ . "]Burst $current_block finished...";
       }
     } # end for (my $current_line=0; $current_line<API_CHUNK_SIZE; $current_line++)
  } # end for (my $current_block=0; $current_block<$num_chunks;$current_block++ )
  
   # Remaining Items after dividing into API_CHUNK_SIZE bursts 
  for ( my $mod_line=0; $mod_line<$mods; $mod_line++)
  {
   if ($quiet_mode==0) {
    say "[$local_filename" . ":" . __LINE__ . "]Mod Line $mod_line";
    }
   $_=<>;
   say "[$local_filename" . ":" . __LINE__ . "]Input $_";
    next if ( (not defined $_ ) || ($_=~/^ *$/) || ($_ =~/^\s*$/));
    chomp;
    
    ($items[$mod_line]) = $_;
    say "[$local_filename" . ":" . __LINE__ . "]Input $_  items $items[$mod_line]";
   }
  
  for ( my $mod_line=0; $mod_line<$mods; $mod_line++ )
  {
    $pid = $pm->start and next;
    if ($quiet_mode==0) {
    say("[$local_filename" . ":" . __LINE__ . "]Parallel Fork Mod proc $mod_line items[mod_line] " . $items[$mod_line]);
    }
   
    $CheckinItemRequest{ItemID}=$items[$mod_line] ;
  
    ($result1[$mod_line],$trace1[$mod_line]) = $call1->(%CheckinItemRequest);
    
    if ($quiet_mode==0) {
      say "[$local_filename" . ":" . __LINE__ . "]Forked modline $mod_line CheckinItem request returned";
     }
    my $MyResponseStatusCode = ($result1[$mod_line]->{CheckinItemResponse}->{ResponseStatuses}->{cho_ResponseStatus}[0]->{ResponseStatus}->{Code});
    
    if ( defined($opt_g) ) {
     say "[$local_filename" . ":" . __LINE__ . "]MyResponseStatusCode " . $MyResponseStatusCode ;
     if ($trace1[$mod_line]->errors) {
          say "[$local_filename" . ":" . __LINE__ . "]trace error. Request: " . $trace1[$mod_line]->printRequest ; 
          say "[$local_filename" . ":" . __LINE__ . "]trace error. Response: " . $trace1[$mod_line]->printResponse ;
          say "[$local_filename" . ":" . __LINE__ . "]trace error. Timings: " . $trace1[$mod_line]->printTimings ;
          say "[$local_filename" . ":" . __LINE__ . "]trace error " . Dumper $trace1[$mod_line] ;
          say "[$local_filename" . ":" . __LINE__ . "]trace error " . Dumper $result1[$mod_line] ;
          exit;
    }
       $pm->finish (0,   {entry_line=>$mod_line, result=>\$MyResponseStatusCode});
     }
     else {
      $pm->finish;
      } 
  if ($quiet_mode==0) {
   say "[$local_filename" . ":" . __LINE__ . "]mod_line waiting children...";
  }
  $pm->wait_all_children;
  
    if ( $quiet_mode==0 )   {
    say "[$local_filename" . ":" . __LINE__ . "]mod_line finished";
    }
   #$elapsed = tv_interval ($t0) ;
   #say ("[$local_filename" . ":" . __LINE__ . "]Parallel Fork Call lapsed time $elapsed.");
  } #end for ( my $mod_line=0; $mod_line<$mods; $mod_line++ )

  