
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

# assign ip to ivs internal port
define ivs_internal_port_ip {
    $port_ip = split($name, ',')
    file_line { "ifconfig ${port_ip[0]} up":
        path  => '/etc/rc.local',
        line  => "ifconfig ${port_ip[0]} up",
        match => "^ifconfig ${port_ip[0]} up",
    }->
    file_line { "ip link set ${port_ip[0]} up":
        path  => '/etc/rc.local',
        line  => "ip link set ${port_ip[0]} up",
        match => "^ip link set ${port_ip[0]} up",
    }->
    file_line { "ifconfig ${port_ip[0]} ${port_ip[1]}":
        path  => '/etc/rc.local',
        line  => "ifconfig ${port_ip[0]} ${port_ip[1]}",
        match => "^ifconfig ${port_ip[0]} ${port_ip[1]}$",
    }
}
# example ['storage,192.168.1.1/24', 'ex,192.168.2.1/24', 'management,192.168.3.1/24']
class ivs_internal_port_ips {
    $port_ips = [%(port_ips)s]
    $default_gw = "%(default_gw)s"
    file { "/etc/rc.local":
        ensure  => file,
        mode    => 0777,
    }->
    file_line { "remove exit 0":
        path    => '/etc/rc.local',
        ensure  => absent,
        line    => "exit 0",
    }->
    file_line { "restart ivs":
        path    => '/etc/rc.local',
        line    => "service ivs restart",
        match   => "^service ivs restart$",
    }->
    file_line { "sleep 2":
        path    => '/etc/rc.local',
        line    => "sleep 2",
        match   => "^sleep 2$",
    }->
    ivs_internal_port_ip { $port_ips:
    }->
    file_line { "clear default gw":
        path    => '/etc/rc.local',
        line    => "ip route del default",
        match   => "^ip route del default$",
    }->
    file_line { "add default gw":
        path    => '/etc/rc.local',
        line    => "ip route add default via ${default_gw}",
        match   => "^ip route add default via ${default_gw}$",
    }->
    file_line { "add exit 0":
        path    => '/etc/rc.local',
        line    => "exit 0",
    }
}
include ivs_internal_port_ips

# ivs configruation and service
file { '/etc/default/ivs':
    ensure  => file,
    mode    => 0644,
    content => "%(ivs_daemon_args)s",
    notify  => Service['ivs'],
}
service { 'ivs':
    ensure     => 'running',
    provider   => 'upstart',
    hasrestart => 'true',
    hasstatus  => 'true',
    subscribe  => File['/etc/default/ivs'],
}

package { 'apport':
    ensure  => 'running',
}

# load 8021q module on boot
package { 'vlan':
    ensure  => latest,
}
file_line {'load 8021q on boot':
    path    => '/etc/modules',
    line    => '8021q',
    match   => '^8021q$',
    require => Package['vlan'],
}
exec { "load 8021q":
    command => "modprobe 8021q",
    path    => $binpath,
    require => Package['vlan'],
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf debug":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'debug',
  value             => 'True',
}
ini_setting { "neutron.conf report_interval":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'report_interval',
  value             => '60',
}
ini_setting { "neutron.conf agent_down_time":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'agent_down_time',
  value             => '150',
}
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'bsn_l3,lbaas',
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '1',
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
}
ini_setting { "ensure absent of neutron.conf service providers":
  ensure            => absent,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
}->
ini_setting { "neutron.conf service providers":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
  value             => 'LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default',
}

# config neutron-bsn-agent conf
file { '/etc/init/neutron-bsn-agent.conf':
    ensure => present,
    content => "
description \"Neutron BSN Agent\"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    exec /usr/local/bin/neutron-bsn-agent --config-file=/etc/neutron/neutron.conf --config-file=/etc/neutron/plugins/ml2/ml2_conf.ini --log-file=/var/log/neutron/neutron-bsn-agent.log
end script
",
}
file { '/etc/init.d/neutron-bsn-agent':
    ensure => link,
    target => '/lib/init/upstart-job',
    notify => Service['neutron-bsn-agent'],
}
service {'neutron-bsn-agent':
    ensure     => 'running',
    provider   => 'upstart',
    hasrestart => 'true',
    hasstatus  => 'true',
    subscribe  => [File['/etc/init/neutron-bsn-agent.conf'], File['/etc/init.d/neutron-bsn-agent']],
}

# stop and disable neutron-plugin-openvswitch-agent
service { 'neutron-plugin-openvswitch-agent':
  ensure   => 'stopped',
  enable   => false,
  provider => 'upstart',
}

# disable l3 agent
ini_setting { "l3 agent disable metadata proxy":
  ensure            => present,
  path              => '/etc/neutron/l3_agent.ini',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'enable_metadata_proxy',
  value             => 'False',
}
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# dhcp configuration
if %(deploy_dhcp_agent)s {
    service { "neutron-dhcp-agent":
        ensure            => running,
        enable            => true,
    }
    ini_setting { "dhcp agent resync_interval":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'resync_interval',
        value             => '60',
        notify            => Service['neutron-dhcp-agent'],
    }
    ini_setting { "dhcp agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.IVSInterfaceDriver',
        notify            => Service['neutron-dhcp-agent'],
    }
    ini_setting { "dhcp agent dhcp driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_driver',
        value             => 'bsnstacklib.plugins.bigswitch.dhcp_driver.DnsmasqWithMetaData',
        notify            => Service['neutron-dhcp-agent'],
    }
    ini_setting { "dhcp agent enable isolated metadata":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_isolated_metadata',
        value             => 'True',
        notify            => Service['neutron-dhcp-agent'],
    }
    ini_setting { "dhcp agent disable metadata network":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_metadata_network',
        value             => 'False',
        notify            => Service['neutron-dhcp-agent'],
    }
    ini_setting { "dhcp agent disable dhcp_delete_namespaces":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_delete_namespaces',
        value             => 'False',
        notify            => Service['neutron-dhcp-agent'],
    }
}

# haproxy
if %(deploy_haproxy)s {
    package { "neutron-lbaas-agent":
        ensure  => installed,
    }
    package { "haproxy":
        ensure  => installed,
    }
    ini_setting { "haproxy agent periodic interval":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'periodic_interval',
        value             => '10',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.IVSInterfaceDriver',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent device driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'device_driver',
        value             => 'neutron.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver',
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
        notify            => Service['neutron-lbaas-agent'],
    }
    service { "haproxy":
        ensure            => running,
        enable            => true,
        require           => Package['haproxy'],
    }
    service { "neutron-lbaas-agent":
        ensure            => running,
        enable            => true,
        require           => [Package['neutron-lbaas-agent'], Package['haproxy']],
    }
}

