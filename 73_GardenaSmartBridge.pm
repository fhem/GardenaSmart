###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#  
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#
###### Wichtige Notizen
#
#   apt-get install libio-socket-ssl-perl
#   http://www.dxsdata.com/de/2016/07/php-class-for-gardena-smart-system-api/
#   
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
use Data::Dumper;   #debugging

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";
###todo Hier fehlt noch Modulabfrage für ssl


my $version = "0.0.29";




# Declare functions
sub GardenaSmartBridge_Attr(@);
sub GardenaSmartBridge_Define($$);
sub GardenaSmartBridge_Initialize($);
sub GardenaSmartBridge_Set($@);
sub GardenaSmartBridge_Write($@);
sub GardenaSmartBridge_Undef($$);
sub GardenaSmartBridge_ResponseProcessing($$);
sub GardenaSmartBridge_ErrorHandling($$$);
sub GardenaSmartBridge_encrypt($);
sub GardenaSmartBridge_decrypt($);
sub GardenaSmartBridge_WriteReadings($$);
sub GardenaSmartBridge_ParseJSON($$);
sub GardenaSmartBridge_getDevices($);
sub GardenaSmartBridge_getToken($);
sub GardenaSmartBridge_InternalTimerGetDeviceData($);




sub GardenaSmartBridge_Initialize($) {

    my ($hash) = @_;

    
    # Provider
    $hash->{WriteFn}    = "GardenaSmartBridge_Write";
    $hash->{Clients}    = ":GardenaSmartDevice:";
    $hash->{MatchList}  = { "1:GardenaSmartDevice"      => '^{"id":".*' };
    
    
    # Consumer
    $hash->{SetFn}      = "GardenaSmartBridge_Set";
    $hash->{DefFn}      = "GardenaSmartBridge_Define";
    $hash->{UndefFn}    = "GardenaSmartBridge_Undef";
    
    $hash->{AttrFn}     = "GardenaSmartBridge_Attr";
    $hash->{AttrList}   = "debugJSON:0,1 ".
                          "disable:1 ".
                          "interval ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{GardenaSmartBridge}{defptr}}) {
    
        my $hash = $modules{GardenaSmartBridge}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub GardenaSmartBridge_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <NAME> GardenaSmartBridge <Email> <Passwort>" if( @a != 4 ) ;
    return "Cannot define Gardena Bridge device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my $name                = $a[0];
    my $user                = $a[2];
    my $pass                = $a[3];
    $hash->{BRIDGE}         = 1;
    $hash->{URL}            = 'https://sg-api.dss.husqvarnagroup.net/sg-1';
    $hash->{VERSION}        = $version;
    $hash->{INTERVAL}       = 300;
    
    my $username            = GardenaSmartBridge_encrypt($user);
    my $password            = GardenaSmartBridge_encrypt($pass);
    Log3 $name, 3, "GardenaSmartBridge ($name) - encrypt $user/$pass to $username/$password" if($user ne $username || $pass ne $password);
    $hash->{DEF} = "$username $password";
    
    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    


    $attr{$name}{room} = "GardenaSmart" if( !defined( $attr{$name}{room} ) );
    
    readingsSingleUpdate($hash,'state','initialized',1);
    readingsSingleUpdate($hash,'token','none',1);
    Log3 $name, 3, "GardenaSmartBridge ($name) - defined GardenaSmartBridge and crypt your credentials";

    
    if( $init_done ) {
    
        GardenaSmartBridge_getToken($hash);
        readingsSingleUpdate($hash,'state','get token',1);
        
    } else {
    
        InternalTimer( gettimeofday()+15, "GardenaSmartBridge_getToken", $hash, 0 );
    }
    
    
    $modules{GardenaSmartBridge}{defptr}{BRIDGE} = $hash;

    return undef;
}

