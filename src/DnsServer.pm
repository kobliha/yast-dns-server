#! /usr/bin/perl -w
#
# DnsServer module written in Perl
#

package DnsServer;

use strict;

use ycp;
use YaST::YCP qw(Boolean);
use Data::Dumper;
use Time::localtime;

use Locale::gettext;
use POSIX ();     # Needed for setlocale()

POSIX::setlocale(LC_MESSAGES, "");
textdomain("dns-server");

our %TYPEINFO;


# FIXME this should be defined only once for all modules
sub _ {
    return gettext ($_[0]);
}


YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Mode");
YaST::YCP::Import ("Package");
YaST::YCP::Import ("Progress");
YaST::YCP::Import ("Report");
YaST::YCP::Import ("Service");
YaST::YCP::Import ("DnsZones");
YaST::YCP::Import ("DnsTSIGKeys");

use DnsData qw(@tsig_keys $start_service $chroot @allowed_interfaces
@zones @options @logging $ddns_file_name
$modified $save_all @files_to_delete %current_zone $current_zone_index
$adapt_firewall %firewall_settings $write_only @new_includes @deleted_includes
@zones_update_actions);
use DnsRoutines;

##-------------------------------------------------------------------------
##----------------- various routines --------------------------------------

sub contains {
    my @list = @{$_[0]};
    my $value = $_[1];

    my $found = 0;
    foreach my $x (@list) {
	if ($x eq $value)
	{
	    $found = 1;
	    last;
	}
    }
    $found;
}

##------------------------------------
# Routines for reading/writing configuration

BEGIN { $TYPEINFO{ZoneWrite} = ["function", "boolean", [ "map", "any", "any" ] ]; }
sub ZoneWrite {
    my %zone_map = %{$_[0]};

    my $zone_name = $zone_map{"zone"} || "";
    if ($zone_name eq "")
    {
	y2error ("Trying to save unnamed zone, aborting");
	return 0;
    }

    if (! ($zone_map{"modified"} || $save_all))
    {
	y2milestone ("Skipping zone $zone_name, wasn't modified");
	return 1;
    }

    my $zone_file = $zone_map{"file"} || "";
    if ($zone_file eq "")
    {
	$zone_file = "master/$zone_name";
	$zone_map{"file"} = $zone_file;
    }

    #save changed of named.conf
    my $base_path = ".dns.named.value.\"zone \\\"$zone_name\\\" in\"";
#    SCR::Write (".dns.named.section.\"zone \\\"$zone_name\\\" in\"", "");

    my @old_options = @{SCR::Dir ($base_path) || []};
    my @save_options = map {
	$_->{"key"};
    } @{$zone_map{"options"}};
    my @del_options = grep {
	! contains (\@save_options, $_);
    } @old_options;
    foreach my $o (@del_options) {
	SCR::Write ("$base_path.$o", undef);
    };

    my @tsig_keys = ();

    foreach my $o (@{$zone_map{"options"}}) {
	my $key = $o->{"key"};
	my $val = $o->{"value"};
	SCR::Write ("$base_path.$key", [$val]);
	if ($key eq "allow-update"
	    && $val =~ /^.*key[ \t]+([^ \t;]+)[ \t;]+.*$/)
	{
	    push @tsig_keys, $1;
	}
    };

    my $zone_type = $zone_map{"type"} || "master";

    if ($zone_type eq "master")
    {
	# write the zone file
	if (@tsig_keys == 0)
	{
	    DnsZones::ZoneFileWrite (\%zone_map);
	}
	else
	{
	    y2error ("Updating zone dynamically");
	    if ($zone_map{"soa_modified"})
	    {
		DnsZones::UpdateSOA (\%zone_map);
	    }
	    my %um = (
		"actions" => $zone_map{"update_actions"},
		"zone" => $zone_name,
		"tsig_key" => $tsig_keys[0],
		"ttl" => $zone_map{"ttl"},
	    );
	    push @zones_update_actions, \%um;
	}

	# write existing keys
	SCR::Write ("$base_path.file", ["\"$zone_file\""]);
    }
    elsif ($zone_type eq "slave" || $zone_type eq "stub")
    {
	my $masters = $zone_map{"masters"} || "";
	if (! $masters =~ /\{.*;\}/)
	{
	    $zone_map{"masters"} = "{$masters;}";
	}
        SCR::Write ("$base_path.masters", [$zone_map{"masters"} || ""]);
    }
    elsif ($zone_type eq "hint")
    {
	SCR::Write ("$base_path.file", ["\"$zone_file\""]);
    }

    SCR::Write ("$base_path.type", [$zone_map{"type"} || "master"]);

    return 1;
}

