require 'spec_helper_acceptance'

test_name 'SIMP SNMPD Profile'

describe 'simp_snmpd class' do
  let(:manifest) {
    <<-EOM
      # Allow ssh incase you need to troubleshoot
      iptables::listen::tcp_stateful { 'allow_sshd':
        order => 8,
        trusted_nets => ['ALL'],
        dports => 22,
      }

      include 'simp_snmpd'
    EOM
  }

  let(:snmphieradata) { <<-EOH
---
simp_options::firewall: true
simp_options::syslog: true
simp_options::logrotate: true
simp_options::trusted_nets: ['ALL']
simp_snmpd::v3_users_hash:
  snmp_ro:
    authpass: 'KeepItSecret'
    privpass: 'KeepItSafe'
  snmp_rw:
    authpass: 'KeepItSecret'
    privpass: 'KeepItSafe'
# Listen on all interfaces
simp_snmpd::agentaddress:
 - udp:161
simp_snmpd::manage_client: true
    EOH
  }
  let(:snmphieradata2) { <<-EOH2
---
simp_options::firewall: true
simp_options::syslog: true
simp_options::logrotate: true
simp_options::trusted_nets: ['ALL']
simp_snmpd::v3_users_hash:
  snmp_ro:
  bar:
    authpass: 'KeepItSecret'
    privpass: 'KeepItSafe'
  foo:
    authpass: 'KeepItSecret'
    privpass: 'KeepItSafe'
simp_snmpd::group_hash:
  foo_group:
    secname:
      - foo
  bar_group:
    secname:
      - bar
  readonly_group:
simp_snmpd::access_hash:
  bar:
    view:
      read: iso1
      write: iso1
    level: priv
    groups:
      - bar_group
  foo:
    view:
      read: newsystemview
    level: auth
    groups:
      - foo_group
  systemwrite:
simp_snmpd::view_hash:
  systemview:
  newsystemview:
    included:
      - '.1.3.6.1.2.1.1'
      - '.1.3.6.1.2.1.25'
simp_snmpd::system_info: false
simp_snmpd::agentaddress:
 - udp:127.0.0.1:161
 - udp:%{facts.fqdn}:161
 - tcp:%{facts.fqdn}:161
simp_snmpd::manage_client: true
    EOH2
  }

  context 'with default setting on snmpd agent and client installed' do
   hosts.each do |node|
      it 'should set the hiera data' do
        set_hieradata_on(node, snmphieradata, 'default')
      end

      it 'should work with no errors' do
        # apply twice becausel of rsyslog changes
        apply_manifest_on(node, manifest, :catch_failures => true)
        apply_manifest_on(node, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(node, manifest, :catch_changes => true)
      end

      it 'should return snmp data for users' do
        result = on(node, '/usr/bin/snmpwalk -u snmp_ro -X KeepItSafe -A KeepItSecret localhost sysLocation.0')
        expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Unknown")
        result = on(node, '/usr/bin/snmpwalk -u snmp_rw -X KeepItSafe -A KeepItSecret localhost .1')
        expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Unknown")
      end
      it 'should not work for undefined users' do
        result = on(node, '/usr/bin/snmpwalk -u snmp_rx -X KeepItSafe -A KeepItSecret localhost 0', { :acceptable_exit_codes => [0,1] })
        expect(result.exit_code).to_not eq(0)
        expect(result.stderr).to include("Unknown user name")
      end
    end
  end
  context 'with snmpd hiera hash updates' do
    hosts.each do |node|
      it 'should remove SNMPv3 users' do
        on(node,'service snmpd stop')
        on(node,'rm -rf /var/lib/net-snmp')
      end
    end
    hosts.each do |node|
      it 'should set the hiera data' do
        set_hieradata_on(node, snmphieradata2, 'default')
      end

      it 'should run with no errors' do
        apply_manifest_on(node, manifest, :catch_failures => true)
      end
#      puppet-snmp now includes location in snmpd.conf and you can't get rid
#      of it.  This makes the value unwritable and this test fails. If we want to test
#      writing we would have to write our writable MIB.
#      it 'should create bar user and give it write access' do
#        result = on(node, '/usr/bin/snmpset -u bar -X KeepItSafe -A KeepItSecret localhost sysLocation.0 s "Over the Rainbow"')
#        result = on(node, '/usr/bin/snmpwalk -u bar -X KeepItSafe -A KeepItSecret localhost sysLocation.0')
#        expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Over the Rainbow")
#      end
      it 'should create user foo and add give it read access with auth only' do
        result = on(node, '/usr/bin/snmpwalk -u foo -l authNoPriv -A KeepItSecret localhost sysLocation.0')
        expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Unknown")
      end
      it 'should not create  snmp_ro user' do
        result = on(node, '/usr/bin/snmpwalk -u snmp_ro -X KeepItSafe -A KeepItSecret localhost sysLocation.0', :accept_all_exit_codes => true)
        expect(result.stderr).to include("Unknown user name")
      end
    end
  end

context 'check remote' do
  hosts.each do |client|
    hosts.each do |remote|
        unless client == remote
          it "#{client}, should be able to query the remote server, #{remote}, over tcp" do
            result = on(client,"/usr/bin/snmpwalk -u foo -X KeepItSafe -A KeepItSecret tcp:#{remote}:161 sysLocation.0", :accept_all_exit_codes => true)
            expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Unknown")
          end
          it "#{client}, should be able to query the remote server, #{remote}, over udp" do
            result = on(client,"/usr/bin/snmpwalk -u foo -X KeepItSafe -A KeepItSecret udp:#{remote}:161 sysLocation.0", :accept_all_exit_codes => true)
            expect(result.stdout).to include("SNMPv2-MIB::sysLocation.0 = STRING: Unknown")
          end
        end
      end
    end
  end
end

