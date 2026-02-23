# frozen_string_literal: true

RSpec.describe Kodo::FeatureToggle, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:config_path) { File.join(tmpdir, 'config.yml') }
  let(:writer) { Kodo::ConfigWriter.new(config_path) }
  let(:toggle) { described_class.new(writer: writer) }

  describe '#list' do
    it 'lists all features with disabled status by default' do
      expect { toggle.list }.to output(/disabled.*browser/).to_stdout
    end

    it 'shows enabled status for enabled features' do
      writer.update('autonomy.enabled', true)

      expect { toggle.list }.to output(/enabled.*autonomy/).to_stdout
    end

    it 'shows usage hint' do
      expect { toggle.list }.to output(/kodo enable <feature>/).to_stdout
    end
  end

  describe '#enable' do
    it 'enables a feature with no dependencies' do
      expect { toggle.enable('autonomy') }.to output(/autonomy enabled/).to_stdout

      expect(writer.read('autonomy.enabled')).to be true
    end

    it 'reports when feature is already enabled' do
      writer.update('autonomy.enabled', true)

      expect { toggle.enable('autonomy') }.to output(/already enabled/).to_stdout
    end

    it 'writes the correct enable value for search' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TAVILY_API_KEY').and_return('tvly-test-123')

      expect { toggle.enable('search') }.to output(/search enabled/).to_stdout

      expect(writer.read('search.provider')).to eq('tavily')
    end

    it 'rejects unknown feature name' do
      expect { toggle.enable('bogus') }.to output(/Unknown feature: bogus/).to_stdout
    end

    it 'shows available features for unknown feature' do
      expect { toggle.enable('bogus') }.to output(/Available features:.*browser/).to_stdout
    end

    it 'blocks enable when env dependency is missing' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TAVILY_API_KEY').and_return(nil)

      expect { toggle.enable('search') }.to output(/Cannot enable search/).to_stdout
      expect(writer.read('search.provider')).to be_nil
    end

    it 'blocks enable when env dependency is empty' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TAVILY_API_KEY').and_return('')

      expect { toggle.enable('search') }.to output(/Cannot enable search/).to_stdout
    end

    it 'blocks enable when command dependency is missing' do
      allow(toggle).to receive(:system).and_return(false)

      expect { toggle.enable('browser') }.to output(/Cannot enable browser/).to_stdout
      expect(writer.read('web.browser_enabled')).to be_nil
    end

    it 'shows dependency hints when blocked' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TELEGRAM_BOT_TOKEN').and_return(nil)

      expect { toggle.enable('telegram') }.to output(/TELEGRAM_BOT_TOKEN not set/).to_stdout
    end

    it 'enables feature with description' do
      expect { toggle.enable('autonomy') }.to output(/Risk-classified action gating/).to_stdout
    end
  end

  describe '#disable' do
    it 'disables an enabled feature' do
      writer.update('autonomy.enabled', true)

      expect { toggle.disable('autonomy') }.to output(/autonomy disabled/).to_stdout
      expect(writer.read('autonomy.enabled')).to be false
    end

    it 'sets search provider to nil when disabled' do
      writer.update('search.provider', 'tavily')

      expect { toggle.disable('search') }.to output(/search disabled/).to_stdout
      expect(writer.read('search.provider')).to be_nil
    end

    it 'rejects unknown feature name' do
      expect { toggle.disable('bogus') }.to output(/Unknown feature: bogus/).to_stdout
    end

    it 'disables without checking dependencies' do
      expect { toggle.disable('browser') }.to output(/browser disabled/).to_stdout
      expect(writer.read('web.browser_enabled')).to be false
    end
  end
end
