# @summary Manages the community COPR yum repository for headscale
#
# @api private
class headscale::repo {
  assert_private()

  if $headscale::manage_repo {
    unless $facts['os']['family'] == 'RedHat' {
      fail("headscale: no yum repository is available for the ${facts['os']['family']} family; use install_method 'deb' or 'binary'")
    }

    yumrepo { 'headscale':
      descr               => 'Copr repo for headscale owned by jonathanspw',
      baseurl             => $headscale::repo_baseurl,
      enabled             => '1',
      gpgcheck            => '1',
      gpgkey              => $headscale::repo_gpgkey,
      repo_gpgcheck       => '0',
      skip_if_unavailable => '1',
    }
  }
}