sub GardenaSmartBridge_Undef($$) {

    my ( $hash, $arg ) = @_;


    RemoveInternalTimer($hash);
    delete $modules{GardenaSmartBridge}{defptr}{BRIDGE} if( defined($modules{GardenaSmartBridge}{defptr}{BRIDGE}) );

    return undef;
}

sub GardenaSmartBridge_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "inactive", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "inactive", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            $hash->{INTERVAL}   = $attrVal;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "GardenaSmartBridge ($name) - set interval: $attrVal";
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL}   = 300;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "GardenaSmartBridge ($name) - delete User interval and set default: 300";
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
        }
    }

    return undef;
}

sub GardenaSmartBridge_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    
    if( lc $cmd eq 'getdevicesstate' ) {
    
        GardenaSmartBridge_getDevices($hash);
        
    } elsif( lc $cmd eq 'gettoken' ) {
    
        return "token is up to date" if( defined($hash->{helper}{session_id}) );
        GardenaSmartBridge_getToken($hash);
    
    } else {
    
        my $list = "getDevicesState:noArg getToken:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub GardenaSmartBridge_InternalTimerGetDeviceData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    if( not IsDisabled($name) ) {
    
        GardenaSmartBridge_getDevices($hash);
        Log3 $name, 4, "GardenaSmartBridge ($name) - set internal timer function for recall InternalTimerGetDeviceData sub";
        
    } else {
    
        readingsSingleUpdate($hash,'state','disabled',1);
        Log3 $name, 3, "GardenaSmartBridge ($name) - device is disabled";
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL},"GardenaSmartBridge_InternalTimerGetDeviceData", $hash, 1 );
}

sub GardenaSmartBridge_Write($@) {

    my ($hash,$payload,$deviceId,$model)  = @_;
    my $name                        = $hash->{NAME};
    
    my $session_id                  = $hash->{helper}{session_id};
    my $header                      = "Content-Type: application/json";
    my $uri                         = '';
    my $method                      = 'POST';
    $header                         .= "\r\nX-Session: $session_id"                                         if( defined($hash->{helper}{session_id}) );
    $payload                        = '{' . $payload . '}'                                                  if( defined($payload) );
    $payload                        = '{}'                                                                  if( not defined($payload) );


    if( $payload eq '{}' ) {
        $method                         = 'GET';
        $uri                            .= '/locations/?user_id=' . $hash->{helper}{user_id}                if( not defined($hash->{helper}{locations_id}) );
            readingsSingleUpdate($hash,'state','fetch locationId',1)                                        if( not defined($hash->{helper}{locations_id}) );
        $uri                            .= '/sessions'                                                      if( not defined($hash->{helper}{session_id}));
        $uri                            .= '/devices'                                                       if( not defined($model) and defined($hash->{helper}{locations_id}) );
    }
    
    $uri                            .= '/sessions'                                                          if( not defined($hash->{helper}{session_id}));
    
    if( defined($hash->{helper}{locations_id}) ) {
        $uri                            .= '/devices/' . $deviceId . '/abilities/' . $model . '/command'    if( defined($model) and defined($payload) );
        $uri                            .= '?locationId=' . $hash->{helper}{locations_id};
    }

    
    HttpUtils_NonblockingGet(
        {
            url         => $hash->{URL} . $uri,
            timeout     => 15,
            hash        => $hash,
            device_id   => $deviceId,
            data        => $payload,
            method      => $method,
            header      => $header,
            doTrigger   => 1,
            callback    => \&GardenaSmartBridge_ErrorHandling
        }
    );

    Log3 $name, 4, "GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: $header, DATA: $payload, METHOD: $method";
}

