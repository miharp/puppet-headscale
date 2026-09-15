# @summary Renders the policy file and reloads headscale when it changes
#
# Kept apart from headscale::config because that class notifies the
# service: a policy change only needs the SIGHUP reload headscale
# supports, not a restart.
#
# The policy file is written before the service so a first start finds
# it, but the reload runs after the service and only when the running
# instance predates the policy file. The .deb's postinst starts headscale
# as soon as it is installed, and a SIGHUP sent to a process that has not
# yet installed its signal handler kills it (systemd counts that as a
# clean exit and restarts it later), which raced Puppet's own service
# start on the Debian family.
#
# @api private
class headscale::policy {
  assert_private()

  if $headscale::policy =~ NotUndef {
    $policy_file = "${headscale::config_dir}/policy.hujson"
    $service = $headscale::service_name

    $policy_content = $headscale::policy ? {
      Hash    => stdlib::to_json_pretty($headscale::policy),
      default => $headscale::policy,
    }

    file { $policy_file:
      ensure  => file,
      owner   => 'root',
      group   => $headscale::group,
      mode    => $headscale::config_mode,
      content => $policy_content,
      before  => Class['headscale::service'],
      notify  => Exec['headscale-reload-policy'],
    }

    # A service (re)started after the policy was written has already
    # read it, so only an instance older than the file is reloaded.
    exec { 'headscale-reload-policy':
      command     => "systemctl reload ${service}",
      path        => ['/bin', '/usr/bin'],
      provider    => shell,
      refreshonly => true,
      onlyif      => [
        "systemctl is-active --quiet ${service}",
        "test $(stat -c %Y ${policy_file}) -gt $(date -d \"$(systemctl show -p ActiveEnterTimestamp --value ${service})\" +%s)",
      ],
      require     => Class['headscale::service'],
    }
  }
}
