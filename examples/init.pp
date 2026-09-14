# Installs headscale with the OS default install method and configures it
# for use behind a TLS-terminating reverse proxy on the same host.
class { 'headscale':
  server_url      => 'https://headscale.example.com',
  listen_addr     => '127.0.0.1:8080',
  trusted_proxies => ['127.0.0.1/32'],
  dns_base_domain => 'tailnet.example.com',
  policy          => {
    'grants' => [
      { 'src' => ['autogroup:member'], 'dst' => ['autogroup:member'], 'ip' => ['*'] },
    ],
  },
}
