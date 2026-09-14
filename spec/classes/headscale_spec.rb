# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

describe 'headscale' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      let(:headscale_config) do
        content = catalogue.resource('file', '/etc/headscale/config.yaml')[:content]
        YAML.safe_load(content)
      end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_class('headscale::repo') }
      it { is_expected.to contain_class('headscale::install') }
      it { is_expected.to contain_class('headscale::config') }
      it { is_expected.to contain_class('headscale::service') }

      it 'orders install, config and service' do
        expect(subject).to contain_class('headscale::install').that_comes_before('Class[headscale::config]')
        expect(subject).to contain_class('headscale::config').that_notifies('Class[headscale::service]')
        expect(subject).to contain_class('headscale::install').that_notifies('Class[headscale::service]')
      end

      it { is_expected.not_to contain_yumrepo('headscale') }

      it do
        expect(subject).to contain_file('/etc/headscale')
          .with(ensure: 'directory', owner: 'root', group: 'headscale', mode: '0750')
      end

      it do
        expect(subject).to contain_file('/var/lib/headscale')
          .with(ensure: 'directory', owner: 'headscale', group: 'headscale', mode: '0750')
      end

      it do
        expect(subject).to contain_file('/etc/headscale/config.yaml')
          .with(ensure: 'file', owner: 'root', group: 'headscale', mode: '0640', show_diff: false)
      end

      it 'renders the upstream defaults' do
        expect(headscale_config).to include(
          'server_url' => 'http://127.0.0.1:8080',
          'listen_addr' => '127.0.0.1:8080',
          'metrics_listen_addr' => '127.0.0.1:9090',
          'trusted_proxies' => [],
          'disable_check_updates' => false,
          'unix_socket' => '/var/run/headscale/headscale.sock',
          'unix_socket_permission' => '0770',
        )
        expect(headscale_config['noise']).to eq('private_key_path' => '/var/lib/headscale/noise_private.key')
        expect(headscale_config['prefixes']).to eq('v4' => '100.64.0.0/10', 'v6' => 'fd7a:115c:a1e0::/48', 'allocation' => 'sequential')
        expect(headscale_config['derp']['server']).to include('enabled' => false, 'stun_listen_addr' => '0.0.0.0:3478')
        expect(headscale_config['derp']['server']).not_to include('ipv4', 'ipv6')
        expect(headscale_config['derp']['urls']).to eq(['https://controlplane.tailscale.com/derpmap/default'])
        expect(headscale_config['node']).to eq('expiry' => 0, 'ephemeral' => { 'inactivity_timeout' => '30m' })
        expect(headscale_config['database']).to eq('type' => 'sqlite',
                                                   'sqlite' => { 'path' => '/var/lib/headscale/db.sqlite', 'write_ahead_log' => true })
        expect(headscale_config['log']).to eq('level' => 'info', 'format' => 'text')
        expect(headscale_config['dns']).to include('magic_dns' => true, 'base_domain' => 'example.com', 'override_local_dns' => true)
        expect(headscale_config['dns']['nameservers']).to eq('global' => ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'],
                                                             'split' => {})
        expect(headscale_config['logtail']).to eq('enabled' => false)
        expect(headscale_config['taildrop']).to eq('enabled' => true)
        expect(headscale_config['auto_update']).to eq('enabled' => false)
      end

      it 'renders unset optional strings as empty strings' do
        expect(headscale_config).to include('acme_email' => '', 'tls_letsencrypt_hostname' => '', 'tls_cert_path' => '', 'tls_key_path' => '')
        expect(headscale_config['tls_letsencrypt_cache_dir']).to eq('/var/lib/headscale/cache')
      end

      it 'configures no policy file by default' do
        expect(headscale_config['policy']).to eq('mode' => 'file', 'path' => '')
        expect(subject).not_to contain_file('/etc/headscale/policy.hujson')
        expect(subject).not_to contain_exec('headscale-reload-policy')
      end

      it { is_expected.not_to contain_key('oidc') }

      it { is_expected.to contain_service('headscale').with_ensure('running').with_enable(true) }

      context 'with a policy hash' do
        let(:params) do
          { policy: { 'grants' => [{ 'src' => ['*'], 'dst' => ['*'], 'ip' => ['*'] }] } }
        end

        it { expect(headscale_config['policy']).to eq('mode' => 'file', 'path' => '/etc/headscale/policy.hujson') }

        it 'renders the policy as JSON and reloads the service on change' do
          expect(subject).to contain_file('/etc/headscale/policy.hujson')
            .with(ensure: 'file', owner: 'root', group: 'headscale', mode: '0640')
            .that_notifies('Exec[headscale-reload-policy]')
          content = catalogue.resource('file', '/etc/headscale/policy.hujson')[:content]
          expect(JSON.parse(content)).to eq('grants' => [{ 'src' => ['*'], 'dst' => ['*'], 'ip' => ['*'] }])
        end

        it do
          expect(subject).to contain_exec('headscale-reload-policy')
            .with(command: 'systemctl reload headscale', refreshonly: true, onlyif: 'systemctl is-active --quiet headscale')
        end
      end

      context 'with a policy string' do
        let(:params) { { policy: "// allow all\n{}\n" } }

        it { is_expected.to contain_file('/etc/headscale/policy.hujson').with_content("// allow all\n{}\n") }
      end

      context 'with policy_mode => database' do
        let(:params) { { policy_mode: 'database' } }

        it { expect(headscale_config['policy']).to eq('mode' => 'database', 'path' => '') }
      end

      context 'with override_options' do
        let(:params) do
          {
            override_options: {
              'dns' => { 'magic_dns' => false },
              'oidc' => { 'issuer' => 'https://sso.example.com', 'client_id' => 'headscale' },
            },
          }
        end

        it 'deep-merges over the generated configuration' do
          expect(headscale_config['dns']).to include('magic_dns' => false, 'base_domain' => 'example.com')
          expect(headscale_config['oidc']).to eq('issuer' => 'https://sso.example.com', 'client_id' => 'headscale')
        end
      end

      context 'with the embedded DERP server' do
        let(:params) do
          { derp_server_enabled: true, derp_server_ipv4: '198.51.100.1', derp_server_ipv6: '2001:db8::1' }
        end

        it do
          expect(headscale_config['derp']['server']).to include('enabled' => true, 'ipv4' => '198.51.100.1', 'ipv6' => '2001:db8::1',
                                                                'private_key_path' => '/var/lib/headscale/derp_server_private.key')
        end
      end

      context 'with PostgreSQL' do
        let(:params) do
          { database_type: 'postgres', database_postgres: { 'host' => 'db.example.com', 'port' => 5432, 'name' => 'headscale' } }
        end

        it do
          expect(headscale_config['database']).to include('type' => 'postgres',
                                                          'postgres' => { 'host' => 'db.example.com', 'port' => 5432, 'name' => 'headscale' })
        end
      end

      context 'with the built-in Let\'s Encrypt client' do
        let(:params) do
          { server_url: 'https://headscale.example.com', listen_addr: '0.0.0.0:443',
            tls_letsencrypt_hostname: 'headscale.example.com', acme_email: 'admin@example.com', }
        end

        it do
          expect(headscale_config).to include('server_url' => 'https://headscale.example.com', 'listen_addr' => '0.0.0.0:443',
                                              'tls_letsencrypt_hostname' => 'headscale.example.com', 'acme_email' => 'admin@example.com')
        end
      end

      context 'with a moved data_dir' do
        let(:params) { { data_dir: '/srv/headscale' } }

        it { is_expected.to contain_file('/srv/headscale').with_ensure('directory') }
        it { is_expected.not_to contain_file('/var/lib/headscale') }

        it 'points the state paths at it' do
          expect(headscale_config['noise']['private_key_path']).to eq('/srv/headscale/noise_private.key')
          expect(headscale_config['database']['sqlite']['path']).to eq('/srv/headscale/db.sqlite')
          expect(headscale_config['tls_letsencrypt_cache_dir']).to eq('/srv/headscale/cache')
        end
      end

      context 'with service_manage => false' do
        let(:params) { { service_manage: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('headscale') }
        it { is_expected.not_to contain_file('/etc/systemd/system/headscale.service') }
        it { is_expected.not_to contain_file('/etc/systemd/system/headscale.service.d/puppet.conf') }
      end

      context 'with install_method => binary' do
        let(:params) { { install_method: 'binary', manage_user: true, binary_path: '/usr/local/bin/headscale' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('headscale') }
        it { is_expected.to contain_group('headscale').with_system(true) }

        it do
          expect(subject).to contain_user('headscale')
            .with(system: true, gid: 'headscale', home: '/var/lib/headscale', shell: '/usr/sbin/nologin')
        end

        it { is_expected.to contain_file('/opt/headscale').with_ensure('directory') }

        it 'downloads the versioned binary without a checksum by default' do
          expect(subject).to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64')
            .with(source: 'https://github.com/juanfont/headscale/releases/download/v0.29.3/headscale_0.29.3_linux_amd64',
                  checksum_type: 'none', extract: false)
            .that_requires('File[/opt/headscale]')
        end

        it do
          expect(subject).to contain_file('/opt/headscale/headscale_0.29.3_linux_amd64')
            .with(ensure: 'file', owner: 'root', group: 'root', mode: '0755')
            .that_requires('Archive[/opt/headscale/headscale_0.29.3_linux_amd64]')
        end

        it do
          expect(subject).to contain_file('/usr/local/bin/headscale')
            .with(ensure: 'link', target: '/opt/headscale/headscale_0.29.3_linux_amd64')
        end

        it { is_expected.to contain_file('/var/lib/headscale').that_requires('User[headscale]') }
        it { is_expected.to contain_file('/etc/headscale').that_requires('User[headscale]') }

        it 'manages the systemd unit' do
          expect(subject).to contain_file('/etc/systemd/system/headscale.service')
            .with(ensure: 'file', owner: 'root', group: 'root', mode: '0644')
            .that_notifies('Service[headscale]')
          content = catalogue.resource('file', '/etc/systemd/system/headscale.service')[:content]
          expect(content).to match(%r{^ExecStart=/usr/local/bin/headscale serve$})
          expect(content).to match(%r{^User=headscale$})
          expect(content).to match(%r{^Group=headscale$})
          expect(content).to match(%r{^WorkingDirectory=/var/lib/headscale$})
          expect(content).to match(%r{^ReadWritePaths=/var/lib/headscale$})
          expect(content).to match(%r{^ProtectSystem=strict$})
        end

        it { is_expected.not_to contain_file('/etc/systemd/system/headscale.service.d/puppet.conf') }

        context 'with a different version' do
          let(:params) { super().merge(version: '0.30.0') }

          it { is_expected.to contain_archive('/opt/headscale/headscale_0.30.0_linux_amd64') }
          it { is_expected.not_to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64') }
          it { is_expected.to contain_file('/usr/local/bin/headscale').with_target('/opt/headscale/headscale_0.30.0_linux_amd64') }
        end

        context 'with download_checksum' do
          let(:params) { super().merge(download_checksum: 'a' * 64) }

          it do
            expect(subject).to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64')
              .with(checksum: 'a' * 64, checksum_type: 'sha256')
          end
        end

        context 'with download_url' do
          let(:params) { super().merge(download_url: 'https://mirror.example.com/headscale') }

          it { is_expected.to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64').with_source('https://mirror.example.com/headscale') }
        end

        context 'with manage_user => false' do
          let(:params) { super().merge(manage_user: false) }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.not_to contain_user('headscale') }
          it { is_expected.not_to contain_group('headscale') }
          it { is_expected.to contain_file('/var/lib/headscale').with_owner('headscale') }
        end

        context 'when on aarch64' do
          let(:facts) { os_facts.merge(os: os_facts[:os].merge('architecture' => 'aarch64')) }

          it do
            expect(subject).to contain_archive('/opt/headscale/headscale_0.29.3_linux_arm64')
              .with_source('https://github.com/juanfont/headscale/releases/download/v0.29.3/headscale_0.29.3_linux_arm64')
          end
        end

        context 'when on an unsupported architecture' do
          let(:facts) { os_facts.merge(os: os_facts[:os].merge('architecture' => 'ppc64le')) }

          it { is_expected.to compile.and_raise_error(%r{no headscale release exists for architecture 'ppc64le'}) }
        end
      end

      context 'with install_method => package' do
        let(:params) { { install_method: 'package', manage_user: false, binary_path: '/usr/bin/headscale' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('headscale').with_ensure('installed') }
        it { is_expected.not_to contain_archive('/var/tmp/headscale_0.29.3_linux_amd64.deb') }
        it { is_expected.not_to contain_user('headscale') }
        it { is_expected.to contain_file('/var/lib/headscale').that_requires('Package[headscale]') }
        it { is_expected.not_to contain_file('/etc/systemd/system/headscale.service') }

        it 'opens data_dir in the packaged unit via a drop-in' do
          expect(subject).to contain_file('/etc/systemd/system/headscale.service.d/puppet.conf')
            .with_content(%r{^ReadWritePaths=/var/lib/headscale$})
            .that_notifies('Service[headscale]')
        end

        context 'with package_ensure' do
          let(:params) { super().merge(package_ensure: '0.28.0') }

          it { is_expected.to contain_package('headscale').with_ensure('0.28.0') }
        end

        context 'with manage_repo => true' do
          let(:params) { super().merge(manage_repo: true) }

          if os_facts[:os]['family'] == 'RedHat'
            it { is_expected.to compile.with_all_deps }

            it do
              expect(subject).to contain_yumrepo('headscale')
                .with(baseurl: 'https://download.copr.fedorainfracloud.org/results/jonathanspw/headscale/epel-$releasever-$basearch/',
                      gpgcheck: '1',
                      gpgkey: 'https://download.copr.fedorainfracloud.org/results/jonathanspw/headscale/pubkey.gpg')
                .that_comes_before('Package[headscale]')
            end
          else
            it { is_expected.to compile.and_raise_error(%r{no yum repository is available for the #{os_facts[:os]['family']} family}) }
          end
        end
      end

      case os_facts[:os]['family']
      when 'Debian'
        it 'installs the official .deb by default' do
          expect(subject).to contain_archive('/var/tmp/headscale_0.29.3_linux_amd64.deb')
            .with(source: 'https://github.com/juanfont/headscale/releases/download/v0.29.3/headscale_0.29.3_linux_amd64.deb',
                  checksum_type: 'none', extract: false)
          expect(subject).to contain_package('headscale')
            .with(ensure: 'latest', provider: 'dpkg', source: '/var/tmp/headscale_0.29.3_linux_amd64.deb')
            .that_requires('Archive[/var/tmp/headscale_0.29.3_linux_amd64.deb]')
        end

        it { is_expected.not_to contain_user('headscale') }
        it { is_expected.not_to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64') }
        it { is_expected.not_to contain_file('/etc/systemd/system/headscale.service') }
        it { is_expected.to contain_file('/etc/systemd/system/headscale.service.d/puppet.conf') }
        it { is_expected.to contain_file('/var/lib/headscale').that_requires('Package[headscale]') }

        context 'with a different version' do
          let(:params) { { version: '0.30.0' } }

          it { is_expected.to contain_archive('/var/tmp/headscale_0.30.0_linux_amd64.deb') }
          it { is_expected.to contain_package('headscale').with_source('/var/tmp/headscale_0.30.0_linux_amd64.deb') }
        end

        context 'with download_checksum' do
          let(:params) { { download_checksum: 'b' * 64 } }

          it { is_expected.to contain_archive('/var/tmp/headscale_0.29.3_linux_amd64.deb').with(checksum: 'b' * 64, checksum_type: 'sha256') }
        end

        context 'when on aarch64' do
          let(:facts) { os_facts.merge(os: os_facts[:os].merge('architecture' => 'aarch64')) }

          it do
            expect(subject).to contain_archive('/var/tmp/headscale_0.29.3_linux_arm64.deb')
              .with_source('https://github.com/juanfont/headscale/releases/download/v0.29.3/headscale_0.29.3_linux_arm64.deb')
          end
        end
      when 'RedHat'
        it 'installs the release binary by default' do
          expect(subject).to contain_archive('/opt/headscale/headscale_0.29.3_linux_amd64')
          expect(subject).to contain_file('/usr/local/bin/headscale').with_ensure('link')
          expect(subject).to contain_user('headscale')
          expect(subject).to contain_file('/etc/systemd/system/headscale.service')
        end

        it { is_expected.not_to contain_package('headscale') }

        context 'with install_method => deb' do
          let(:params) { { install_method: 'deb' } }

          it { is_expected.to compile.and_raise_error(%r{install_method 'deb' is only available on the Debian family}) }
        end
      when 'Archlinux'
        it 'installs the distribution package by default' do
          expect(subject).to contain_package('headscale').with_ensure('installed')
          expect(subject).not_to contain_user('headscale')
          expect(subject).not_to contain_file('/etc/systemd/system/headscale.service')
        end
      end
    end
  end
end
