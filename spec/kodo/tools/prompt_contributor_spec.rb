# frozen_string_literal: true

RSpec.describe Kodo::Tools::PromptContributor do
  let(:test_class) do
    Class.new do
      extend Kodo::Tools::PromptContributor
    end
  end

  describe '.capability_name' do
    it 'defaults to nil' do
      expect(test_class.capability_name).to be_nil
    end

    it 'sets and gets the capability name' do
      test_class.capability_name 'Knowledge'
      expect(test_class.capability_name).to eq('Knowledge')
    end
  end

  describe '.capability_primary' do
    it 'defaults to false' do
      expect(test_class.capability_primary).to be false
    end

    it 'sets and gets the primary flag' do
      test_class.capability_primary true
      expect(test_class.capability_primary).to be true
    end
  end

  describe '.enabled_guidance' do
    it 'defaults to nil' do
      expect(test_class.enabled_guidance).to be_nil
    end

    it 'sets and gets the enabled guidance text' do
      test_class.enabled_guidance 'Search the web.'
      expect(test_class.enabled_guidance).to eq('Search the web.')
    end
  end

  describe '.disabled_guidance' do
    it 'defaults to nil' do
      expect(test_class.disabled_guidance).to be_nil
    end

    it 'sets and gets the disabled guidance text' do
      test_class.disabled_guidance 'Set TAVILY_API_KEY to enable.'
      expect(test_class.disabled_guidance).to eq('Set TAVILY_API_KEY to enable.')
    end
  end

  describe 'real tool declarations' do
    it 'RememberFact is primary for Knowledge' do
      expect(Kodo::Tools::RememberFact.capability_name).to eq('Knowledge')
      expect(Kodo::Tools::RememberFact.capability_primary).to be true
      expect(Kodo::Tools::RememberFact.enabled_guidance).to be_a(String)
    end

    it 'ForgetFact shares Knowledge capability but is not primary' do
      expect(Kodo::Tools::ForgetFact.capability_name).to eq('Knowledge')
      expect(Kodo::Tools::ForgetFact.capability_primary).to be false
    end

    it 'WebSearch is primary for Web Search with both guidance texts' do
      expect(Kodo::Tools::WebSearch.capability_name).to eq('Web Search')
      expect(Kodo::Tools::WebSearch.capability_primary).to be true
      expect(Kodo::Tools::WebSearch.enabled_guidance).to be_a(String)
      expect(Kodo::Tools::WebSearch.disabled_guidance).to be_a(String)
    end

    it 'StoreSecret is primary for Secret Storage' do
      expect(Kodo::Tools::StoreSecret.capability_name).to eq('Secret Storage')
      expect(Kodo::Tools::StoreSecret.capability_primary).to be true
    end
  end
end
