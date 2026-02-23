# frozen_string_literal: true

require 'yaml'

RSpec.describe Kodo::ConfigWriter, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:config_path) { File.join(tmpdir, 'config.yml') }
  let(:writer) { described_class.new(config_path) }

  describe '#update' do
    it 'writes a top-level key' do
      writer.update('search.provider', 'tavily')

      data = YAML.safe_load_file(config_path)
      expect(data.dig('search', 'provider')).to eq('tavily')
    end

    it 'creates missing parent hashes' do
      writer.update('channels.telegram.enabled', true)

      data = YAML.safe_load_file(config_path)
      expect(data.dig('channels', 'telegram', 'enabled')).to be true
    end

    it 'preserves existing keys when updating' do
      File.write(config_path, YAML.dump('llm' => { 'model' => 'gpt-4' }, 'search' => { 'provider' => nil }))

      writer.update('search.provider', 'tavily')

      data = YAML.safe_load_file(config_path)
      expect(data.dig('llm', 'model')).to eq('gpt-4')
      expect(data.dig('search', 'provider')).to eq('tavily')
    end

    it 'handles setting a value to nil' do
      File.write(config_path, YAML.dump('search' => { 'provider' => 'tavily' }))

      writer.update('search.provider', nil)

      data = YAML.safe_load_file(config_path)
      expect(data.dig('search', 'provider')).to be_nil
    end

    it 'creates the file when it does not exist' do
      expect(File.exist?(config_path)).to be false

      writer.update('autonomy.enabled', true)

      expect(File.exist?(config_path)).to be true
      data = YAML.safe_load_file(config_path)
      expect(data.dig('autonomy', 'enabled')).to be true
    end

    it 'handles an empty config file' do
      File.write(config_path, '')

      writer.update('web.browser_enabled', true)

      data = YAML.safe_load_file(config_path)
      expect(data.dig('web', 'browser_enabled')).to be true
    end
  end

  describe '#read' do
    it 'reads a nested key' do
      File.write(config_path, YAML.dump('web' => { 'browser_enabled' => true }))

      expect(writer.read('web.browser_enabled')).to be true
    end

    it 'returns nil for a missing key' do
      File.write(config_path, YAML.dump('web' => {}))

      expect(writer.read('web.browser_enabled')).to be_nil
    end

    it 'returns nil when the file does not exist' do
      expect(writer.read('web.browser_enabled')).to be_nil
    end

    it 'returns nil for a deeply missing path' do
      File.write(config_path, YAML.dump('web' => { 'browser_enabled' => true }))

      expect(writer.read('web.nonexistent.deeply.nested')).to be_nil
    end
  end
end
