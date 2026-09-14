# @summary Manages the headscale service
#
# @api private
class headscale::service {
  assert_private()

  if $headscale::service_manage {
    if $headscale::install_method == 'binary' {
      # Binary installs ship no systemd unit.
      file { "/etc/systemd/system/${headscale::service_name}.service":
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => epp('headscale/headscale.service.epp', {
          'binary_path' => $headscale::binary_path,
          'user'        => $headscale::user,
          'group'       => $headscale::group,
          'data_dir'    => $headscale::data_dir,
        }),
        notify  => Service[$headscale::service_name],
      }
    } else {
      # The packaged unit sandboxes the service with ProtectSystem=strict
      # and only opens /var/lib/headscale; a drop-in opens data_dir in
      # case it was moved.
      file { "/etc/systemd/system/${headscale::service_name}.service.d":
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }

      file { "/etc/systemd/system/${headscale::service_name}.service.d/puppet.conf":
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "# This file is managed by Puppet.\n[Service]\nReadWritePaths=${headscale::data_dir}\n",
        notify  => Service[$headscale::service_name],
      }
    }

    service { $headscale::service_name:
      ensure => $headscale::service_ensure,
      enable => $headscale::service_enable,
    }
  }
}
