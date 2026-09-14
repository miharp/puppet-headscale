# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
