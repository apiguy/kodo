# frozen_string_literal: true

RSpec.describe Kodo::Secrets::Store, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:passphrase) { "test-passphrase-for-secrets" }
  let(:store) { described_class.new(passphrase: passphrase, secrets_dir: tmpdir) }

  before do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
  end

  describe "#put and #get" do
    it "stores and retrieves a secret" do
      store.put("tavily_api_key", "tvly-abc123")
      expect(store.get("tavily_api_key")).to eq("tvly-abc123")
    end

    it "stores metadata with the secret" do
      store.put("tavily_api_key", "tvly-abc123", source: "chat", validated: true)
      expect(store.get("tavily_api_key")).to eq("tvly-abc123")
    end

    it "overwrites an existing secret" do
      store.put("tavily_api_key", "tvly-old")
      store.put("tavily_api_key", "tvly-new")
      expect(store.get("tavily_api_key")).to eq("tvly-new")
    end
  end

  describe "#get" do
    it "returns nil for a missing secret" do
      expect(store.get("nonexistent")).to be_nil
    end
  end

  describe "#exists?" do
    it "returns true when secret exists" do
      store.put("tavily_api_key", "tvly-abc123")
      expect(store.exists?("tavily_api_key")).to be true
    end

    it "returns false when secret does not exist" do
      expect(store.exists?("tavily_api_key")).to be false
    end
  end

  describe "#delete" do
    it "removes a secret and returns true" do
      store.put("tavily_api_key", "tvly-abc123")
      expect(store.delete("tavily_api_key")).to be true
      expect(store.get("tavily_api_key")).to be_nil
    end

    it "returns false when secret does not exist" do
      expect(store.delete("nonexistent")).to be false
    end
  end

  describe "#names" do
    it "returns all stored secret names" do
      store.put("tavily_api_key", "tvly-abc123")
      store.put("anthropic_api_key", "sk-ant-abc123")
      expect(store.names).to contain_exactly("tavily_api_key", "anthropic_api_key")
    end

    it "returns empty array when no secrets stored" do
      expect(store.names).to eq([])
    end
  end

  describe "encryption round-trip" do
    it "persists secrets encrypted and loads them back" do
      store.put("tavily_api_key", "tvly-abc123")

      # Create a new store instance that reads from the same file
      store2 = described_class.new(passphrase: passphrase, secrets_dir: tmpdir)
      expect(store2.get("tavily_api_key")).to eq("tvly-abc123")
    end

    it "encrypts the file on disk" do
      store.put("tavily_api_key", "tvly-abc123")

      raw = File.binread(File.join(tmpdir, "secrets.enc"))
      expect(Kodo::Memory::Encryption.encrypted?(raw)).to be true
      expect(raw).not_to include("tvly-abc123")
    end
  end

  describe "#metadata" do
    it "returns source, validated, and stored_at for a secret" do
      store.put("tavily_api_key", "tvly-abc123", source: "chat", validated: true)
      meta = store.metadata("tavily_api_key")

      expect(meta[:source]).to eq("chat")
      expect(meta[:validated]).to be true
      expect(meta[:stored_at]).not_to be_nil
    end

    it "returns nil for a missing secret" do
      expect(store.metadata("nonexistent")).to be_nil
    end
  end

  describe "missing file" do
    it "starts with empty secrets when file does not exist" do
      fresh = described_class.new(passphrase: passphrase, secrets_dir: tmpdir)
      expect(fresh.names).to eq([])
    end
  end

  describe "corrupt file" do
    it "falls back to empty secrets on corrupt file" do
      File.write(File.join(tmpdir, "secrets.enc"), "not valid json or encrypted")
      fresh = described_class.new(passphrase: passphrase, secrets_dir: tmpdir)
      expect(fresh.names).to eq([])
    end
  end
end
