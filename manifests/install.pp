# @summary Installs the headscale binary or package
#
# @api private
class headscale::install {
  assert_private()

  $version = $headscale::version

  case $facts['os']['architecture'] {
    'x86_64', 'amd64': { $arch = 'amd64' }
    'aarch64', 'arm64': { $arch = 'arm64' }
    default: {
      $arch = undef
    }
  }

  $release_url = "https://github.com/juanfont/headscale/releases/download/v${version}"

  $checksum_type = $headscale::download_checksum ? {
    undef   => 'none',
    default => 'sha256',
  }

  case $headscale::install_method {
    'package': {
      package { $headscale::package_name:
        ensure => $headscale::package_ensure,
      }

      if $headscale::manage_repo {
        Yumrepo['headscale'] -> Package[$headscale::package_name]
      }

      # The package creates the headscale user.
      $owner_require = Package[$headscale::package_name]
    }
    'deb': {
      unless $facts['os']['family'] == 'Debian' {
        fail("headscale: install_method 'deb' is only available on the Debian family, not ${facts['os']['family']}; use 'binary'")
      }

      if $arch =~ Undef {
        fail("headscale: no headscale release exists for architecture '${facts['os']['architecture']}'")
      }

      $deb_file = "headscale_${version}_linux_${arch}.deb"
      $deb_path = "/var/tmp/${deb_file}"

      archive { $deb_path:
        source           => pick($headscale::download_url, "${release_url}/${deb_file}"),
        checksum         => $headscale::download_checksum,
        checksum_type    => $checksum_type,
        download_options => $headscale::download_options,
        extract          => false,
      }

      # The dpkg provider is not versionable, but 'latest' compares the
      # installed version with the version inside the .deb, so raising
      # `version` (a new .deb path) upgrades in place.
      package { $headscale::package_name:
        ensure   => latest, # lint:ignore:package_ensure
        provider => dpkg,
        source   => $deb_path,
        require  => Archive[$deb_path],
      }

      # The package creates the headscale user.
      $owner_require = Package[$headscale::package_name]
    }
    'binary': {
      if $arch =~ Undef {
        fail("headscale: no headscale release exists for architecture '${facts['os']['architecture']}'")
      }

      if $headscale::manage_user {
        group { $headscale::group:
          ensure => present,
          system => true,
        }

        user { $headscale::user:
          ensure => present,
          system => true,
          gid    => $headscale::group,
          home   => $headscale::data_dir,
          shell  => '/usr/sbin/nologin',
        }

        $owner_require = User[$headscale::user]
      } else {
        $owner_require = undef
      }

      # Each version is downloaded to its own file and binary_path is a
      # symlink to the current one, so raising `version` installs the
      # new release alongside the old and flips the link (the previous
      # binary is kept for rollback).
      $binary_file = "headscale_${version}_linux_${arch}"
      $versioned_binary = "${headscale::install_dir}/${binary_file}"

      file { $headscale::install_dir:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }

      archive { $versioned_binary:
        source           => pick($headscale::download_url, "${release_url}/${binary_file}"),
        checksum         => $headscale::download_checksum,
        checksum_type    => $checksum_type,
        download_options => $headscale::download_options,
        extract          => false,
        require          => File[$headscale::install_dir],
      }

      file { $versioned_binary:
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => Archive[$versioned_binary],
      }

      file { $headscale::binary_path:
        ensure  => link,
        target  => $versioned_binary,
        require => File[$versioned_binary],
      }
    }
    default: {
      fail("headscale: unsupported install_method '${headscale::install_method}'")
    }
  }

  # config.yaml may hold secrets: readable by root and the service group only.
  file { $headscale::config_dir:
    ensure  => directory,
    owner   => 'root',
    group   => $headscale::group,
    mode    => '0750',
    require => $owner_require,
  }

  # Private keys, the SQLite database and the ACME cache live here.
  file { $headscale::data_dir:
    ensure  => directory,
    owner   => $headscale::user,
    group   => $headscale::group,
    mode    => '0750',
    require => $owner_require,
  }
}
