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
use Time::Local;

use Data::Dumper;   #debugging

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.0.58";




# Declare functions
sub GardenaSmartDevice_Attr(@);
sub GardenaSmartDevice_Define($$);
sub GardenaSmartDevice_Initialize($);
sub GardenaSmartDevice_Set($@);
sub GardenaSmartDevice_Undef($$);
sub GardenaSmartDevice_WriteReadings($$);
sub GardenaSmartDevice_Parse($$);
sub GardenaSmartDevice_ReadingLangGerman($$);
sub GardenaSmartDevice_RigRadingsValue($$);
sub GardenaSmartDevice_Zulu2LocalString($);




sub GardenaSmartDevice_Initialize($) {

    my ($hash) = @_;
    
    $hash->{Match}      = '^{"id":".*';

    $hash->{SetFn}      = "GardenaSmartDevice_Set";
    $hash->{DefFn}      = "GardenaSmartDevice_Define";
    $hash->{UndefFn}    = "GardenaSmartDevice_Undef";
    $hash->{ParseFn}    = "GardenaSmartDevice_Parse";
    
    $hash->{AttrFn}     = "GardenaSmartDevice_Attr";
    $hash->{AttrList}   = "disable:1 ".
                            "readingValueLanguage:de ".
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
    my $abilities;
    
    
    ### mower
    if( lc $cmd eq 'parkuntilfurthernotice' ) {

        $payload    = '"name":"park_until_further_notice"';
    
    } elsif( lc $cmd eq 'parkuntilnexttimer' ) {
    
        $payload    = '"name":"park_until_next_timer"';
        
    } elsif( lc $cmd eq 'startresumeschedule' ) {
    
        $payload    = '"name":"start_resume_schedule"';
    
    } elsif( lc $cmd eq 'startoverridetimer' ) {
    
        my $duration     = join( " ", @args );
        $payload    = '"name":"start_override_timer","parameters":{"duration":' . $duration . '}';
    
    ### watering_computer
    } elsif( lc $cmd eq 'manualoverride' ) {
    
        my $duration     = join( " ", @args );
        $payload    = '"name":"manual_override","parameters":{"duration":' . $duration . '}';
    
    } elsif( lc $cmd eq 'canceloverride' ) {
    
        $payload    = '"name":"cancel_override"';
    
    ### Sensors
    } elsif( lc $cmd eq 'refresh' ) {
    
        my $sensname     = join( " ", @args );
        if( lc $sensname eq 'temperature' ) {
            $payload    = '"name":"measure_ambient_temperature"';
            $abilities  = 'ambient_temperature';
            
        } elsif( lc $sensname eq 'light' ) {
            $payload    = '"name":"measure_light"';
            $abilities  = 'light';
            
        } elsif( lc $sensname eq 'humidity' ) {
            $payload    = '"name":"measure_humidity"';
            $abilities  = 'humidity';
        }
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    } elsif( lc $cmd eq '' ) {
    
    
    } elsif( lc $cmd eq '' ) {
    
    
    } elsif( lc $cmd eq '' ) {
    
    
    } else {
    
        my $list    = '';
        $list       .= 'parkUntilFurtherNotice:noArg parkUntilNextTimer:noArg startResumeSchedule:noArg startOverrideTimer:slider,0,60,1440' if( AttrVal($name,'model','unknown') eq 'mower' );
        $list       .= 'manualOverride:slider,0,1,59 cancelOverride:noArg' if( AttrVal($name,'model','unknown') eq 'watering_computer' );
        $list       .= 'refresh:temperature,light' if( AttrVal($name,'model','unknown') eq 'sensor' );
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    $abilities  = 'mower' if( AttrVal($name,'model','unknown') eq 'mower' );
    $abilities  = 'outlet' if( AttrVal($name,'model','unknown') eq 'watering_computer' );
    
    
    $hash->{helper}{deviceAction}  = $payload;
    readingsSingleUpdate( $hash, "state", "send command to gardena cloud", 1);
    
    IOWrite($hash,$payload,$hash->{DEVICEID},$abilities);
    Log3 $name, 4, "GardenaSmartBridge ($name) - IOWrite: $payload $hash->{DEVICEID} $abilities IODevHash=$hash->{IODev}";
    
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
            
            Log3 $name, 3, "GardenaSmartDevice ($name) - autocreate new device " . join('',split("[ \t]+",$decode_json->{name})) . " with deviceId $decode_json->{id}, model $decode_json->{category} and IODev IODev=$name";
            return "UNDEFINED " . join('',split("[ \t]+",$decode_json->{name})) . " GardenaSmartDevice $decode_json->{id} $decode_json->{category} IODev=$name";
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
                readingsBulkUpdateIfChanged($hash,$decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name},GardenaSmartDevice_RigRadingsValue($hash,$propertie->{value})) if( defined($propertie->{value})
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'radio-quality'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'battery-level'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'internal_temperature-temperature'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'ambient_temperature-temperature'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'soil_temperature-temperature'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'humidity-humidity'
                                                            and $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} ne 'light-light' );
                                                            
                readingsBulkUpdate($hash,$decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name},GardenaSmartDevice_RigRadingsValue($hash,$propertie->{value})) if( defined($propertie->{value})
                                                            and ($decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'radio-quality'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'battery-level'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'internal_temperature-temperature'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'ambient_temperature-temperature'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'soil_temperature-temperature'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'humidity-humidity'
                                                            or $decode_json->{abilities}[$abilities]{name}.'-'.$propertie->{name} eq 'light-light') );
            }
        }

        $abilities--;
    } while ($abilities >= 0);
    
    
    readingsBulkUpdate($hash,'state',ReadingsVal($name,'mower-status','readingsValError')) if( AttrVal($name,'model','unknown') eq 'mower' );
    readingsBulkUpdate($hash,'state',(ReadingsVal($name,'outlet-valve_open','readingsValError') == 1 ? GardenaSmartDevice_RigRadingsValue($hash,'open') : GardenaSmartDevice_RigRadingsValue($hash,'closed'))) if( AttrVal($name,'model','unknown') eq 'watering_computer' );
    
    readingsBulkUpdate($hash,'state','T: ' . ReadingsVal($name,'ambient_temperature-temperature','readingsValError') . '°C, H: ' . ReadingsVal($name,'humidity-humidity','readingsValError') . '%, L: ' . ReadingsVal($name,'light-light','readingsValError') . 'lux') if( AttrVal($name,'model','unknown') eq 'sensor' );

    readingsEndUpdate( $hash, 1 );
    
    Log3 $name, 4, "GardenaSmartDevice ($name) - readings was written}";
}

