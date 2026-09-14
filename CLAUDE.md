# puppet-headscale

Puppet module for the headscale coordination server, following the
OpenVox [Beginner's guide to writing modules](https://docs.openvoxproject.org/openvox/latest/bgtm.html)
and modelled on [miharp/puppet-mattermost](https://github.com/miharp/puppet-mattermost).

## Testing

Unit tests and static checks with the voxbox container (no local Ruby needed):

```console
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 spec
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 validate lint check rubocop
docker run --rm -v "$PWD:/repo" ghcr.io/voxpupuli/voxbox:8 strings:generate:reference
```

Or with a local Ruby: `bundle install && bundle exec rake validate lint check rubocop spec`.

Acceptance tests (Beaker in a systemd container, downloads releases from GitHub):

```console
BEAKER_SETFILE=debian12-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
BEAKER_SETFILE=almalinux9-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
```

On Apple Silicon use the arm64 setfiles instead: `debian12-AARCH64`, `almalinux9-AARCH64`
(`DOCKER_DEFAULT_PLATFORM` is ignored by the docker-api gem).

Regenerate `REFERENCE.md` after changing parameters or doc comments.

## Architecture

- `manifests/init.pp` is the only parameterised class. It contains
  `repo -> install -> config ~> service`; install also notifies service;
  `install -> policy -> service` without notify.
- `install.pp` handles three `install_method`s: `deb` (archive downloads
  the official .deb, `package` with the dpkg provider and `ensure => latest`
  installs it, which upgrades when `version` changes), `binary` (archive
  downloads the release binary to `install_dir/headscale_<version>_linux_<arch>`,
  `binary_path` is a symlink to it), `package` (distribution or COPR).
  It also manages `config_dir` and `data_dir`.
- `config.pp` builds a hash mirroring upstream `config-example.yaml`,
  deep-merges `override_options`, and renders it with `stdlib::to_yaml`.
- `policy.pp` renders `policy.hujson` and reloads (SIGHUP) on change. It
  is a separate class because `config ~> service` would turn any change
  inside `config` into a restart; `policy` is ordered before `service`
  with no notify.
- `service.pp` writes the unit (from `templates/headscale.service.epp`,
  a copy of upstream's hardened unit) for binary installs, or a drop-in
  adding `ReadWritePaths=<data_dir>` for packaged units.
- OS defaults live in `data/<family>.yaml` via `hiera.yaml`: Debian
  family uses `deb`, Arch uses `package`, everything else `binary`.

## Conventions

- Parameters use `thing_property` naming (`service_ensure`,
  `package_name`) and `manage_*` toggles; every parameter has a
  `@param` doc comment in init.pp.
- Static defaults are inline in init.pp; only OS-specific defaults go
  in `data/`.
- Sub-classes are `@api private`, call `assert_private()`, and read
  `$headscale::<param>`; they take no parameters.
- Align `=>` within resource blocks and hash literals (puppet-lint).
- Specs iterate `on_supported_os`; per-family behaviour is asserted in
  a `case os_facts[:os]['family']` block.
- Keep `CHANGELOG.md` (Keep a Changelog) up to date under Unreleased.