BEGIN { $TYPEINFO{AdaptFirewall} = ["function", "boolean"]; }
sub AdaptFirewall {
    if (! $adapt_firewall)
    {
	return 1;
    }

    my $ret = 1;

    foreach my $i ("INT", "EXT", "DMZ") {
        y2milestone ("Removing dhcpd iface $i");
        SuSEFirewall::RemoveService ("42", "UDP", $i);
        SuSEFirewall::RemoveService ("42", "TCP", $i);
    }
    if ($start_service)
    {
        foreach my $i (@allowed_interfaces) {
            y2milestone ("Adding dhcpd iface %1", $i);
            SuSEFirewall::AddService ("42", "UDP", $i);
            SuSEFirewall::AddService ("42", "TCP", $i);
        }
    }
    if (! Mode::test ())
    {
        Progress::off ();
        $ret = SuSEFirewall::Write () && $ret;
        Progress::on ();
    }
    if ($start_service)
    {
        $ret = SCR::Write (".sysconfig.SuSEfirewall2.FW_SERVICE_DHCPD",
            SuSEFirewall::MostInsecureInterface (\@allowed_interfaces)) && $ret;
    }
    else
    {
        $ret = SCR::Write (".sysconfig.SuSEfirewall2.FW_SERVICE_DHCPD", "no")
            && $ret;
    }

    $ret = SCR::Write (".sysconfig.SuSEfirewall2", undef) && $ret;
    if (! $write_only)
    {
        $ret = SCR::Execute (".target.bash", "test -x /sbin/rcSuSEfirewall2 && /sbin/rcSuSEfirewall2 status && /sbin/rcSuSEfirewall2 restart") && $ret;
    }
    if (! $ret)
    {
        # error report
        Report::Error (_("Error occurred while setting firewall settings."));
    }
    return $ret;
}

sub ReadDDNSKeys {
    @DnsTsigKeys::tsig_keys = ();
    my $includes = SCR::Read (".sysconfig.named.NAMED_CONF_INCLUDE_FILES")|| "";
    my @includes = split (/ /, $includes);
    foreach my $filename (@includes) {
	if ($filename ne "") {
	    y2milestone ("Reading include file $filename");
	    $filename = NormalizeFilename ($filename);
	    my @tsig_keys = @{DnsTsigKeys::AnalyzeTSIGKeyFile ($filename) ||[]};
	    foreach my $tsig_key (@tsig_keys) {
		y2milestone ("Having key $tsig_key, file $filename");
		push @DnsTsigKeys::tsig_keys, {
		    "filename" => $filename,
		    "key" => $tsig_key,
		};
	    }
	}
    };
}

sub AdaptDDNS {
    my @do_not_copy_chroot = ();

    my @globals = @{SCR::Dir (".dns.named.value") || []};

    my $includes = SCR::Read (".sysconfig.named.NAMED_CONF_INCLUDE_FILES")|| "";
    my @includes = split (/ /, $includes);
    my %includes = ();
    foreach my $i (@includes) {
	$includes{$i} = 1;
    }
    # remove obsolete
    foreach my $i (@deleted_includes) {
	my $file = $i->{"filename"};
	$includes{$file} = 0;
    }
    # add new
    foreach my $i (@new_includes) {
	my $file = $i->{"filename"};
	$includes{$file} = 1;
    }
    #save them back
    foreach my $i (keys (%includes)) {
	if ($includes{$i} != 1)
	{
	    delete $includes{$i};
	}
    }
    @includes = sort (keys (%includes));
    $includes = join (" ", @includes);
    SCR::Write (".sysconfig.named.NAMED_CONF_INCLUDE_FILES", $includes);

    return 1;
}

