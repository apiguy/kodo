# frozen_string_literal: true

RSpec.describe Kodo::Tools::UpdatePulse, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }
  let(:tool) { described_class.new(audit: audit) }

  before do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
  end

  describe '#execute' do
    it 'writes content to pulse.md' do
      tool.execute(content: '# Daily Report')

      pulse_path = File.join(tmpdir, 'pulse.md')
      expect(File.exist?(pulse_path)).to be true
      expect(File.read(pulse_path)).to eq('# Daily Report')
    end

    it 'backs up existing pulse.md' do
      pulse_path = File.join(tmpdir, 'pulse.md')
      File.write(pulse_path, '# Old Pulse')

      tool.execute(content: '# New Pulse')

      backup_path = File.join(tmpdir, 'pulse.md.bak')
      expect(File.exist?(backup_path)).to be true
      expect(File.read(backup_path)).to eq('# Old Pulse')
    end

    it 'returns confirmation with char count' do
      result = tool.execute(content: '# Test')

      expect(result).to include('Pulse updated')
      expect(result).to include('6 chars')
    end

    it 'logs the update to audit' do
      tool.execute(content: '# Test')

      expect(audit).to have_received(:log).with(
        event: 'pulse_updated',
        detail: 'len:6'
      )
    end

    it 'rejects content exceeding max length' do
      result = tool.execute(content: 'x' * 10_001)
      expect(result).to include('too long')
    end

    it 'enforces rate limit of 1 per turn' do
      tool.execute(content: '# First')
      result = tool.execute(content: '# Second')

      expect(result).to include('Rate limit')
    end

    it 'resets rate limit on reset_turn_count!' do
      tool.execute(content: '# First')
      tool.reset_turn_count!
      result = tool.execute(content: '# Second')

      expect(result).to include('Pulse updated')
    end

    it 'skips backup when pulse.md does not exist' do
      tool.execute(content: '# New')

      backup_path = File.join(tmpdir, 'pulse.md.bak')
      expect(File.exist?(backup_path)).to be false
    end
  end

  describe '#name' do
    it 'returns update_pulse' do
      expect(tool.name).to eq('update_pulse')
    end
  end

  describe 'PromptContributor' do
    it 'declares Pulse Configuration capability' do
      expect(described_class.capability_name).to eq('Pulse Configuration')
      expect(described_class.capability_primary).to be true
    end
  end
end