sub GardenaSmartBridge_ErrorHandling($$$) {

    my ($param,$err,$data)    = @_;
    
    my $hash                        = $param->{hash};
    my $name                        = $hash->{NAME};


    ###todo Das gesamte Errorhandling muss hier noch rein
    
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Header:\n".Dumper($param->{header});
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Error:\n".Dumper($err);
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Data:\n".Dumper($data);
    
    
    
    
    #### Ein Fehler der Behandelt werden muss
   # '<html>
   #     <head>
   #         <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
   #         <title>Error 400 Bad Request</title>
   #     </head>
   #     <body><h2>HTTP ERROR 400</h2>
   #         <p>Problem accessing /sg-1/devices/2ad0d816-8bc3-4f0a-8c52-8b0dc8d7b2ec/abilities/watering_computer/command. Reason:
   #         <pre>    Bad Request</pre></p><hr><i><small>Powered by Jetty://</small></i><hr/>
   #
   #     </body>
   # </html>
   # ';
    


    readingsSingleUpdate($hash,'state','connect to cloud',1) if( defined($hash->{helper}{locations_id}) );
    GardenaSmartBridge_ResponseProcessing($hash,$data);

}

sub GardenaSmartBridge_ResponseProcessing($$) {

    my ($hash,$json)    = @_;
    
    my $name            = $hash->{NAME};


    my $decode_json =   eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request: $@";
        
        if( AttrVal( $name, 'debugJSON', 0 ) == 1 ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, 'JSON_ERROR', $@, 1);
            readingsBulkUpdate($hash, 'JSON_ERROR_STRING', $json, 1);
            readingsEndUpdate($hash, 1);
        }
    }
    
    
    
    if( defined($decode_json->{sessions}) and $decode_json->{sessions}) {
    
        $hash->{helper}{session_id}         = $decode_json->{sessions}{token};
        $hash->{helper}{user_id}            = $decode_json->{sessions}{user_id};
        
        GardenaSmartBridge_Write($hash,undef,undef,undef);
        Log3 $name, 3, "GardenaSmartBridge ($name) - fetch locations id";
        readingsSingleUpdate($hash,'token',$hash->{helper}{session_id},1);
        
        return;
    
    } elsif( not defined($hash->{helper}{locations_id}) and defined($decode_json->{locations}) and ref($decode_json->{locations}) eq "ARRAY" and scalar(@{$decode_json->{locations}}) > 0) {
    
        foreach my $location ( @{$decode_json->{locations}} ) {
        
            $hash->{helper}{locations_id}    = $location->{id};

            GardenaSmartBridge_WriteReadings($hash,$location);
        }
        
        Log3 $name, 3, "GardenaSmartBridge ($name) - processed locations id. ID ist " . $hash->{helper}{locations_id};
        GardenaSmartBridge_Write($hash,undef,undef,undef);
        
        return;
        
    } elsif( defined($decode_json->{devices}) and ref($decode_json->{devices}) eq "ARRAY" and scalar(@{$decode_json->{devices}}) > 0) {

        my @buffer   = split('"devices":\[',$json);
        
        
        my ($json,$tail) = GardenaSmartBridge_ParseJSON($hash, $buffer[1]);


        while($json) {
        
            Log3 $name, 5, "GardenaSmartBridge ($name) - Decoding JSON message. Length: " . length($json) . " Content: " . $json;
            Log3 $name, 5, "GardenaSmartBridge ($name) - Vor Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
            
            
            unless( not defined($tail) and not ($tail) ) {
            
                $decode_json =   eval{decode_json($json)};
                if($@){
                    Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request: $@";
                }
                
                Dispatch($hash,$json,undef)
                unless( $decode_json->{category} eq 'gateway' );
            }
            
            ($json,$tail) = GardenaSmartBridge_ParseJSON($hash, $tail);
        
            Log3 $name, 5, "GardenaSmartBridge ($name) - Nach Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
        }

        return;
    }

        Log3 $name, 3, "GardenaSmartBridge ($name) - no Match for processing data"
}

