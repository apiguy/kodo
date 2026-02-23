# frozen_string_literal: true

RSpec.describe Kodo::Tools::SmtpSend do
  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }
  let(:tool) { described_class.new(audit: audit) }

  before do
    allow(Kodo).to receive(:config).and_return(
      Kodo::Config.new(
        Kodo::Config::DEFAULTS.merge(
          'agent' => { 'name' => 'Kodo', 'email' => 'kodo@example.com', 'email_provider' => 'smtp' }
        )
      )
    )
  end

  describe '#execute' do
    it 'sends an email and returns confirmation' do
      smtp = instance_double(Net::SMTP)
      allow(Net::SMTP).to receive(:start).and_yield(smtp)
      allow(smtp).to receive(:send_message)

      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')

      expect(result).to include('Email sent')
      expect(result).to include('user@example.com')
    end

    it 'logs the email to audit' do
      smtp = instance_double(Net::SMTP)
      allow(Net::SMTP).to receive(:start).and_yield(smtp)
      allow(smtp).to receive(:send_message)

      tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')

      expect(audit).to have_received(:log).with(
        event: 'email_sent',
        detail: a_string_including('user@example.com')
      )
    end

    it 'returns error when agent email is not configured' do
      allow(Kodo).to receive(:config).and_return(
        Kodo::Config.new(Kodo::Config::DEFAULTS)
      )

      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')
      expect(result).to include('not configured')
    end

    it 'enforces body length limit' do
      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'x' * 5001)
      expect(result).to include('too long')
    end

    it 'enforces rate limit' do
      smtp = instance_double(Net::SMTP)
      allow(Net::SMTP).to receive(:start).and_yield(smtp)
      allow(smtp).to receive(:send_message)

      3.times { tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello') }
      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')

      expect(result).to include('Rate limit')
    end

    it 'handles SMTP errors gracefully' do
      allow(Net::SMTP).to receive(:start).and_raise(Net::SMTPFatalError, 'Connection refused')

      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')
      expect(result).to include('Failed to send email')
    end

    it 'resets rate limit on reset_turn_count!' do
      smtp = instance_double(Net::SMTP)
      allow(Net::SMTP).to receive(:start).and_yield(smtp)
      allow(smtp).to receive(:send_message)

      3.times { tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello') }
      tool.reset_turn_count!
      result = tool.execute(to: 'user@example.com', subject: 'Test', body: 'Hello')

      expect(result).to include('Email sent')
    end
  end

  describe '#name' do
    it 'returns smtp_send' do
      expect(tool.name).to eq('smtp_send')
    end
  end

  describe 'PromptContributor' do
    it 'declares Email capability' do
      expect(described_class.capability_name).to eq('Email')
      expect(described_class.capability_primary).to be true
    end
  end
end