BEGIN { $TYPEINFO{SaveGlobals} = [ "function", "boolean" ]; }
sub SaveGlobals {

    #delete all deleted zones first
    my @old_sections = @{SCR::Dir (".dns.named.section") || []};
    my @old_zones = grep (/^zone/, @old_sections);
    my @current_zones = map {
	my %zone = %{$_};
	"zone \"$zone{\"zone\"}\" in";
    } @zones;
    my @del_zones = grep {
	! contains (\@current_zones, $_);
    } @old_zones;
    y2milestone ("Deleting zones @del_zones");
    foreach my $z (@del_zones) {
	SCR::Write (".dns.named.section.$z", undef);
    }

    # delete all removed options
    my @old_options = @{SCR::Dir (".dns.named.value.options") || []};
    my @current_options = map {
	$_->{"key"}
    } (@options);
    my @del_options = grep {
	! contains (\@current_options, $_);
    } @old_options;
    foreach my $o (@del_options) {
	SCR::Write (".dns.named.value.options.$o", undef);
    }

    # save the settings
    foreach my $option (@options)
    {
	my $key = $option->{"key"};
	my $value = $option->{"value"};
	# FIXME doesn't work with multiple occurences !!!
	SCR::Write (".dns.named.value.options.$key", [$value]);
    }

    # really save the file
    return SCR::Write (".dns.named", undef);
}



##------------------------------------
# Store/Find/Select/Remove a zone

BEGIN { $TYPEINFO{StoreZone} = ["function", "boolean"]; }
sub StoreZone {
    $current_zone{"modified"} = 1;
    if ($current_zone_index == -1)
    {
	push (@zones, \%current_zone);
    }
    else
    {
	$zones[$current_zone_index] = \%current_zone;
    }
    return Boolean(1);
}

BEGIN { $TYPEINFO{FindZone} = ["function", "integer", "string"]; }
sub FindZone {
    my $zone_name = $_[0];

    my $found_index = -1;
    my $index = -1;

    map {
	$index = $index + 1;
	my %zone_map = %{$_};
	if ($zone_map{"zone"} eq $zone_name)
	{
	    $found_index = $index;
	}
    } @zones;
    return $found_index;
}

BEGIN { $TYPEINFO{RemoveZone} = ["function", "boolean", "integer", "boolean"]; }
sub RemoveZone {
    my $zone_index = $_[0];
    my $delete_file = $_[1];

    if ($delete_file)
    {
	my %zone_map = %{$zones[$zone_index]};
	my $filename = DnsZones::AbsoluteZoneFileName ($zone_map{"file"});
	push (@files_to_delete, $filename) if (defined ($filename));
    }

    $zones[$zone_index] = 0;

    @zones = grep {
	ref ($_);
    } @zones;
    return 1;
}

BEGIN { $TYPEINFO{SelectZone} = ["function", "boolean", "integer"]; }
sub SelectZone {
    my $zone_index = $_[0];

    my $ret = 1;

    if ($zone_index < -1)
    {
	y2error ("Zone with index $zone_index doesn't exist");
	$zone_index = -1;
	$ret = 0;
    }
    elsif ($zone_index >= @zones)
    {
	y2error ("Zone with index $zone_index doesn't exist");
	$zone_index = -1;
	$ret = 0;
    }

    if ($zone_index == -1)
    {
	my %new_soa = %{DnsZones::GetDefaultSOA ()};
	%current_zone = (
	    "soa_modified" => 1,
	    "modified" => 1,
	    "type" => "master",
	    "soa" => \%new_soa,
	    "ttl" => "2D",
	);
    }
    else
    {
	%current_zone = %{$zones[$zone_index]};
    }
    $current_zone_index = $zone_index;

    return $ret;
}

#BEGIN{ $TYPEINFO{ListZones}=["function",["list",["map","string","string"]]];}
#sub ListZones {
#    return map {
#	{
#	    "zone" => $_->{"zone"},
#	    "type" => $_->{"type"},
#	}
#    } @zones;
#}

##------------------------------------
# Functions for accessing the data

BEGIN { $TYPEINFO{SetStartService} = [ "function", "void", "boolean" ];}
sub SetStartService {
    $start_service = $_[0];
    SetModified ();
}

BEGIN { $TYPEINFO{GetStartService} = [ "function", "boolean" ];}
sub GetStartService {
    return Boolean($start_service);
}

BEGIN { $TYPEINFO{SetChrootJail} = [ "function", "void", "boolean" ];}
sub SetChrootJail {
    $chroot = $_[0];
    SetModified ();
}

BEGIN { $TYPEINFO{GetChrootJail} = [ "function", "boolean" ];}
sub GetChrootJail {
    return Boolean($chroot);
}

BEGIN { $TYPEINFO{SetModified} = ["function", "void" ]; }
sub SetModified {
    $modified = 1;
}