sub GardenaSmartBridge_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};


    if( defined($decode_json->{id}) and $decode_json->{id} and defined($decode_json->{name}) and $decode_json->{name} ) {

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash,'name',$decode_json->{name});
        readingsBulkUpdateIfChanged($hash,'authorized_user_ids',scalar(@{$decode_json->{authorized_user_ids}}));
        readingsBulkUpdateIfChanged($hash,'devices',scalar(@{$decode_json->{devices}}));
        
        while( ( my ($t,$v) ) = each %{$decode_json->{geo_position}} ) {
            $v  = encode_utf8($v);
            readingsBulkUpdateIfChanged($hash,$t,$v);
        }
        
        readingsBulkUpdateIfChanged($hash,'zones',scalar(@{$decode_json->{zones}}));
        readingsEndUpdate( $hash, 1 );
    }

    Log3 $name, 3, "GardenaSmartBridge ($name) - readings would be written";
}


####################################
####################################
#### my little helpers Sub's #######

sub GardenaSmartBridge_getDevices($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    GardenaSmartBridge_Write($hash,undef,undef,undef);
    Log3 $name, 4, "GardenaSmartBridge ($name) - fetch device list and device states";
}

sub GardenaSmartBridge_getToken($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    delete $hash->{helper}{session_id}      if( defined($hash->{helper}{session_id}) and $hash->{helper}{session_id} );
    delete $hash->{helper}{user_id}         if( defined($hash->{helper}{user_id}) and $hash->{helper}{user_id} );
    delete $hash->{helper}{locations_id}    if( defined($hash->{helper}{locations_id}) and $hash->{helper}{locations_id} );
        
    GardenaSmartBridge_Write($hash,'"sessions": {"email": "'.GardenaSmartBridge_decrypt($hash->{helper}{username}).'","password": "'.GardenaSmartBridge_decrypt($hash->{helper}{password}).'"}',undef,undef);
    
    Log3 $name, 3, "GardenaSmartBridge ($name) - send credentials to fetch Token and locationId";
    
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday()+$hash->{INTERVAL},"GardenaSmartBridge_InternalTimerGetDeviceData", $hash, 1 );
}

sub GardenaSmartBridge_encrypt($) {

    my ($decoded) = @_;
    my $key = getUniqueId();
    my $encoded;

    return $decoded if( $decoded =~ /crypt:/ );

    for my $char (split //, $decoded) {
        my $encode = chop($key);
        $encoded .= sprintf("%.2x",ord($char)^ord($encode));
        $key = $encode.$key;
    }

    return 'crypt:'.$encoded;
}

sub GardenaSmartBridge_decrypt($) {

    my ($encoded) = @_;
    my $key = getUniqueId();
    my $decoded;

    return $encoded if( $encoded !~ /crypt:/ );
  
    $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

    for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
        my $decode = chop($key);
        $decoded .= chr(ord($char)^ord($decode));
        $key = $decode.$key;
    }

    return $decoded;
}

sub GardenaSmartBridge_ParseJSON($$) {

    my ($hash, $buffer) = @_;
    
    my $name    = $hash->{NAME};
    my $open    = 0;
    my $close   = 0;
    my $msg     = '';
    my $tail    = '';
    
    
    if($buffer) {
        foreach my $c (split //, $buffer) {
            if($open == $close && $open > 0) {
                $tail .= $c;
                Log3 $name, 5, "GardenaSmartBridge ($name) - $open == $close && $open > 0";
                
            } elsif(($open == $close) && ($c ne '{')) {
            
                Log3 $name, 5, "GardenaSmartBridge ($name) - Garbage character before message: " . $c;
        
            } else {
      
                if($c eq '{') {

                    $open++;
                
                } elsif($c eq '}') {
                
                    $close++;
                }
                
                $msg .= $c;
            }
        }
        
        if($open != $close) {
    
            $tail = $msg;
            $msg = '';
        }
    }
    
    Log3 $name, 4, "GardenaSmartBridge ($name) - return msg: $msg and tail: $tail";
    return ($msg,$tail);
}




1;






=pod

=item device
=item summary    Gardena Smart
=item summary_DE Gardena Smart

=begin html



=end html
=begin html_DE



=end html_DE
=cut
