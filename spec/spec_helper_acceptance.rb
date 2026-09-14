# frozen_string_literal: true

require 'voxpupuli/acceptance/spec_helper_acceptance'

configure_beaker do |host|
  # The acceptance specs probe the headscale endpoints with curl. EL
  # images ship curl-minimal, which conflicts with the full curl package.
  host.install_package('curl') if fact_on(host, 'os.family') == 'Debian'
end
