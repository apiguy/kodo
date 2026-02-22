# frozen_string_literal: true

RSpec.describe Kodo::Web::UrlValidator do
  let(:test_class) do
    Class.new do
      include Kodo::Web::UrlValidator
    end
  end

  subject(:validator) { test_class.new }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
    allow(Kodo).to receive(:config).and_return(Kodo::Config.new(Kodo::Config::DEFAULTS))
  end

  describe '#validate_url!' do
    it 'returns a URI for a valid https URL' do
      uri = validator.validate_url!('https://example.com/path')
      expect(uri).to be_a(URI::HTTPS)
      expect(uri.host).to eq('example.com')
    end

    it 'returns a URI for a valid http URL' do
      uri = validator.validate_url!('http://example.com/')
      expect(uri).to be_a(URI::HTTP)
    end

    it 'raises for non-http schemes' do
      expect { validator.validate_url!('ftp://example.com/file') }
        .to raise_error(Kodo::Error, /Only http and https/)
    end

    it 'raises for invalid URL format' do
      expect { validator.validate_url!('not a url at all ://') }
        .to raise_error(Kodo::Error, /Invalid URL format/)
    end
  end

  describe 'SSRF protection' do
    it 'blocks localhost (127.0.0.1)' do
      allow(Resolv).to receive(:getaddresses).and_return(['127.0.0.1'])
      expect { validator.validate_url!('https://localhost/admin') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'blocks 10.x.x.x range' do
      allow(Resolv).to receive(:getaddresses).and_return(['10.0.0.1'])
      expect { validator.validate_url!('https://internal.corp/secret') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'blocks 172.16.x.x range' do
      allow(Resolv).to receive(:getaddresses).and_return(['172.16.0.1'])
      expect { validator.validate_url!('https://internal.corp/secret') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'blocks 192.168.x.x range' do
      allow(Resolv).to receive(:getaddresses).and_return(['192.168.1.1'])
      expect { validator.validate_url!('https://router.local/config') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'blocks link-local addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['169.254.1.1'])
      expect { validator.validate_url!('https://metadata.internal/latest') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'blocks IPv6 loopback' do
      allow(Resolv).to receive(:getaddresses).and_return(['::1'])
      expect { validator.validate_url!('https://localhost/admin') }
        .to raise_error(Kodo::Error, %r{private/internal network})
    end

    it 'allows public IP addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
      expect { validator.validate_url!('https://example.com') }.not_to raise_error
    end

    it 'raises for unresolvable hostnames' do
      allow(Resolv).to receive(:getaddresses).and_return([])
      expect { validator.validate_url!('https://nonexistent.invalid/page') }
        .to raise_error(Kodo::Error, /Could not resolve/)
    end
  end

  describe 'domain policy' do
    it 'blocks domains in fetch_blocklist' do
      config = Kodo::Config.new(Kodo::Config::DEFAULTS.merge('web' => {
                                                               'fetch_url_enabled' => true, 'web_search_enabled' => true,
                                                               'injection_scan' => true, 'audit_urls' => true,
                                                               'fetch_blocklist' => ['pastebin.com'], 'fetch_allowlist' => [],
                                                               'ssrf_bypass_hosts' => []
                                                             }))
      allow(Kodo).to receive(:config).and_return(config)

      expect { validator.validate_url!('https://pastebin.com/abc') }
        .to raise_error(Kodo::Error, /blocked/)
    end

    it 'blocks subdomains with wildcard blocklist entry' do
      config = Kodo::Config.new(Kodo::Config::DEFAULTS.merge('web' => {
                                                               'fetch_url_enabled' => true, 'web_search_enabled' => true,
                                                               'injection_scan' => true, 'audit_urls' => true,
                                                               'fetch_blocklist' => ['*.example.com'], 'fetch_allowlist' => [],
                                                               'ssrf_bypass_hosts' => []
                                                             }))
      allow(Kodo).to receive(:config).and_return(config)

      expect { validator.validate_url!('https://evil.example.com/page') }
        .to raise_error(Kodo::Error, /blocked/)
    end

    it 'blocks domains not in allowlist when allowlist is set' do
      config = Kodo::Config.new(Kodo::Config::DEFAULTS.merge('web' => {
                                                               'fetch_url_enabled' => true, 'web_search_enabled' => true,
                                                               'injection_scan' => true, 'audit_urls' => true,
                                                               'fetch_blocklist' => [], 'fetch_allowlist' => ['allowed.com'],
                                                               'ssrf_bypass_hosts' => []
                                                             }))
      allow(Kodo).to receive(:config).and_return(config)

      expect { validator.validate_url!('https://notallowed.com/page') }
        .to raise_error(Kodo::Error, /not in the fetch_allowlist/)
    end

    it 'allows domains in allowlist' do
      config = Kodo::Config.new(Kodo::Config::DEFAULTS.merge('web' => {
                                                               'fetch_url_enabled' => true, 'web_search_enabled' => true,
                                                               'injection_scan' => true, 'audit_urls' => true,
                                                               'fetch_blocklist' => [], 'fetch_allowlist' => ['allowed.com'],
                                                               'ssrf_bypass_hosts' => []
                                                             }))
      allow(Kodo).to receive(:config).and_return(config)

      expect { validator.validate_url!('https://allowed.com/page') }.not_to raise_error
    end
  end

  describe 'secret exfiltration protection' do
    let(:secret_value) { 'tvly-supersecretkey123' }
    let(:sensitive_values_fn) { -> { [secret_value] } }

    it 'raises when URL contains a stored secret' do
      expect { validator.validate_url!("https://attacker.com/?key=#{secret_value}", sensitive_values_fn: sensitive_values_fn) }
        .to raise_error(Kodo::Error, /stored secret/)
    end

    it 'allows URLs that do not contain any stored secret' do
      expect { validator.validate_url!('https://example.com/page', sensitive_values_fn: sensitive_values_fn) }
        .not_to raise_error
    end

    it 'skips secrets shorter than 8 characters to avoid false positives' do
      short_fn = -> { ['abc'] }
      expect { validator.validate_url!('https://example.com/?q=abc', sensitive_values_fn: short_fn) }
        .not_to raise_error
    end

    it 'works without a sensitive_values_fn' do
      expect { validator.validate_url!('https://example.com/') }.not_to raise_error
    end
  end
end