##################################
##################################
#### my little helpers ###########

sub GardenaSmartDevice_ReadingLangGerman($$) {

    my ($hash,$readingValue)    = @_;
    my $name                    = $hash->{NAME};
    
    
    my %langGermanMapp = (
                'ok_cutting'                        =>  'mähen',
                'paused'                            =>  'pausiert',
                'ok_searching'                      =>  'suche Ladestation',
                'ok_charging'                       =>  'lädt',
                'ok_leaving'                        =>  'mähen',
                'wait_updating'                     =>  'wird aktualisiert ...',
                'wait_power_up'                     =>  'wird eingeschaltet ...',
                'parked_timer'                      =>  'geparkt nach Zeitplan',
                'parked_park_selected'              =>  'geparkt',
                'off_disabled'                      =>  'der Mäher ist ausgeschaltet',
                'off_hatch_open'                    =>  'deaktiviert. Abdeckung ist offen oder PIN-Code erforderlich',
                'unknown'                           =>  'unbekannter Status',
                'error'                             =>  'fehler',
                'error_at_power_up'                 =>  'neustart ...',
                'off_hatch_closed'                  =>  'deaktiviert. Manueller Start erforderlich',
                'ok_cutting_timer_overridden'       =>  'manuelles mähen',
                'parked_autotimer'                  =>  'geparkt durch SensorControl',
                'parked_daily_limit_reached'        =>  'abgeschlossen',
                'no_message'                        =>  'kein Fehler',
                'outside_working_area'              =>  'außerhalb des Arbeitsbereichs',
                'no_loop_signal'                    =>  'kein Schleifensignal',
                'wrong_loop_signal'                 =>  'falsches Schleifensignal',
                'loop_sensor_problem_front'         =>  'problem Schleifensensor, vorne',
                'loop_sensor_problem_rear'          =>  'problem Schleifensensor, hinten',
                'trapped'                           =>  'eingeschlossen',
                'upside_down'                       =>  'steht auf dem Kopf',
                'low_battery'                       =>  'niedriger Batteriestand',
                'empty_battery'                     =>  'empty_battery',
                'no_drive'                          =>  'no_drive',
                'lifted'                            =>  'angehoben',
                'stuck_in_charging_station'         =>  'eingeklemmt in Ladestation',
                'charging_station_blocked'          =>  'ladestation blockiert',
                'collision_sensor_problem_rear'     =>  'problem Stoßsensor hinten',
                'collision_sensor_problem_front'    =>  'problem Stoßsensor vorne',
                'wheel_motor_blocked_right'         =>  'radmotor rechts blockiert',
                'wheel_motor_blocked_left'          =>  'radmotor links blockiert',
                'wheel_drive_problem_right'         =>  'problem Antrieb, rechts',
                'wheel_drive_problem_left'          =>  'problem Antrieb, links',
                'cutting_system_blocked'            =>  'schneidsystem blockiert',
                'invalid_sub_device_combination'    =>  'Fehlerhafte Verbindung',
                'settings_restored'                 =>  'standardeinstellungen',
                'electronic_problem'                =>  'elektronisches Problem',
                'charging_system_problem'           =>  'problem Ladesystem',
                'tilt_sensor_problem'               =>  'kippsensorproblem',
                'wheel_motor_overloaded_right'      =>  'rechter Radmotor überlastet',
                'wheel_motor_overloaded_left'       =>  'linker Radmotor überlastet',
                'charging_current_too_high'         =>  'ladestrom zu hoch',
                'temporary_problem'                 =>  'vorübergehendes Problem',
                'guide_1_not_found'                 =>  'sk 1 nicht gefunden',
                'guide_2_not_found'                 =>  'sk 2 nicht gefunden',
                'guide_3_not_found'                 =>  'sk 3 nicht gefunden',
                'difficult_finding_home'            =>  'problem die Ladestation zu finden',
                'guide_calibration_accomplished'    =>  'kalibration des Suchkabels beendet',
                'guide_calibration_failed'          =>  'kalibration des Suchkabels fehlgeschlagen',
                'temporary_battery_problem'         =>  'kurzzeitiges Batterieproblem',
                'battery_problem'                   =>  'batterieproblem',
                'alarm_mower_switched_off'          =>  'alarm! Mäher ausgeschalten',
                'alarm_mower_stopped'               =>  'alarm! Mäher gestoppt',
                'alarm_mower_lifted'                =>  'alarm! Mäher angehoben',
                'alarm_mower_tilted'                =>  'alarm! Mäher gekippt',
                'connection_changed'                =>  'verbindung geändert',
                'connection_not_changed'            =>  'verbindung nicht geändert',
                'com_board_not_available'           =>  'com board nicht verfügbar',
                'slipped'                           =>  'rutscht',
                'out_of_operation'                  =>  'ausser Betrieb',
                'replace_now'                       =>  'kritischer Batteriestand, wechseln Sie jetzt',
                'low'                               =>  'niedrig',
                'ok'                                =>  'oK',
                'no_source'                         =>  'oK',
                'mower_charging'                    =>  'mäher wurde geladen',
                'completed_cutting_autotimer'       =>  'sensorControl erreicht',
                'week_timer'                        =>  'wochentimer erreicht',
                'countdown_timer'                   =>  'stoppuhr Timer',
                'undefined'                         =>  'unklar',
                'unknown'                           =>  'unklar',
                'status_device_unreachable'         =>  'gerät ist nicht in Reichweite',
                'status_device_alive'               =>  'gerät ist in Reichweite',
                'bad'                               =>  'schlecht',
                'poor'                              =>  'schwach',
                'good'                              =>  'gut',
                'undefined'                         =>  'unklar',
                'idle'                              =>  'nichts zu tun',
                'firmware_cancel'                   =>  'firmwareupload unterbrochen',
                'firmware_upload'                   =>  'firmwareupload',
                'unsupported'                       =>  'nicht unterstützt',
                'up_to_date'                        =>  'auf dem neusten Stand',
                'mower'                             =>  'mäher',
                'watering_computer'                 =>  'bewässerungscomputer',
                'no_frost'                          =>  'kein Frost',
                'open'                              =>  'offen',
                'closed'                            =>  'geschlossen',
                'included'                          =>  'inbegriffen',
                'active'                            =>  'aktiv',
                'inactive'                          =>  'nicht aktiv'
    );
    
    if( defined($langGermanMapp{$readingValue}) and (AttrVal('global','language','none') eq 'DE' or AttrVal($name,'readingValueLanguage','none') eq 'de') ) {
        return $langGermanMapp{$readingValue};
    } else {
        return $readingValue;
    }
}

