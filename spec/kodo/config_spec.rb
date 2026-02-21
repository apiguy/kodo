# frozen_string_literal: true

RSpec.describe Kodo::Config, :tmpdir do
  let(:tmpdir) { @tmpdir }

  let(:default_config) { described_class.new(described_class::DEFAULTS) }

  describe ".load" do
    it "returns defaults when no config file exists" do
      config = described_class.load(File.join(tmpdir, "nonexistent.yml"))
      expect(config.port).to eq(7377)
      expect(config.heartbeat_interval).to eq(60)
      expect(config.llm_model).to eq("claude-sonnet-4-6")
    end

    it "deep merges user config with defaults" do
      user_config = { "daemon" => { "port" => 9999 } }
      path = File.join(tmpdir, "config.yml")
      File.write(path, YAML.dump(user_config))

      config = described_class.load(path)
      expect(config.port).to eq(9999)
      expect(config.heartbeat_interval).to eq(60) # preserved from defaults
    end

    it "handles empty config file" do
      path = File.join(tmpdir, "config.yml")
      File.write(path, "")

      config = described_class.load(path)
      expect(config.port).to eq(7377)
    end
  end

  describe "accessor methods" do
    it "#port returns daemon port" do
      expect(default_config.port).to eq(7377)
    end

    it "#heartbeat_interval returns interval" do
      expect(default_config.heartbeat_interval).to eq(60)
    end

    it "#llm_model returns model name" do
      expect(default_config.llm_model).to eq("claude-sonnet-4-6")
    end

    it "#utility_model returns haiku by default" do
      expect(default_config.utility_model).to eq("claude-haiku-4-5-20251001")
    end

    it "#utility_model returns configured utility model" do
      config = described_class.new(
        described_class::DEFAULTS.merge(
          "llm" => described_class::DEFAULTS["llm"].merge("utility_model" => "claude-haiku-4-5-20251001")
        )
      )
      expect(config.utility_model).to eq("claude-haiku-4-5-20251001")
    end

    it "#log_level returns symbol" do
      expect(default_config.log_level).to eq(:info)
    end

    it "#audit_enabled? returns true by default" do
      expect(default_config.audit_enabled?).to be true
    end

    it "#telegram_enabled? returns false by default" do
      expect(default_config.telegram_enabled?).to be false
    end
  end

  describe "memory/encryption accessors" do
    it "#memory_encryption? returns false by default" do
      expect(default_config.memory_encryption?).to be false
    end

    it "#memory_passphrase_env returns KODO_PASSPHRASE by default" do
      expect(default_config.memory_passphrase_env).to eq("KODO_PASSPHRASE")
    end

    it "#memory_passphrase reads from the configured env var" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KODO_PASSPHRASE").and_return("my-secret")

      expect(default_config.memory_passphrase).to eq("my-secret")
    end

    it "#memory_passphrase raises when encryption is enabled but passphrase is missing" do
      config = described_class.new(
        described_class::DEFAULTS.merge("memory" => { "encryption" => true, "passphrase_env" => "KODO_PASSPHRASE" })
      )
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KODO_PASSPHRASE").and_return(nil)

      expect { config.memory_passphrase }.to raise_error(Kodo::Error, /not set/)
    end

    it "#memory_passphrase returns nil when encryption is disabled and no passphrase" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KODO_PASSPHRASE").and_return(nil)

      expect(default_config.memory_passphrase).to be_nil
    end
  end

  describe "#llm_api_keys" do
    it "reads API keys from environment variables" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-test-123")

      keys = default_config.llm_api_keys
      expect(keys).to eq({ "anthropic" => "sk-test-123" })
    end

    it "raises when no API keys are configured" do
      allow(ENV).to receive(:[]).and_return(nil)

      expect { default_config.llm_api_keys }.to raise_error(Kodo::Error, /No LLM API keys found/)
    end

    it "skips providers with empty keys" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("")

      expect { default_config.llm_api_keys }.to raise_error(Kodo::Error)
    end
  end

  describe ".ensure_home_dir!" do
    it "creates home directory structure" do
      allow(Kodo).to receive(:home_dir).and_return(File.join(tmpdir, ".kodo"))

      described_class.ensure_home_dir!

      expect(File.directory?(File.join(tmpdir, ".kodo"))).to be true
      expect(File.directory?(File.join(tmpdir, ".kodo", "memory", "conversations"))).to be true
      expect(File.directory?(File.join(tmpdir, ".kodo", "memory", "knowledge"))).to be true
      expect(File.directory?(File.join(tmpdir, ".kodo", "memory", "audit"))).to be true
      expect(File.directory?(File.join(tmpdir, ".kodo", "skills"))).to be true
      expect(File.exist?(File.join(tmpdir, ".kodo", "config.yml"))).to be true
    end

    it "does not overwrite existing config" do
      home = File.join(tmpdir, ".kodo")
      FileUtils.mkdir_p(home)
      config_path = File.join(home, "config.yml")
      File.write(config_path, "custom: true\n")

      allow(Kodo).to receive(:home_dir).and_return(home)
      described_class.ensure_home_dir!

      expect(File.read(config_path)).to eq("custom: true\n")
    end
  end
end
