# frozen_string_literal: true

require 'spec_helper_acceptance'

def headscale_manifest(policy)
  <<~PUPPET
    class { 'headscale':
      server_url      => 'http://127.0.0.1:8080',
      dns_base_domain => 'tailnet.example.com',
      policy          => #{policy},
    }
  PUPPET
end

ALLOW_ALL = "{ 'grants' => [{ 'src' => ['*'], 'dst' => ['*'], 'ip' => ['*'] }] }"
DENY_ALL = "{ 'grants' => [] }"

describe 'headscale' do
  let(:manifest) { headscale_manifest(ALLOW_ALL) }

  it_behaves_like 'an idempotent resource'

  describe file('/etc/headscale/config.yaml') do
    it { is_expected.to be_file }
    it { is_expected.to be_owned_by 'root' }
    it { is_expected.to be_grouped_into 'headscale' }
    it { is_expected.to be_mode 640 }

    its(:content) { is_expected.to include('server_url: http://127.0.0.1:8080', 'base_domain: tailnet.example.com') }
  end

  describe file('/etc/headscale/policy.hujson') do
    it { is_expected.to be_file }

    its(:content) { is_expected.to include('"grants"') }
  end

  describe file('/var/lib/headscale') do
    it { is_expected.to be_directory }
    it { is_expected.to be_owned_by 'headscale' }
  end

  describe user('headscale') do
    it { is_expected.to exist }
  end

  describe service('headscale') do
    it { is_expected.to be_running }
    it { is_expected.to be_enabled }
  end

  [8080, 9090].each do |listen_port|
    describe port(listen_port) do
      it { is_expected.to be_listening }
    end
  end

  describe 'the headscale server' do
    it 'reports healthy' do
      health = 'curl --silent --fail http://127.0.0.1:8080/health'
      result = shell("for i in $(seq 1 30); do #{health} && exit 0; sleep 2; done; exit 1")
      expect(result.stdout).to include('"pass"')
    end

    it 'runs the requested version' do
      expect(shell('headscale version').stdout).to include('0.29.3')
    end

    it 'answers the CLI over the unix socket' do
      shell('headscale users create acceptance')
      expect(shell('headscale users list').stdout).to include('acceptance')
    end
  end

  describe 'changing the policy' do
    it 'reloads the service without restarting it' do
      pid_before = shell('systemctl show --property MainPID --value headscale').stdout.strip
      apply_manifest(headscale_manifest(DENY_ALL), catch_failures: true)
      expect(apply_manifest(headscale_manifest(DENY_ALL), catch_changes: true).exit_code).to eq(0)
      expect(file('/etc/headscale/policy.hujson').content).to include('"grants": []')
      expect(shell('systemctl show --property MainPID --value headscale').stdout.strip).to eq(pid_before)
    end
  end
end
