# frozen_string_literal: true

RSpec.describe Kodo::Tools::StoreSecret, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:passphrase) { "test-passphrase" }
  let(:secrets_store) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    Kodo::Secrets::Store.new(passphrase: passphrase, secrets_dir: tmpdir)
  end
  let(:audit) do
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end
  let(:broker) { Kodo::Secrets::Broker.new(store: secrets_store, audit: audit) }
  let(:callback_calls) { [] }
  let(:on_secret_stored) { ->(name) { callback_calls << name } }
  let(:tool) { described_class.new(broker: broker, audit: audit, on_secret_stored: on_secret_stored) }

  describe "#execute" do
    it "stores a valid tavily key" do
      result = tool.execute(secret_name: "tavily_api_key", secret_value: "tvly-abc123")
      expect(result).to include("stored")
      expect(secrets_store.get("tavily_api_key")).to eq("tvly-abc123")
    end

    it "rejects unknown secret names" do
      result = tool.execute(secret_name: "unknown_key", secret_value: "value")
      expect(result).to include("Unknown secret")
    end

    it "validates prefix for tavily keys" do
      result = tool.execute(secret_name: "tavily_api_key", secret_value: "wrong-prefix")
      expect(result).to include("expected to start with")
    end

    it "validates prefix for anthropic keys" do
      result = tool.execute(secret_name: "anthropic_api_key", secret_value: "wrong-prefix")
      expect(result).to include("expected to start with")
    end

    it "accepts keys without a defined prefix" do
      result = tool.execute(secret_name: "gemini_api_key", secret_value: "any-value")
      expect(result).to include("stored")
    end

    it "enforces rate limiting" do
      tool.execute(secret_name: "tavily_api_key", secret_value: "tvly-key1")
      tool.execute(secret_name: "anthropic_api_key", secret_value: "sk-ant-key2")
      result = tool.execute(secret_name: "gemini_api_key", secret_value: "key3")
      expect(result).to include("Rate limit")
    end

    it "resets rate limit between turns" do
      tool.execute(secret_name: "tavily_api_key", secret_value: "tvly-key1")
      tool.execute(secret_name: "anthropic_api_key", secret_value: "sk-ant-key2")
      tool.reset_turn_count!
      result = tool.execute(secret_name: "gemini_api_key", secret_value: "key3")
      expect(result).to include("stored")
    end

    it "logs an audit event" do
      tool.execute(secret_name: "tavily_api_key", secret_value: "tvly-abc123")

      events = audit.today
      expect(events.any? { |e| e["event"] == "secret_stored_via_tool" }).to be true
    end

    it "calls the on_secret_stored callback" do
      tool.execute(secret_name: "tavily_api_key", secret_value: "tvly-abc123")
      expect(callback_calls).to eq(["tavily_api_key"])
    end

    it "works without a callback" do
      tool_no_cb = described_class.new(broker: broker, audit: audit)
      result = tool_no_cb.execute(secret_name: "tavily_api_key", secret_value: "tvly-abc123")
      expect(result).to include("stored")
    end
  end

  describe "#name" do
    it "returns store_secret" do
      expect(tool.name).to eq("store_secret")
    end
  end
end
