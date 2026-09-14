# @summary Renders config.yaml and the policy file
#
# @api private
class headscale::config {
  assert_private()

  $config_file = "${headscale::config_dir}/config.yaml"
  $policy_file = "${headscale::config_dir}/policy.hujson"
  $data_dir = $headscale::data_dir

  # Optional keys are only emitted when set; headscale treats an empty
  # string as unset for the ACME and TLS keys.
  $derp_server_addresses = {
    'ipv4' => $headscale::derp_server_ipv4,
    'ipv6' => $headscale::derp_server_ipv6,
  }.filter |$key, $value| { $value =~ NotUndef }

  $database_postgres = $headscale::database_postgres ? {
    undef   => {},
    default => { 'postgres' => $headscale::database_postgres },
  }

  $policy_path = $headscale::policy ? {
    undef   => '',
    default => $policy_file,
  }

  $settings = {
    'server_url'                     => $headscale::server_url,
    'listen_addr'                    => $headscale::listen_addr,
    'metrics_listen_addr'            => $headscale::metrics_listen_addr,
    'trusted_proxies'                => $headscale::trusted_proxies,
    'noise'                          => {
      'private_key_path' => "${data_dir}/noise_private.key",
    },
    'prefixes'                       => {
      'v4'         => $headscale::prefix_v4,
      'v6'         => $headscale::prefix_v6,
      'allocation' => $headscale::prefix_allocation,
    },
    'derp'                           => {
      'server'              => {
        'enabled'                                => $headscale::derp_server_enabled,
        'region_id'                              => $headscale::derp_server_region_id,
        'region_code'                            => $headscale::derp_server_region_code,
        'region_name'                            => $headscale::derp_server_region_name,
        'verify_clients'                         => true,
        'stun_listen_addr'                       => $headscale::derp_server_stun_listen_addr,
        'private_key_path'                       => "${data_dir}/derp_server_private.key",
        'automatically_add_embedded_derp_region' => true,
      } + $derp_server_addresses,
      'urls'                => $headscale::derp_urls,
      'paths'               => $headscale::derp_paths,
      'auto_update_enabled' => $headscale::derp_auto_update_enabled,
      'update_frequency'    => $headscale::derp_update_frequency,
    },
    'disable_check_updates'          => !$headscale::check_updates,
    'node'                           => {
      'expiry'    => $headscale::node_expiry,
      'ephemeral' => {
        'inactivity_timeout' => $headscale::ephemeral_inactivity_timeout,
      },
    },
    'database'                       => {
      'type'   => $headscale::database_type,
      'sqlite' => {
        'path'            => "${data_dir}/db.sqlite",
        'write_ahead_log' => true,
      },
    } + $database_postgres,
    'acme_url'                       => $headscale::acme_url,
    'acme_email'                     => $headscale::acme_email.lest || { '' },
    'tls_letsencrypt_hostname'       => $headscale::tls_letsencrypt_hostname.lest || { '' },
    'tls_letsencrypt_cache_dir'      => "${data_dir}/cache",
    'tls_letsencrypt_challenge_type' => $headscale::tls_letsencrypt_challenge_type,
    'tls_letsencrypt_listen'         => $headscale::tls_letsencrypt_listen,
    'tls_cert_path'                  => $headscale::tls_cert_path.lest || { '' },
    'tls_key_path'                   => $headscale::tls_key_path.lest || { '' },
    'log'                            => {
      'level'  => $headscale::log_level,
      'format' => $headscale::log_format,
    },
    'policy'                         => {
      'mode' => $headscale::policy_mode,
      'path' => $policy_path,
    },
    'dns'                            => {
      'magic_dns'          => $headscale::dns_magic_dns,
      'base_domain'        => $headscale::dns_base_domain,
      'override_local_dns' => $headscale::dns_override_local_dns,
      'nameservers'        => {
        'global' => $headscale::dns_nameservers,
        'split'  => $headscale::dns_split,
      },
      'search_domains'     => $headscale::dns_search_domains,
      'extra_records'      => $headscale::dns_extra_records,
    },
    'unix_socket'                    => $headscale::unix_socket,
    'unix_socket_permission'         => $headscale::unix_socket_permission,
    'logtail'                        => {
      'enabled' => $headscale::logtail_enabled,
    },
    'taildrop'                       => {
      'enabled' => $headscale::taildrop_enabled,
    },
    'auto_update'                    => {
      'enabled' => $headscale::node_auto_update_enabled,
    },
  }

  $config = deep_merge($settings, $headscale::override_options)

  file { $config_file:
    ensure    => file,
    owner     => 'root',
    group     => $headscale::group,
    mode      => $headscale::config_mode,
    content   => "# This file is managed by Puppet. Local changes will be overwritten.\n${stdlib::to_yaml($config)}",
    show_diff => false,
  }

  if $headscale::policy =~ NotUndef {
    $policy_content = $headscale::policy ? {
      Hash    => stdlib::to_json_pretty($headscale::policy),
      default => $headscale::policy,
    }

    # headscale re-reads the policy file on SIGHUP, so a policy change
    # only needs a reload, not the restart a config.yaml change causes.
    file { $policy_file:
      ensure  => file,
      owner   => 'root',
      group   => $headscale::group,
      mode    => $headscale::config_mode,
      content => $policy_content,
      notify  => Exec['headscale-reload-policy'],
    }

    exec { 'headscale-reload-policy':
      command     => "systemctl reload ${headscale::service_name}",
      path        => ['/bin', '/usr/bin'],
      refreshonly => true,
      onlyif      => "systemctl is-active --quiet ${headscale::service_name}",
    }
  }
}