BEGIN { $TYPEINFO{WasModified} = ["function", "boolean" ]; }
sub WasModified {
    return $modified;
}

BEGIN { $TYPEINFO{SetWriteOnly} = ["function", "void", "boolean" ]; }
sub SetWriteOnly {
    $write_only = $_[0];
}

BEGIN { $TYPEINFO{SetAdaptFirewall} = ["function", "void", "boolean" ]; }
sub SetAdaptFirewall {
    $adapt_firewall = $_[0];
}

BEGIN { $TYPEINFO{GetAdaptFirewall} = [ "function", "boolean" ];}
sub GetAdaptFirewall {
    return $adapt_firewall;
}

BEGIN{$TYPEINFO{SetAllowedInterfaces} = ["function","void",["list","string"]];}
sub SetAllowedInterfaces {
    @allowed_interfaces = @{$_[0]};
}

BEGIN { $TYPEINFO{GetAllowedInterfaces} = [ "function", ["list","string"]];}
sub GetAllowedInterfaces {
    return \@allowed_interfaces;
}
BEGIN {$TYPEINFO{FetchCurrentZone} = [ "function", ["map", "string", "any"] ]; }
sub FetchCurrentZone {
    return \%current_zone;
}

BEGIN {$TYPEINFO{StoreCurrentZone} = [ "function", "boolean", ["map", "string", "any"] ]; }
sub StoreCurrentZone {
    %current_zone = %{$_[0]};
    return 1;
}

BEGIN {$TYPEINFO{FetchZones} = [ "function", ["list", ["map", "any", "any"] ] ]; }
sub FetchZones {
    return \@zones;
}

BEGIN {$TYPEINFO{StoreZones} = [ "function", "void", [ "list", ["map", "any", "any"] ] ]; }
sub StoreZones {
    @zones = @{$_[0]};
    SetModified ();
}

BEGIN{$TYPEINFO{GetGlobalOptions}=["function",["list",["map","string","any"]]];}
sub GetGlobalOptions {
    return \@options;
}

BEGIN{$TYPEINFO{SetGlobalOptions}=["function","void",["list",["map","string","any"]]];}
sub SetGlobalOptions {
    @options = @{$_[0]};
    SetModified ();
}

BEGIN{$TYPEINFO{StopDnsService} = ["function", "boolean"];}
sub StopDnsService {
    my $ret = SCR::Execute (".target.bash", "/etc/init.d/named stop");
    if ($ret == 0)
    {
	return 1;
    }
    y2error ("Stopping DNS daemon failed");
    return 0;
}

BEGIN{$TYPEINFO{GetDnsServiceStatus} = ["function", "boolean"];}
sub GetDnsServiceStatus {
    my $ret = SCR::Execute (".target.bash", "/etc/init.d/named status");
    if ($ret == 0)
    {
	return 1;
    }
    return 0;
}

BEGIN{$TYPEINFO{StartDnsService} = ["function", "boolean"];}
sub StartDnsService { 
    my $ret = SCR::Execute (".target.bash", "/etc/init.d/named restart");
    if ($ret == 0)
    {
        return 1;
    }
    y2error ("Starting DNS daemon failed");
    return 0;
}   

##------------------------------------

BEGIN { $TYPEINFO{AutoPackages} = ["function", ["map","any","any"]];}
sub AutoPackages {
    return {
	"install" => ["bind"],
	"remote" => [],
    }
}

