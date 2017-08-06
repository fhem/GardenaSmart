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

use Data::Dumper;   #debugging

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.0.25";




# Declare functions
sub GardenaSmartDevice_Attr(@);
sub GardenaSmartDevice_Define($$);
sub GardenaSmartDevice_Initialize($);
sub GardenaSmartDevice_Set($@);
sub GardenaSmartDevice_Undef($$);
sub GardenaSmartDevice_WriteReadings($$);
sub GardenaSmartDevice_Parse($$);




sub GardenaSmartDevice_Initialize($) {

    my ($hash) = @_;
    
    $hash->{Match}      = '^{"id":".*';

    $hash->{SetFn}      = "GardenaSmartDevice_Set";
    $hash->{DefFn}      = "GardenaSmartDevice_Define";
    $hash->{UndefFn}    = "GardenaSmartDevice_Undef";
    $hash->{ParseFn}    = "GardenaSmartDevice_Parse";
    
    $hash->{AttrFn}     = "GardenaSmartDevice_Attr";
    $hash->{AttrList}   = "disable:1 ".
                            "model ".
                            $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{GardenaSmartDevice}{defptr}}) {
    
        my $hash = $modules{GardenaSmartDevice}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub GardenaSmartDevice_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );
    splice( @a, 1, 1 );
    my $iodev;
    my $i = 0;


    foreach my $param ( @a ) {
        if( $param =~ m/IODev=([^\s]*)/ ) {
        
            $iodev = $1;
            splice( @a, $i, 3 );
            last;
        }
        
        $i++;
    }


    return "too few parameters: define <NAME> GardenaSmartDevice <device_Id> <model>" if( @a != 3 ) ;
    return "Cannot define Gardena Bridge device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my ($name,$deviceId,$category)   = @a;
    
    $hash->{DEVICEID}           = $deviceId;
    $hash->{VERSION}            = $version;

    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "GardenaSmartDevice ($name) - I/O device is " . $hash->{IODev}->{NAME};
    
    } else {
    
        Log3 $name, 1, "GardenaSmartDevice ($name) - no I/O device";
    }
    
    $iodev = $hash->{IODev}->{NAME};
    
    my $d = $modules{GardenaSmartDevice}{defptr}{$deviceId};
    
    return "GardenaSmartDevice device $name on GardenaSmartBridge $iodev already defined."
    if( defined($d) && $d->{IODev} == $hash->{IODev} && $d->{NAME} ne $name );
    
    $attr{$name}{room}          = "GardenaSmart"    if( not defined( $attr{$name}{room} ) );
    $attr{$name}{model}         = $category         if( not defined( $attr{$name}{model} ) );
    
    Log3 $name, 3, "GardenaSmartDevice ($name) - defined GardenaSmartDevice with DEVICEID: $deviceId";
    readingsSingleUpdate($hash,'state','initialized',1);
    
    $modules{GardenaSmartDevice}{defptr}{$deviceId} = $hash;

    return undef;
}

sub GardenaSmartDevice_Undef($$) {

    my ( $hash, $arg )  = @_;
    my $name            = $hash->{NAME};
    my $deviceId        = $hash->{DEVICEID};
    
    
    delete $modules{GardenaSmartDevice}{defptr}{$deviceId};

    return undef;
}

sub GardenaSmartDevice_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};


    return undef;
}

