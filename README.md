# puppet-headscale

[![CI](https://github.com/miharp/puppet-headscale/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-headscale/actions/workflows/ci.yml)
[![OpenVox compatible](https://img.shields.io/badge/OpenVox-%3E%3D%208.0-orange.svg)](https://voxpupuli.org/openvox/)
[![License](https://img.shields.io/github/license/miharp/puppet-headscale)](https://github.com/miharp/puppet-headscale/blob/main/LICENSE)

[![Puppet Forge](https://img.shields.io/puppetforge/v/miharp/headscale)](https://forge.puppet.com/modules/miharp/headscale)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/miharp/headscale)](https://forge.puppet.com/modules/miharp/headscale)

## Table of Contents

1. [Description](#description)
1. [Setup](#setup)
1. [Usage](#usage)
1. [Reference](#reference)
1. [Limitations](#limitations)
1. [Development](#development)

## Description

Installs and configures [headscale](https://headscale.net/), the
self-hosted implementation of the Tailscale control server, following
the [official installation guide](https://headscale.net/stable/setup/install/official/):

* on Debian 12+ and Ubuntu 22.04+, downloads the official `.deb` from
  the GitHub releases page and installs it with dpkg; the package
  creates the `headscale` user and ships the systemd unit
* on the RedHat family (and any other Linux), downloads the official
  release binary into a versioned path, and manages the `headscale`
  system user and a hardened systemd unit (the upstream unit); raising
  `version` upgrades in place
* on Arch Linux, installs the `headscale` package from the `extra`
  repository; the RedHat family can also use the community
  [COPR](https://copr.fedorainfracloud.org/coprs/jonathanspw/headscale/)
  with `install_method => 'package'` and `manage_repo => true`
* renders `/etc/headscale/config.yaml` from parameters that mirror the
  upstream example configuration, with `override_options` deep-merged
  over it for anything without a dedicated parameter (OIDC, PostgreSQL,
  tuning)
* optionally renders a policy file (ACLs, grants, SSH) and reloads
  headscale when it changes
* manages the `headscale` systemd service

The module's responsibility is the headscale server. It does **not**
manage a reverse proxy, TLS certificates (beyond headscale's built-in
Let's Encrypt client), DERP servers or the Tailscale clients; pair it
with an nginx or Caddy module for a production deployment.

## Setup

### What headscale affects

* The `headscale` package (`.deb`, distribution package) or the release
  binary under `/opt/headscale` (`install_dir`) with `/usr/local/bin/headscale`
  (`binary_path`) linked to the current version
* The `headscale` system user and group on binary installs
  (`manage_user`)
* `/etc/headscale/config.yaml` (`config_dir`), owned by root and the
  `headscale` group, mode 0640, since it may contain OIDC or database
  secrets, and `/etc/headscale/policy.hujson` when `policy` is set
* `/var/lib/headscale` (`data_dir`), holding the private keys, the SQLite
  database and the Let's Encrypt cache
* `/etc/systemd/system/headscale.service` on binary installs, or a
  drop-in for the packaged unit that opens `data_dir` in the unit's
  sandbox
* The `headscale` service
* With `manage_repo => true` on the RedHat family, the `headscale`
  yum repository

### Beginning with headscale

```puppet
class { 'headscale':
  server_url      => 'https://headscale.example.com',
  listen_addr     => '127.0.0.1:8080',
  trusted_proxies => ['127.0.0.1/32'],
  dns_base_domain => 'tailnet.example.com',
}
```

This installs headscale with the OS default install method, listening
on localhost for a TLS-terminating reverse proxy on the same host, with
MagicDNS names under `tailnet.example.com`. `dns_base_domain` must be
different from the `server_url` domain.

Register the first node with a pre-authentication key:

```console
headscale users create alice
headscale preauthkeys create --user alice --reusable --expiration 1h
tailscale up --login-server https://headscale.example.com --authkey <key>
```

## Usage

### Serving TLS directly with Let's Encrypt

Without a reverse proxy, headscale can obtain its own certificate. It
then needs to listen on port 443 (the managed unit grants
`CAP_NET_BIND_SERVICE`) and, for the HTTP-01 challenge, port 80:

```puppet
class { 'headscale':
  server_url               => 'https://headscale.example.com',
  listen_addr              => '0.0.0.0:443',
  tls_letsencrypt_hostname => 'headscale.example.com',
  acme_email               => 'admin@example.com',
  dns_base_domain          => 'tailnet.example.com',
}
```

### Access control policy

`policy` is rendered to `/etc/headscale/policy.hujson` and headscale is
reloaded (not restarted) when it changes. A hash is rendered as JSON;
pass a string to write HuJSON with comments verbatim:

```puppet
class { 'headscale':
  server_url      => 'https://headscale.example.com',
  dns_base_domain => 'tailnet.example.com',
  policy          => {
    'tagOwners' => { 'tag:server' => ['alice@'] },
    'grants'    => [
      { 'src' => ['autogroup:member'], 'dst' => ['tag:server'], 'ip' => ['22', '443'] },
    ],
  },
}
```

Set `policy_mode => 'database'` to manage the policy with
`headscale policy set` instead.

### Settings without a parameter

`override_options` is deep-merged over the generated configuration, so
any key of the [upstream configuration](https://headscale.net/stable/ref/configuration/)
can be set:

```puppet
class { 'headscale':
  server_url       => 'https://headscale.example.com',
  dns_base_domain  => 'tailnet.example.com',
  override_options => {
    'oidc'   => {
      'issuer'          => 'https://sso.example.com',
      'client_id'       => 'headscale',
      'client_secret'   => 'supersecret',
      'allowed_domains' => ['example.com'],
    },
    'tuning' => { 'node_store_batch_size' => 200 },
  },
}
```

### Pinning and upgrading

`version` selects the release for the `deb` and `binary` install
methods and defaults to a recent release. Raising it downloads the new
release and restarts the service; binary installs keep the previous
binary in `install_dir` for rollback. `download_checksum` verifies the
download against the SHA-256 from the release's `checksums.txt`:

```puppet
class { 'headscale':
  version           => '0.29.3',
  download_checksum => '4f5b...e1a2',
  server_url        => 'https://headscale.example.com',
  dns_base_domain   => 'tailnet.example.com',
}
```

For `install_method => 'package'`, pin with `package_ensure` instead.

### Binary installs on the Debian family

The install method defaults per OS (`deb` on the Debian family,
`package` on Arch Linux, `binary` elsewhere) but can be forced:

```puppet
class { 'headscale':
  install_method  => 'binary',
  manage_user     => true,
  binary_path     => '/usr/local/bin/headscale',
  server_url      => 'https://headscale.example.com',
  dns_base_domain => 'tailnet.example.com',
}
```

## Reference

See [REFERENCE.md](REFERENCE.md), generated with
[puppet-strings](https://github.com/puppetlabs/puppet-strings):

```console
bundle exec rake strings:generate:reference
```

## Limitations

* Debian 12/13, Ubuntu 22.04/24.04, the RedHat family (RHEL, Rocky,
  AlmaLinux, Oracle Linux, CentOS Stream) 9/10 and Arch Linux, on amd64
  and arm64 (the architectures headscale publishes releases for).
* headscale only publishes `.deb` packages; the RedHat family defaults
  to the release binary. The COPR repository used with `manage_repo`
  is maintained by the community and can lag behind upstream releases.
* The configuration is rendered in full from the module's parameters.
  Local edits to `config.yaml` are overwritten; use `override_options`.
  Upstream configuration keys change between headscale minor releases,
  so check the release notes when raising `version` across a minor.
* `config.yaml` is not validated at catalog time. `headscale configtest`
  initialises the server as the calling user, which would create the
  private keys as root, so the module does not run it as a
  `validate_cmd`; a broken configuration surfaces as a failed service
  start.
* The module does not open firewall ports (443, 80 for HTTP-01, and
  UDP 3478 for the embedded DERP server) or manage SELinux policy.
* PostgreSQL is discouraged upstream and the module only writes the
  connection settings (`database_postgres`); it does not create the
  database.

## Development

Pull requests welcome on
[GitHub](https://github.com/miharp/puppet-headscale). Run the unit test
suite and static checks with:

```console
bundle install
bundle exec rake validate lint check rubocop
bundle exec rake spec
```

or, without a local Ruby, with the
[voxbox](https://github.com/voxpupuli/container-voxbox) container:

```console
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 spec
```

Acceptance tests use [Beaker](https://github.com/voxpupuli/beaker) via
[voxpupuli-acceptance](https://github.com/voxpupuli/voxpupuli-acceptance),
following the [OpenVox acceptance testing
guide](https://docs.openvoxproject.org/ecosystem/latest/devkit/acceptance_testing.html).
They apply the module to a systemd container, verify idempotency, probe
the health endpoint and the CLI, and check that a policy change reloads
rather than restarts the service:

```console
BEAKER_SETFILE=debian12-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
BEAKER_SETFILE=almalinux9-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
```

Set `HEADSCALE_INSTALL_METHOD=binary` to exercise the binary install
method on a Debian-family host as well.

On Apple Silicon use the arm64 images instead (headscale publishes arm64
releases, and the amd64 base images cannot be pulled through the Docker
API on an arm64 host):

```console
BEAKER_SETFILE=debian12-AARCH64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
BEAKER_SETFILE=almalinux9-AARCH64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
```

CI runs the same checks through the
[voxpupuli/gha-puppet](https://github.com/voxpupuli/gha-puppet) reusable
workflow, which builds its acceptance matrix from `metadata.json` and
tests against the OpenVox 8 collection.