BEGIN { $TYPEINFO{Read} = ["function", "boolean"]; }
sub Read {

    # DNS server read dialog caption
    my $caption = _("Initializing DNS Server Configuration");

    Progress::New( $caption, " ", 3, [
	# progress stage
	_("Check the environment"),
	# progress stage
	_("Flush caches of the DNS daemon"),
	# progress stage
	_("Restart the DNS daemon"),
    ],
    [
	# progress step
	_("Checking the environment..."),
	# progress step
	_("Flushing caches of the DNS daemon..."),
	# progress step
	_("Reading the settings..."),
	# progress step
	_("Finished")
    ],
    ""
    );

    my $sl = 0.5;

    Progress::NextStage ();
    sleep ($sl);

    # Check packages
    if (! (Mode::config () || Package::Installed ("bind")))
    {
	my $installed = Package::Install ("bind");
	if (! $installed && ! Package::LastOperationCanceled ())
	{
	    # error popup
	    Report::Error (_("Installing required packages failed."));
	}
    }
 
    Progress::NextStage ();
    sleep ($sl);

    my $started = GetDnsServiceStatus ();
    StopDnsService ();
    if ($started)
    {
	StartDnsService ();
    }

    Progress::NextStage ();
    sleep ($sl);

    # Information about the daemon
    $start_service = Service::Enabled ("named");
    y2milestone ("Service start: $start_service");
    $chroot = SCR::Read (".sysconfig.named.NAMED_RUN_CHROOTED")
	? 1
	: 0;
    y2milestone ("Chroot: $chroot");

    my @zone_headers = @{SCR::Dir (".dns.named.section") || []};
    @zone_headers = grep (/^zone/, @zone_headers);
    y2milestone ("Read zone headers @zone_headers");

    my @opt_names = @{SCR::Dir (".dns.named.value.options") || []};
    if (! @opt_names)
    {
	@opt_names = ();
    }
    foreach my $key (@opt_names) {
	my @values = @{SCR::Read (".dns.named.value.options.$key") || []};
	foreach my $value (@values) {
	    push @options, {
		"key" => $key,
		"value" => $value,
	    };
	}
    }

    ReadDDNSKeys ();

    @zones = map {
	my $zonename = $_;
	$zonename =~ s/.*\"(.*)\".*/$1/;
	my $path_el = $_;
	$path_el =~ s/\"/\\\"/g;
	$path_el = "\"$path_el\"";
	my @tmp = @{SCR::Read (".dns.named.value.$path_el.type") || []};
	my $zonetype = $tmp[0] || "";
	@tmp = @{SCR::Read (".dns.named.value.$path_el.file") || []};
	my $filename = $tmp[0] || "";
	if (! defined $filename)
	{
	    $filename = $zonetype eq "master" ? "master" : "slave";
	    $filename = "$filename/$zonename";
	}
	if ($filename =~ /^\".*\"$/)
	{
	    $filename =~ s/^\"(.*)\"$/$1/;
	}
	my %zd = ();
	if ($zonetype eq "master")
	{
	    %zd = %{DnsZones::ZoneRead ($zonename, $filename)};
	}
	elsif ($zonetype eq "slave" || $zonetype eq "stub")
	{
	    @tmp = @{SCR::Read (".dns.named.value.$path_el.masters") || []};
	    $zd{"masters"} = $tmp[0] || "";
 	    if ($zd{"masters"} =~ /\{.*;\}/)
	    {
		$zd{"masters"} =~ s/\{(.*);\}/$1/
	    }
	}
	else
	{
# TODO hint, forward, .... not supported at the moment
	}
	
	my @zone_options_names = @{SCR::Dir (".dns.named.value.$path_el")|| []};
	my @zone_options = ();
	foreach my $key (@zone_options_names) {
	    my @values = @{SCR::Read (".dns.named.value.$path_el.$key") || []};
	    foreach my $value (@values) {
		push @zone_options, {
		    "key" => $key,
		    "value" => $value,
		}
	    }
	}
	
	$zd{"file"} = $filename;
	$zd{"type"} = $zonetype;
	$zd{"zone"} = $zonename;
	$zd{"options"} = \@zone_options;
	\%zd;
    } @zone_headers;
    $modified = 0;

    Progress::NextStage ();
    sleep ($sl);

    return Boolean(1);
}

BEGIN { $TYPEINFO{Write} = ["function", "boolean"]; }
sub Write {

    # DNS server read dialog caption
    my $caption = _("Initializing DNS Server Configuration");

    Progress::New( $caption, " ", 4, [
	# progress stage
	_("Flush caches of the DNS daemon"),
	# progress stage
	_("Save configuration files"),
	# progress stage
	_("Restart the DNS daemon"),
	# progress stage
	_("Update zone files"),
    ],
    [
	# progress step
	_("Flushing caches of the DNS daemon..."),
	# progress step
	_("Saving configuration files..."),
	# progress step
	_("Restarting the DNS daemon..."),
	# progress step
	_("Updating zone files..."),
	# progress step
	_("Finished")
    ],
    ""
    );

    my $sl = 0.5;

    Progress::NextStage ();
    sleep ($sl);

    my $ok = 1;

    if (! $modified)
    {
	return "true";
    }

    $ok = StopDnsService () && $ok;

    Progress::NextStage ();
    sleep ($sl);

    #adapt firewall
    $ok = AdaptFirewall () && $ok;

    #save globals
    $ok = SaveGlobals () && $ok;

    #adapt included files
    $ok = AdaptDDNS () && $ok;

    #save all zones
    @zones_update_actions = ();
    foreach my $z (@zones) {
	$ok = ZoneWrite ($z) && $ok;
    }

    #be sure the named.conf file is saved
    SCR::Write (".dns.named", undef);
    
    #set daemon starting
    SCR::Write (".sysconfig.named.NAMED_RUN_CHROOTED", $chroot ? "yes" : "no");
    SCR::Write (".sysconfig.named", undef);

    Progress::NextStage ();
    sleep ($sl);

    my $ret = 0;
    if (0 != @zones_update_actions)
    {
	$ret = SCR::Execute (".target.bash", "/etc/init.d/named restart");
    }

    Progress::NextStage ();
    sleep ($sl);

    if (0 != @zones_update_actions)
    {
	if ($ret != 0)
	{
	    $ok = 0;
	}
	else
	{
	    sleep (0.1);
	    DnsZones::UpdateZones (\@zones_update_actions);
	}
    }

    Progress::NextStage ();
    sleep ($sl);

    if ($start_service)
    {
	my $ret = 0;
	if (! $write_only)
	{
	    $ret = SCR::Execute (".target.bash", "/etc/init.d/named restart");
	}
	Service::Enable ("named");
	if (0 != $ret)
	{
	    $ok = 0;
	}
    }
    else
    {
	if (! $write_only)
	{
	    SCR::Execute (".target.bash", "/etc/init.d/named stop");
	}
	Service::Disable ("named");
    }

    Progress::NextStage ();
    sleep ($sl);

    return Boolean($ok);
}

BEGIN { $TYPEINFO{Export}  =["function", [ "map", "any", "any" ] ]; }
sub Export {
    my %ret = (
	"start_service" => $start_service,
	"chroot" => $chroot,
	"allowed_interfaces" => \@allowed_interfaces,
	"zones" => \@zones,
	"options" => \@options,
	"logging" => \@logging,
    );
    return \%ret;
}
BEGIN { $TYPEINFO{Import} = ["function", "boolean", [ "map", "any", "any" ] ]; }
sub Import {
    my %settings = %{$_[0]};

    $start_service = $settings{"start_service"} || 0;
    $chroot = $settings{"chroot"} || 1;
    @allowed_interfaces = @{$settings{"allowed_interfaces"} || []};
    @zones = @{$settings{"zones"} || []}; 
    @options = @{$settings{"options"} || []};
    @logging = @{$settings{"logging"} || []};

    $modified = 1;
    $save_all = 1;
    @files_to_delete = ();
    %current_zone = ();
    $current_zone_index = -1;
    $adapt_firewall = 0;
    $write_only = 0;
    return Boolean(1);
}

BEGIN { $TYPEINFO{Summary} = ["function", [ "list", "string" ] ]; }
sub Summary {
    my %zone_types = (
	# type of zone to be used in summary
	"master" => _("master"),
	# type of zone to be used in summary
	"slave" => _("slave"),
	# type of zone to be used in summary
	"stub" => _("stub"),
	# type of zone to be used in summary
	"hint" => _("hint"),
	# type of zone to be used in summary
	"forward" => _("forward"),
    );
    my @ret = ();

    if ($start_service)
    {
	# summary string
	push (@ret, _("The DNS server starts when booting the system."));
    }
    else
    {
	push (@ret,
	    # summary string
	    _("The DNS server does not start when booting the system."));
    }

    my @zones_descr = map {
	my $zone_ref = $_;
	my %zone_map = %{$zone_ref};	
	my $zone_name = $zone_map{"zone"} || "";
	my $zone_type = $zone_map{"type"} || "";
	$zone_type = $zone_types{$zone_type} || $zone_type;
	my $descr = "";
	if ($zone_name ne "")
	{
	    if ($zone_type ne "")
	    {
		$descr = "$zone_name ($zone_type)";
	    }
	    else
	    {
		$descr = "$zone_name";
	    }
	}
	$descr;
    } @zones;
    @zones_descr = grep {
	$_ ne "";
    } @zones_descr;

    my $zones_list = join (", ", @zones_descr);
    #  summary string, %s is list of DNS zones (their names), coma separated
    push (@ret, sprintf (_("Configured Zones: %s"), $zones_list));
    return \@ret;
}


# EOF
