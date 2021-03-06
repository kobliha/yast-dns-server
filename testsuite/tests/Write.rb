# encoding: utf-8

# File:	Write.ycp
# Package:	Configuration of dns-server
# Summary:	Testsuite for writting configuration
# Authors:	Jiri Srain <jsrain@suse.cz>, Lukas Ocilka <locilka@suse.cz>
# Copyright:	Copyright 2004, Novell, Inc.  All rights reserved.
#
# $Id$
#
# Testsuite for writting configuration for dns-server
require "yast"

module Yast
  class WriteClient < Client
    def main
      Yast.include self, "testsuite.rb"
      # testedfiles: DnsServer.pm DNSD.pm DnsZones.pm
      @I_READ = {
        "probe"     => {
          "architecture" => "i386",
          "has_apm"      => true,
          "has_pcmcia"   => false,
          "has_smp"      => false,
          "system"       => [],
          "memory"       => [],
          "cpu"          => [],
          "cdrom"        => { "manual" => [] },
          "floppy"       => { "manual" => [] },
          "is_uml"       => false
        },
        "product"   => {
          "features" => {
            "USE_DESKTOP_SCHEDULER" => "0",
            "IO_SCHEDULER"          => "cfg",
            "UI_MODE"               => "expert",
            "ENABLE_AUTOLOGIN"      => "0",
            "EVMS_CONFIG"           => "0"
          }
        },
        "sysconfig" => {
          "SuSEfirewall2"     => {
            "FW_ALLOW_FW_TRACEROUTE"   => "yes",
            "FW_AUTOPROTECT_SERVICES"  => "no",
            "FW_DEV_DMZ"               => "",
            "FW_DEV_EXT"               => "eth-id-00:c0:df:22:c6:a8",
            "FW_DEV_INT"               => "",
            "FW_IPSEC_TRUST"           => "no",
            "FW_LOG_ACCEPT_ALL"        => "no",
            "FW_LOG_ACCEPT_CRIT"       => "yes",
            "FW_LOG_DROP_ALL"          => "no",
            "FW_LOG_DROP_CRIT"         => "yes",
            "FW_MASQUERADE"            => "no",
            "FW_MASQ_NETS"             => "",
            "FW_PROTECT_FROM_INTERNAL" => "yes",
            "FW_ROUTE"                 => "no",
            "FW_SERVICES_DMZ_IP"       => "",
            "FW_SERVICES_DMZ_TCP"      => "",
            "FW_SERVICES_DMZ_UDP"      => "",
            "FW_SERVICES_EXT_IP"       => "",
            "FW_SERVICES_EXT_RPC"      => "nlockmgr status nfs nfs_acl mountd ypserv fypxfrd ypbind ypasswdd",
            "FW_SERVICES_EXT_TCP"      => "32768 5801 5901 dixie domain hostname microsoft-ds netbios-dgm netbios-ns netbios-ssn nfs ssh sunrpc",
            "FW_SERVICES_EXT_UDP"      => "222 bftp domain ipp sunrpc",
            "FW_SERVICES_INT_IP"       => "",
            "FW_SERVICES_INT_TCP"      => "ddd eee fff 44 55 66",
            "FW_SERVICES_INT_UDP"      => "aaa bbb ccc 11 22 33"
          },
          "personal-firewall" => { "REJECT_ALL_INCOMING_CONNECTIONS" => "" },
          "console"           => { "CONSOLE_ENCODING" => "utf8" },
          "language"          => {
            "RC_LANG"        => "en_US.UTF-8",
            "ROOT_USES_LANG" => "ctype"
          },
          "network" => {
            "NETCONFIG_DNS_FORWARDER"  => "resolver",
          },
        },
        "target"    => {
          "yast2" => { "lang2iso.ycp" => {} },
          "stat"  => {
            "atime"   => 1101890288,
            "ctime"   => 1101890286,
            "gid"     => 0,
            "inode"   => 29236,
            "isblock" => false,
            "ischr"   => false,
            "isdir"   => false,
            "isfifo"  => false,
            "islink"  => false,
            "isreg"   => true,
            "issock"  => false,
            "mtime"   => 1101890286,
            "nlink"   => 1,
            "size"    => 804,
            "uid"     => 0
          },
          "ycp"   => {}
        }
      }
      @I_WRITE = {}
      @I_EXEC = {}

      TESTSUITE_INIT([@I_READ, @I_WRITE, @I_EXEC], nil)

      Yast.import "Progress"
      Yast.import "DnsServer"
      Yast.import "Mode"

      Mode.SetMode("test")

      @progress_orig = Progress.set(false)

      @READ = {
        "probe"     => {
          "architecture" => "i386",
          "has_apm"      => true,
          "has_pcmcia"   => false,
          "has_smp"      => false,
          "system"       => [],
          "memory"       => [],
          "cpu"          => [],
          "cdrom"        => { "manual" => [] },
          "floppy"       => { "manual" => [] },
          "is_uml"       => false
        },
        "product"   => {
          "features" => {
            "USE_DESKTOP_SCHEDULER" => "0",
            "IO_SCHEDULER"          => "cfg",
            "UI_MODE"               => "expert",
            "ENABLE_AUTOLOGIN"      => "0",
            "EVMS_CONFIG"           => "0"
          }
        },
        # Runlevel
        "init"      => {
          "scripts" => {
            "exists"   => true,
            "runlevel" => { "named" => { "start" => [], "stop" => [] } },
            # their contents is not important for ServiceAdjust
            "comment"  => {
              "named" => {}
            }
          }
        },
        "target"    => {
          "stat" => {
            "atime"   => 1101890288,
            "ctime"   => 1101890286,
            "gid"     => 0,
            "inode"   => 29236,
            "isblock" => false,
            "ischr"   => false,
            "isdir"   => false,
            "isfifo"  => false,
            "islink"  => false,
            "isreg"   => true,
            "issock"  => false,
            "mtime"   => 1101890286,
            "nlink"   => 1,
            "size"    => 804,
            "uid"     => 0
          },
          "ycp"  => {}
        },
        "dns"       => {
          "named" => {
            "section" => { "options" => "", "zone \"localhost\" in" => "" },
            "value"   => {
              "options"               => {
                "directory" => "\"/var/lib/named\"",
                "notify"    => "no",
                "xxx"       => "yyy"
              },
              "zone \"localhost\" in" => {
                "type" => "master",
                "file" => "\"localhost.zone\""
              }
            }
          },
          "zone"  => {
            "TTL"     => "1W",
            "records" => [
              { "key" => "", "type" => "NS", "value" => "@" },
              { "key" => "", "type" => "A", "value" => "127.0.0.1" },
              { "key" => "localhost2", "type" => "A", "value" => "127.0.0.2" }
            ],
            "soa"     => {
              "expiry"  => "6W",
              "mail"    => "root",
              "minimum" => "1W",
              "refresh" => "2D",
              "retry"   => "4H",
              "serial"  => 42,
              "server"  => "@",
              "zone"    => "@"
            }
          }
        },
        "sysconfig" => {
          "SuSEfirewall2"     => {
            "FW_ALLOW_FW_TRACEROUTE"   => "yes",
            "FW_AUTOPROTECT_SERVICES"  => "no",
            "FW_DEV_DMZ"               => "",
            "FW_DEV_EXT"               => "eth-id-00:c0:df:22:c6:a8",
            "FW_DEV_INT"               => "",
            "FW_IPSEC_TRUST"           => "no",
            "FW_LOG_ACCEPT_ALL"        => "no",
            "FW_LOG_ACCEPT_CRIT"       => "yes",
            "FW_LOG_DROP_ALL"          => "no",
            "FW_LOG_DROP_CRIT"         => "yes",
            "FW_MASQUERADE"            => "no",
            "FW_MASQ_NETS"             => "",
            "FW_PROTECT_FROM_INTERNAL" => "yes",
            "FW_ROUTE"                 => "no",
            "FW_SERVICES_DMZ_IP"       => "",
            "FW_SERVICES_DMZ_TCP"      => "",
            "FW_SERVICES_DMZ_UDP"      => "",
            "FW_SERVICES_EXT_IP"       => "",
            "FW_SERVICES_EXT_RPC"      => "nlockmgr status nfs nfs_acl mountd ypserv fypxfrd ypbind ypasswdd",
            "FW_SERVICES_EXT_TCP"      => "32768 5801 5901 dixie domain hostname microsoft-ds netbios-dgm netbios-ns netbios-ssn nfs ssh sunrpc",
            "FW_SERVICES_EXT_UDP"      => "222 bftp domain ipp sunrpc",
            "FW_SERVICES_INT_IP"       => "",
            "FW_SERVICES_INT_TCP"      => "ddd eee fff 44 55 66",
            "FW_SERVICES_INT_UDP"      => "aaa bbb ccc 11 22 33"
          },
          "personal-firewall" => { "REJECT_ALL_INCOMING_CONNECTIONS" => "" },
          "console"           => { "CONSOLE_ENCODING" => "utf8" },
          "language"          => {
            "RC_LANG"        => "en_US.UTF-8",
            "ROOT_USES_LANG" => "ctype"
          }
        },
        "target"    => {
          "yast2" => { "lang2iso.ycp" => {} },
          "ycp"   => {},
          "stat"  => {
            "atime"   => 1101890288,
            "ctime"   => 1101890286,
            "gid"     => 0,
            "inode"   => 29236,
            "isblock" => false,
            "ischr"   => false,
            "isdir"   => false,
            "isfifo"  => false,
            "islink"  => false,
            "isreg"   => true,
            "issock"  => false,
            "mtime"   => 1101890286,
            "nlink"   => 1,
            "size"    => 804,
            "uid"     => 0
          }
        }
      }
      @WRITE = {}
      @EXEC = {
        "target" => { "bash_output" => { "exit" => 0, "stdout" => "20030806", "stderr"=>"" } }
      }

      DUMP("=======================")
      TEST(lambda do
        DnsServer.Import(
          {
            "chroot"        => false,
            "options"       => [
              { "key" => "directory", "value" => "\"/var/lib/named\"" },
              { "key" => "notify", "value" => "no" }
            ],
            "start_service" => false,
            "zones"         => [
              {
                "file"     => "example.com",
                "records"  => [
                  {
                    "key"   => "localhost",
                    "type"  => "A",
                    "value" => "127.0.0.1"
                  },
                  {
                    "key"   => "localhost",
                    "type"  => "NS",
                    "value" => "127.0.0.1"
                  },
                  {
                    "key"   => "localhost2",
                    "type"  => "A",
                    "value" => "127.0.0.2"
                  }
                ],
                "soa"      => {
                  "expiry"  => "6W",
                  "mail"    => "root",
                  "minimum" => "1W",
                  "refresh" => "2D",
                  "retry"   => "4H",
                  "serial"  => 42,
                  "server"  => "@",
                  "zone"    => "@"
                },
                "ttl"      => "1W",
                "type"     => "master",
                "zone"     => "example.com",
                "modified" => true
              }
            ]
          }
        )
      end, [], 0)
      DUMP("=======================")
      TEST(lambda { DnsServer.Write }, [@READ, @WRITE, @EXEC], 0)

      nil
    end
  end
end

Yast::WriteClient.new.main