sub GardenaSmartDevice_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    my $payload;
    
    
    if( lc $cmd eq 'parkuntilfurthernotice' ) {

        $payload    = '"name":"park_until_further_notice"';
    
    } elsif( lc $cmd eq 'parkuntilnexttimer' ) {
    
        $payload    = '"name":"park_until_next_timer"';
        
    } elsif( lc $cmd eq 'startresumeschedule' ) {
    
        $payload    = '"name":"start_resume_schedule"';
    
    } elsif( lc $cmd eq 'startoverridetimer' ) {
    
        my $duration     = join( " ", @args );
        $payload    = '"name":"start_override_timer","parameters":{"duration":' . $duration . '}';
    
    } elsif( lc $cmd eq 'manualoverride' ) {
    
        my $duration     = join( " ", @args );
        $payload    = '"name":"manual_override","parameters":{"duration":' . $duration . '}';
    
    } elsif( lc $cmd eq 'canceloverride' ) {
    
        $payload    = '"name":"cancel_override"';
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    
    } elsif( lc $cmd eq '' ) {
    
    
    } elsif( lc $cmd eq '' ) {
    
    
    } else {
    
        my $list    = '';
        $list       .= 'parkUntilFurtherNotice:noArg parkUntilNextTimer:noArg startResumeSchedule:noArg startOverrideTimer:slider,0,60,1440' if( AttrVal($name,'model','unknown') eq 'mower' );
        $list       .= 'manualOverride:slider,0,10,240 cancelOverride:noArg' if( AttrVal($name,'model','unknown') eq 'watering_computer' );
        $list       .= 'refresh:Temperature,Light,Humidity' if( AttrVal($name,'model','unknown') eq 'sensor' );
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    IOWrite($hash,$payload,$hash->{DEVICEID},AttrVal($name,'model','unknown'));
    Log3 $name, 4, "GardenaSmartBridge ($name) - IOWrite: $payload $hash->{DEVICEID} " . AttrVal($name,'model','unknown') . " IODevHash=$hash->{IODev}";
    
    return undef;
}

sub GardenaSmartDevice_Parse($$) {

    my ($io_hash,$json)  = @_;
    
    my $name                    = $io_hash->{NAME};
    
    
    
    my $decode_json =   eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request: $@";
    }
    
    Log3 $name, 4, "GardenaSmartDevice ($name) - ParseFn was called";
    Log3 $name, 5, "GardenaSmartDevice ($name) - JSON: $json";

    
    if( defined($decode_json->{id}) ) {
        
        my $deviceId                = $decode_json->{id};

        if( my $hash                = $modules{GardenaSmartDevice}{defptr}{$deviceId} ) {  
            my $name                = $hash->{NAME};
                        
            GardenaSmartDevice_WriteReadings($hash,$decode_json);
            Log3 $name, 4, "GardenaSmartDevice ($name) - find logical device: $hash->{NAME}";
                        
            return $hash->{NAME};
            
        } else {
            
            Log3 $name, 3, "GardenaSmartDevice ($name) - autocreate new device $decode_json->{name} with deviceId $decode_json->{id}, model $decode_json->{category} and IODev IODev=$name";
            return "UNDEFINED $decode_json->{name} GardenaSmartDevice $decode_json->{id} $decode_json->{category} IODev=$name";
        }
    }
}

sub GardenaSmartDevice_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    my $abilities               = scalar (@{$decode_json->{abilities}});

    
    readingsBeginUpdate($hash);
    
    do {
        
        if( ref($decode_json->{abilities}[$abilities]{properties}) eq "ARRAY" and scalar(@{$decode_json->{abilities}[$abilities]{properties}}) > 0 ) {;
            foreach my $propertie (@{$decode_json->{abilities}[$abilities]{properties}}) {
                readingsBulkUpdateIfChanged($hash,$decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name},$propertie->{value}) if( defined($propertie->{value}) );
            }
        }

        $abilities--;
    } while ($abilities >= 0);
    
    
    readingsBulkUpdateIfChanged($hash,'state',ReadingsVal($name,'mower-status','readingsValError')) if( AttrVal($name,'model','unknown') eq 'mower' );
    readingsBulkUpdateIfChanged($hash,'state',(ReadingsVal($name,'outlet-valve_open','readingsValError') == 1 ? "open" : "closed")) if( AttrVal($name,'model','unknown') eq 'watering_computer' );
    
    readingsBulkUpdateIfChanged($hash,'state','T: ' . ReadingsVal($name,'ambient_temperature-temperature','readingsValError') . '°C, H: ' . ReadingsVal($name,'humidity-humidity','readingsValError') . '%, Light: ' . ReadingsVal($name,'ambient_temperature-temperature','readingsValError') . 'lux') if( AttrVal($name,'model','unknown') eq 'sensor' );

    readingsEndUpdate( $hash, 1 );
    
    Log3 $name, 4, "GardenaSmartDevice ($name) - readings was written}";
}

##################################
##################################
#### my little helpers ###########








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
