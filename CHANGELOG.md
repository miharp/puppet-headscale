# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-09-15

### Added

- README pointer to the `blockops/tailscale` module for enrolling clients
  against headscale.
- The acceptance suite prints the headscale journal when a check fails.

### Fixed

- The policy reload no longer races the service start. On the Debian
  family the `.deb` postinst starts headscale immediately, and the
  reload's SIGHUP could reach the process before its signal handler
  was installed, killing it; the reload now runs after the service and
  only when the running instance is older than the policy file.

## [0.1.0] - 2026-09-15

### Added

- Initial module: installs headscale from the official `.deb` (Debian
  family), the release binary (RedHat family and others, versioned with
  in-place upgrades) or a distribution package (Arch Linux, or the
  community COPR on the RedHat family with `manage_repo`).
- `config.yaml` rendered from parameters mirroring the upstream example
  configuration, with `override_options` deep-merged over it.
- Optional policy file (`policy`) applied with a service reload.
- Management of the `headscale` user, directories, systemd unit (binary
  installs) or a drop-in for the packaged unit, and the service.
- `download_options` (default: curl retries transient errors three times),
  since GitHub release downloads intermittently answer 5xx.
- `binary_path` defaults to `/usr/bin/headscale` for every install method,
  matching upstream's binary install and keeping `sudo headscale` on the
  RedHat family's sudo `secure_path`.

[Unreleased]: https://github.com/miharp/puppet-headscale/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/miharp/puppet-headscale/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/miharp/puppet-headscale/releases/tag/v0.1.0
