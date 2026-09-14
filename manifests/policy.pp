# @summary Renders the policy file and reloads headscale when it changes
#
# Kept apart from headscale::config because that class notifies the
# service: a policy change only needs the SIGHUP reload headscale
# supports, not a restart.
#
# @api private
class headscale::policy {
  assert_private()

  if $headscale::policy =~ NotUndef {
    $policy_content = $headscale::policy ? {
      Hash    => stdlib::to_json_pretty($headscale::policy),
      default => $headscale::policy,
    }

    file { "${headscale::config_dir}/policy.hujson":
      ensure  => file,
      owner   => 'root',
      group   => $headscale::group,
      mode    => $headscale::config_mode,
      content => $policy_content,
      notify  => Exec['headscale-reload-policy'],
    }

    # On the first run the service is not active yet and the reload is
    # skipped; the service then starts with the policy in place.
    exec { 'headscale-reload-policy':
      command     => "systemctl reload ${headscale::service_name}",
      path        => ['/bin', '/usr/bin'],
      refreshonly => true,
      onlyif      => "systemctl is-active --quiet ${headscale::service_name}",
    }
  }
}
