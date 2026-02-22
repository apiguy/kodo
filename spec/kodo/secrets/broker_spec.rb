# frozen_string_literal: true

RSpec.describe Kodo::Secrets::Broker, :tmpdir do
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
  let(:broker) { described_class.new(store: secrets_store, audit: audit) }

  describe "#fetch" do
    it "returns a secret from the store when authorized" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      expect(broker.fetch("tavily_api_key", requestor: "search")).to eq("tvly-abc123")
    end

    it "returns nil when requestor is not authorized" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      expect(broker.fetch("tavily_api_key", requestor: "llm")).to be_nil
    end

    it "logs access denied on unauthorized request" do
      broker.fetch("tavily_api_key", requestor: "unauthorized")

      events = audit.today
      expect(events.any? { |e| e["event"] == "secret_access_denied" }).to be true
    end

    it "falls back to env var when store is empty" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return("tvly-from-env")

      expect(broker.fetch("tavily_api_key", requestor: "search")).to eq("tvly-from-env")
    end

    it "prefers store over env var" do
      secrets_store.put("tavily_api_key", "tvly-from-store")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return("tvly-from-env")

      expect(broker.fetch("tavily_api_key", requestor: "search")).to eq("tvly-from-store")
    end

    it "returns nil when neither store nor env has the secret" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return(nil)

      expect(broker.fetch("tavily_api_key", requestor: "search")).to be_nil
    end

    it "allows LLM requestor to fetch provider keys" do
      secrets_store.put("anthropic_api_key", "sk-ant-test")
      expect(broker.fetch("anthropic_api_key", requestor: "llm")).to eq("sk-ant-test")
    end

    it "allows telegram requestor to fetch telegram token" do
      secrets_store.put("telegram_bot_token", "bot-token-123")
      expect(broker.fetch("telegram_bot_token", requestor: "telegram")).to eq("bot-token-123")
    end
  end

  describe "#fetch!" do
    it "returns the secret when available" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      expect(broker.fetch!("tavily_api_key", requestor: "search")).to eq("tvly-abc123")
    end

    it "raises when secret is not available" do
      expect { broker.fetch!("tavily_api_key", requestor: "search") }
        .to raise_error(Kodo::Error, /Secret not available/)
    end
  end

  describe "#store" do
    it "stores a secret via the backing store" do
      broker.store("tavily_api_key", "tvly-abc123", source: "chat", validated: true)
      expect(secrets_store.get("tavily_api_key")).to eq("tvly-abc123")
    end

    it "logs the storage event" do
      broker.store("tavily_api_key", "tvly-abc123")

      events = audit.today
      expect(events.any? { |e| e["event"] == "secret_stored" }).to be true
    end
  end

  describe "#available?" do
    it "returns true when secret exists in store" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      expect(broker.available?("tavily_api_key")).to be true
    end

    it "returns true when secret exists in env" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return("tvly-from-env")

      expect(broker.available?("tavily_api_key")).to be true
    end

    it "returns false when secret exists nowhere" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return(nil)

      expect(broker.available?("tavily_api_key")).to be false
    end

    it "does not require authorization" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      # available? doesn't check grants — any component can ask if a secret exists
      expect(broker.available?("tavily_api_key")).to be true
    end
  end

  describe "#sensitive_values" do
    it "returns values from the store" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      expect(broker.sensitive_values).to include("tvly-abc123")
    end

    it "returns values from env vars" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-from-env")

      expect(broker.sensitive_values).to include("sk-ant-from-env")
    end

    it "prefers store over env when both present" do
      secrets_store.put("tavily_api_key", "tvly-from-store")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TAVILY_API_KEY").and_return("tvly-from-env")

      values = broker.sensitive_values
      expect(values).to include("tvly-from-store")
      expect(values).not_to include("tvly-from-env")
    end

    it "excludes nil and empty values" do
      values = broker.sensitive_values
      expect(values).not_to include(nil)
      expect(values).not_to include("")
    end
  end

  describe "#configured_secrets" do
    it "returns names of secrets available in store or env" do
      secrets_store.put("tavily_api_key", "tvly-abc123")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")

      configured = broker.configured_secrets
      expect(configured).to include("tavily_api_key")
      expect(configured).to include("anthropic_api_key")
    end

    it "does not include unconfigured secrets" do
      configured = broker.configured_secrets
      expect(configured).not_to include("tavily_api_key")
    end
  end
end