sub GardenaSmartDevice_RigRadingsValue($$) {

    my ($hash,$readingValue)    = @_;

    my $rigReadingValue;
    
    
    if( $readingValue =~ /^(\d+)-(\d\d)-(\d\d)T.*/ ) {
        $rigReadingValue = GardenaSmartDevice_Zulu2LocalString($readingValue);
    } else {
        $rigReadingValue = GardenaSmartDevice_ReadingLangGerman($hash,$readingValue);
    }

    return $rigReadingValue;
}

sub GardenaSmartDevice_Zulu2LocalString($) {

    my $t = shift;
    my ($datehour,$datemin,$rest) = split(/:/,$t,3);


    my ($year, $month, $day, $hour,$min) = $datehour =~ /(\d+)-(\d\d)-(\d\d)T(\d\d)/;
    my $epoch = timegm (0,0,$hour,$day,$month-1,$year);

    my ($lyear,$lmonth,$lday,$lhour,$isdst) = (localtime($epoch))[5,4,3,2,-1];

    $lyear += 1900;  # year is 1900 based
    $lmonth++;       # month number is zero based

    return ( sprintf("%04d-%02d-%02d %02d:%02d:%s",$lyear,$lmonth,$lday,$lhour,$datemin,substr($rest,0,2)) );
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
