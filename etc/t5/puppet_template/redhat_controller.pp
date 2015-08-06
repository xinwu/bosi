
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

# make sure known_hosts is cleaned up
file { "/root/.ssh/known_hosts":
    ensure => absent,
}

# reserve keystone ephemeral port
exec { "reserve keystone port":
    command => "sysctl -w 'net.ipv4.ip_local_reserved_ports=49000,35357,41055,58882'",
    path    => $binpath,
}
file_line { "reserve keystone port":
    path  => '/etc/sysctl.conf',
    line  => 'net.ipv4.ip_local_reserved_ports=49000,35357,41055,58882',
    match => '^net.ipv4.ip_local_reserved_ports.*$',
}

# purge bcf controller public key
exec { 'purge bcf key':
    command => "rm -rf /var/lib/neutron/host_certs/*",
    path    => $binpath,
    notify  => Service['neutron-server'],
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'router',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '1',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf allow_automatic_l3agent_failover":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'allow_automatic_l3agent_failover',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron.conf l3_ha":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'l3_ha',
  value             => 'False',
  notify            => Service['neutron-server'],
}

# config /etc/neutron/plugin.ini
ini_setting { "neutron plugin.ini firewall_driver":
  ensure            => present,
  path              => '/etc/neutron/plugin.ini',
  section           => 'securitygroup',
  key_val_separator => '=',
  setting           => 'firewall_driver',
  value             => 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',
  notify            => Service['neutron-server'],
}
ini_setting { "neutron plugin.ini enable_security_group":
  ensure            => present,
  path              => '/etc/neutron/plugin.ini',
  section           => 'securitygroup',
  key_val_separator => '=',
  setting           => 'enable_security_group',
  value             => 'True',
  notify            => Service['neutron-server'],
}
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# config /etc/neutron/plugins/ml2/ml2_conf.ini 
ini_setting { "ml2 type dirvers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'type_drivers',
  value             => 'vlan',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 tenant network types":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'tenant_network_types',
  value             => 'vlan',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 tenant network vlan ranges":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2_type_vlan',
  key_val_separator => '=',
  setting           => 'network_vlan_ranges',
  value             => '%(network_vlan_ranges)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 mechanism drivers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'ml2',
  key_val_separator => '=',
  setting           => 'mechanism_drivers',
  value             => 'openvswitch, bsn_ml2',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy ssl cert directory":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'ssl_cert_directory',
  value             => '/var/lib/neutron',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy servers":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'servers',
  value             => '%(bcf_controllers)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy server auth":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_auth',
  value             => '%(bcf_controller_user)s:%(bcf_controller_passwd)s',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy server ssl":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'server_ssl',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy auto sync on failure":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'auto_sync_on_failure',
  value             => 'True',
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy consistency interval":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'consistency_interval',
  value             => 60,
  notify            => Service['neutron-server'],
}
ini_setting { "ml2 restproxy neutron_id":
  ensure            => present,
  path              => '/etc/neutron/plugins/ml2/ml2_conf.ini',
  section           => 'restproxy',
  key_val_separator => '=',
  setting           => 'neutron_id',
  value             => %(neutron_id)s,
  notify            => Service['neutron-server'],
}

# change ml2 ownership
file { '/etc/neutron/plugins/ml2':
  owner   => neutron,
  group   => neutron,
  recurse => true,
  notify  => Service['neutron-server'],
}

service { 'neutron-server':
  ensure     => running,
  enable     => true,
}

