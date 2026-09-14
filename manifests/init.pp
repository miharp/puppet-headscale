# @summary Installs and configures a headscale coordination server
#
# Installs headscale, the self-hosted Tailscale control server, from the
# official .deb on the GitHub releases page (Debian family), from the
# release binary (any Linux; default on the RedHat family, where there
# is no official package) or from a distribution package (Arch Linux, or
# the RedHat family with the community COPR repository), renders
# `/etc/headscale/config.yaml` and an optional policy file, and manages
# the `headscale` systemd service.
#
# Binary installs are versioned: each release is downloaded to
# `${install_dir}/headscale_${version}_linux_${arch}` and `binary_path`
# is a symlink to the current one, so raising `version` upgrades in
# place (download, link flip, service restart) and the previous binary
# remains for rollback. Package installs from the .deb upgrade the same
# way: a new .deb is downloaded and installed when `version` changes.
#
# Every key of the upstream example configuration that has a sensible
# static default is exposed as a parameter; anything else (OIDC,
# PostgreSQL, tuning) can be set through `override_options`, which is
# deep-merged over the generated configuration.
#
# @example Minimal usage
#   class { 'headscale':
#     server_url      => 'https://headscale.example.com',
#     listen_addr     => '0.0.0.0:8080',
#     dns_base_domain => 'tailnet.example.com',
#   }
#
# @example Behind a reverse proxy with a policy file and OIDC
#   class { 'headscale':
#     server_url       => 'https://headscale.example.com',
#     listen_addr      => '127.0.0.1:8080',
#     trusted_proxies  => ['127.0.0.1/32'],
#     dns_base_domain  => 'tailnet.example.com',
#     policy           => {
#       'grants' => [
#         { 'src' => ['autogroup:member'], 'dst' => ['autogroup:member'], 'ip' => ['*'] },
#       ],
#     },
#     override_options => {
#       'oidc' => {
#         'issuer'        => 'https://sso.example.com',
#         'client_id'     => 'headscale',
#         'client_secret' => 'supersecret',
#       },
#     },
#   }
#
# @param version
#   The headscale version to install, e.g. '0.29.3'. Used to build the
#   download URL for the 'deb' and 'binary' install methods; ignored for
#   'package' (use package_ensure to pin a distribution package).
# @param install_method
#   How to install headscale. 'deb' downloads the official .deb from the
#   GitHub releases page and installs it with dpkg (default on the Debian
#   family). 'binary' downloads the official release binary and manages
#   the headscale user and systemd unit (default everywhere else).
#   'package' installs a distribution package (default on Arch Linux;
#   with manage_repo on the RedHat family it uses the community COPR).
# @param download_url
#   URL of the .deb or binary to download. Defaults to the official
#   GitHub release asset for `version` and the node's architecture.
# @param download_checksum
#   SHA-256 checksum of the downloaded .deb or binary, from the
#   `checksums.txt` of the release. Verified when set; the download is
#   not checksummed otherwise.
# @param install_dir
#   Directory the versioned binaries are stored in with install_method
#   'binary'.
# @param binary_path
#   Path of the headscale executable. With install_method 'binary' this
#   is a symlink to the versioned binary in install_dir; with the other
#   methods it is where the package installs the binary.
# @param manage_repo
#   Whether to manage the community COPR yum repository for
#   install_method 'package'. Only applies to the RedHat family.
# @param repo_baseurl
#   Base URL of the yum repository managed with manage_repo.
# @param repo_gpgkey
#   URL of the GPG key of the yum repository managed with manage_repo.
# @param package_name
#   Name of the package to install.
# @param package_ensure
#   Ensure value of the package with install_method 'package', e.g.
#   'installed', 'latest' or a version.
# @param manage_user
#   Whether to manage the headscale system user and group. Defaults to
#   true except on the Debian family and Arch Linux, where the package
#   creates them.
# @param user
#   System user headscale runs as and that owns the data directory.
# @param group
#   Group of the headscale user.
# @param config_dir
#   Directory of config.yaml and the policy file.
# @param config_mode
#   Mode of config.yaml. It is owned by root and the headscale group,
#   and may contain secrets (OIDC, PostgreSQL).
# @param data_dir
#   Directory headscale keeps its state in: private keys, the SQLite
#   database, the Let's Encrypt cache.
# @param server_url
#   The URL clients connect to, typically 'https://headscale.example.com'.
# @param listen_addr
#   Address and port headscale listens on for clients.
# @param metrics_listen_addr
#   Address and port of the /metrics and /debug endpoints. Keep this
#   private; an empty string disables the listener.
# @param trusted_proxies
#   CIDRs of reverse proxies whose X-Forwarded-For and similar headers
#   are honoured.
# @param prefix_v4
#   IPv4 prefix tailnet addresses are allocated from. Must be a subset of
#   100.64.0.0/10.
# @param prefix_v6
#   IPv6 prefix tailnet addresses are allocated from. Must be a subset of
#   fd7a:115c:a1e0::/48.
# @param prefix_allocation
#   Strategy for allocating node IPs: 'sequential' or 'random'.
# @param derp_server_enabled
#   Whether to run the embedded DERP relay. Requires server_url to use
#   HTTPS.
# @param derp_server_region_id
#   Region ID of the embedded DERP server.
# @param derp_server_region_code
#   Region code of the embedded DERP server, shown in the Tailscale UI.
# @param derp_server_region_name
#   Region name of the embedded DERP server, shown in the Tailscale UI.
# @param derp_server_stun_listen_addr
#   UDP address the embedded DERP server answers STUN requests on.
# @param derp_server_ipv4
#   Public IPv4 address to publish for the embedded DERP server.
# @param derp_server_ipv6
#   Public IPv6 address to publish for the embedded DERP server.
# @param derp_urls
#   URLs of DERP maps to present to clients.
# @param derp_paths
#   Local DERP map files to present to clients.
# @param derp_auto_update_enabled
#   Whether to periodically refresh the DERP map from derp_urls.
# @param derp_update_frequency
#   How often to refresh the DERP map, e.g. '3h'.
# @param check_updates
#   Whether headscale checks for new releases at startup.
# @param node_expiry
#   Default key expiry for untagged nodes, e.g. '180d'. 0 disables
#   expiry.
# @param ephemeral_inactivity_timeout
#   Time before an inactive ephemeral node is deleted.
# @param database_type
#   Database backend: 'sqlite' (recommended upstream) or 'postgres'.
# @param database_postgres
#   Connection settings for database_type 'postgres', written under
#   `database.postgres` (host, port, name, user, pass, ...).
# @param acme_url
#   ACME directory URL used for the built-in Let's Encrypt client.
# @param acme_email
#   Email address to register with the ACME provider.
# @param tls_letsencrypt_hostname
#   Hostname to request a certificate for with the built-in Let's
#   Encrypt client. Leave unset when TLS is terminated elsewhere.
# @param tls_letsencrypt_challenge_type
#   ACME challenge type: 'HTTP-01' or 'TLS-ALPN-01'.
# @param tls_letsencrypt_listen
#   Address the HTTP-01 challenge listener binds to.
# @param tls_cert_path
#   Path of an existing TLS certificate to serve.
# @param tls_key_path
#   Path of the private key of tls_cert_path.
# @param log_level
#   Log level.
# @param log_format
#   Log format: 'text' or 'json'.
# @param policy_mode
#   Where the policy is stored: 'file' (managed by this module from
#   `policy`) or 'database' (managed with the headscale CLI).
# @param policy
#   The policy to write to the policy file, as a hash rendered as JSON
#   or a string written verbatim (HuJSON). When unset, no policy file is
#   configured and headscale allows all traffic. Changes are applied by
#   reloading the service.
# @param dns_magic_dns
#   Whether to enable MagicDNS.
# @param dns_base_domain
#   Base domain of MagicDNS hostnames. Must differ from the server_url
#   domain.
# @param dns_override_local_dns
#   Whether nodes use headscale's DNS configuration instead of their
#   local one.
# @param dns_nameservers
#   Global nameservers to push to nodes.
# @param dns_split
#   Split DNS: a hash of domains to the nameservers to use for them.
# @param dns_search_domains
#   Additional DNS search domains pushed to nodes.
# @param dns_extra_records
#   Extra DNS records, each a hash with name, type and value.
# @param unix_socket
#   Path of the unix socket the headscale CLI connects through.
# @param unix_socket_permission
#   Mode of the unix socket.
# @param logtail_enabled
#   Whether nodes send logs to Tailscale's logtail service.
# @param taildrop_enabled
#   Whether Taildrop file sharing is enabled tailnet-wide.
# @param node_auto_update_enabled
#   Whether nodes auto-update by default.
# @param override_options
#   A hash deep-merged over the configuration this module generates,
#   for any setting without a dedicated parameter, e.g. `oidc` or
#   `tuning`.
# @param service_manage
#   Whether to manage the headscale service at all.
# @param service_name
#   Name of the service to manage.
# @param service_ensure
#   Desired run state of the service.
# @param service_enable
#   Whether the service starts on boot.
class headscale (
  String[1] $version = '0.29.3',
  Enum['deb', 'binary', 'package'] $install_method = 'binary',
  Optional[Stdlib::HTTPUrl] $download_url = undef,
  Optional[Pattern[/\A[0-9a-f]{64}\z/]] $download_checksum = undef,
  Stdlib::Absolutepath $install_dir = '/opt/headscale',
  Stdlib::Absolutepath $binary_path = '/usr/local/bin/headscale',
  Boolean $manage_repo = false,
  Stdlib::HTTPUrl $repo_baseurl = 'https://download.copr.fedorainfracloud.org/results/jonathanspw/headscale/epel-$releasever-$basearch/',
  Stdlib::HTTPUrl $repo_gpgkey = 'https://download.copr.fedorainfracloud.org/results/jonathanspw/headscale/pubkey.gpg',
  String[1] $package_name = 'headscale',
  String[1] $package_ensure = 'installed',
  Boolean $manage_user = true,
  String[1] $user = 'headscale',
  String[1] $group = 'headscale',
  Stdlib::Absolutepath $config_dir = '/etc/headscale',
  Stdlib::Filemode $config_mode = '0640',
  Stdlib::Absolutepath $data_dir = '/var/lib/headscale',
  Stdlib::HTTPUrl $server_url = 'http://127.0.0.1:8080',
  String[1] $listen_addr = '127.0.0.1:8080',
  String $metrics_listen_addr = '127.0.0.1:9090',
  Array[Stdlib::IP::Address] $trusted_proxies = [],
  Stdlib::IP::Address::V4::CIDR $prefix_v4 = '100.64.0.0/10',
  Stdlib::IP::Address::V6::CIDR $prefix_v6 = 'fd7a:115c:a1e0::/48',
  Enum['sequential', 'random'] $prefix_allocation = 'sequential',
  Boolean $derp_server_enabled = false,
  Integer[1] $derp_server_region_id = 999,
  String[1] $derp_server_region_code = 'headscale',
  String[1] $derp_server_region_name = 'Headscale Embedded DERP',
  String[1] $derp_server_stun_listen_addr = '0.0.0.0:3478',
  Optional[Stdlib::IP::Address::V4::Nosubnet] $derp_server_ipv4 = undef,
  Optional[Stdlib::IP::Address::V6::Nosubnet] $derp_server_ipv6 = undef,
  Array[Stdlib::HTTPUrl] $derp_urls = ['https://controlplane.tailscale.com/derpmap/default'],
  Array[Stdlib::Absolutepath] $derp_paths = [],
  Boolean $derp_auto_update_enabled = true,
  String[1] $derp_update_frequency = '3h',
  Boolean $check_updates = true,
  Variant[Integer[0], String[1]] $node_expiry = 0,
  String[1] $ephemeral_inactivity_timeout = '30m',
  Enum['sqlite', 'postgres'] $database_type = 'sqlite',
  Optional[Hash[String[1], Data]] $database_postgres = undef,
  Stdlib::HTTPUrl $acme_url = 'https://acme-v02.api.letsencrypt.org/directory',
  Optional[String[1]] $acme_email = undef,
  Optional[Stdlib::Fqdn] $tls_letsencrypt_hostname = undef,
  Enum['HTTP-01', 'TLS-ALPN-01'] $tls_letsencrypt_challenge_type = 'HTTP-01',
  String[1] $tls_letsencrypt_listen = ':http',
  Optional[Stdlib::Absolutepath] $tls_cert_path = undef,
  Optional[Stdlib::Absolutepath] $tls_key_path = undef,
  Enum['panic', 'fatal', 'error', 'warn', 'info', 'debug', 'trace'] $log_level = 'info',
  Enum['text', 'json'] $log_format = 'text',
  Enum['file', 'database'] $policy_mode = 'file',
  Optional[Variant[Hash[String[1], Data], String[1]]] $policy = undef,
  Boolean $dns_magic_dns = true,
  Stdlib::Fqdn $dns_base_domain = 'example.com',
  Boolean $dns_override_local_dns = true,
  Array[String[1]] $dns_nameservers = ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'],
  Hash[Stdlib::Fqdn, Array[String[1]]] $dns_split = {},
  Array[Stdlib::Fqdn] $dns_search_domains = [],
  Array[Hash[String[1], String[1]]] $dns_extra_records = [],
  Stdlib::Absolutepath $unix_socket = '/var/run/headscale/headscale.sock',
  Stdlib::Filemode $unix_socket_permission = '0770',
  Boolean $logtail_enabled = false,
  Boolean $taildrop_enabled = true,
  Boolean $node_auto_update_enabled = false,
  Hash[String[1], Data] $override_options = {},
  Boolean $service_manage = true,
  String[1] $service_name = 'headscale',
  Stdlib::Ensure::Service $service_ensure = 'running',
  Boolean $service_enable = true,
) {
  contain headscale::repo
  contain headscale::install
  contain headscale::config
  contain headscale::service

  Class['headscale::repo']
  -> Class['headscale::install']
  -> Class['headscale::config']
  ~> Class['headscale::service']

  # A new package or binary version must restart the service.
  Class['headscale::install'] ~> Class['headscale::service']
}
