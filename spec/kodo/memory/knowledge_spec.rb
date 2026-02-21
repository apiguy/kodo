# frozen_string_literal: true

RSpec.describe Kodo::Memory::Knowledge, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:knowledge) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "knowledge"))
    described_class.new
  end

  describe "#remember" do
    it "stores a fact and returns it" do
      fact = knowledge.remember(category: "preference", content: "Likes Ruby")

      expect(fact["id"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(fact["category"]).to eq("preference")
      expect(fact["content"]).to eq("Likes Ruby")
      expect(fact["source"]).to eq("explicit")
      expect(fact["active"]).to be true
    end

    it "persists facts to disk as JSONL" do
      knowledge.remember(category: "fact", content: "Lives in Portland")

      path = File.join(tmpdir, "memory", "knowledge", "global.jsonl")
      expect(File.exist?(path)).to be true

      lines = File.readlines(path).reject(&:empty?)
      expect(lines.length).to eq(1)

      parsed = JSON.parse(lines.first)
      expect(parsed["content"]).to eq("Lives in Portland")
    end

    it "rejects invalid categories" do
      expect {
        knowledge.remember(category: "invalid", content: "test")
      }.to raise_error(Kodo::Error, /Invalid category/)
    end

    it "accepts all valid categories" do
      %w[preference fact instruction context].each do |cat|
        expect {
          knowledge.remember(category: cat, content: "test #{cat}")
        }.not_to raise_error
      end
    end

    it "defaults source to explicit" do
      fact = knowledge.remember(category: "fact", content: "test")
      expect(fact["source"]).to eq("explicit")
    end

    it "accepts inference as source" do
      fact = knowledge.remember(category: "fact", content: "test", source: "inference")
      expect(fact["source"]).to eq("inference")
    end

    it "enforces MAX_FACTS limit" do
      stub_const("Kodo::Memory::Knowledge::MAX_FACTS", 3)

      3.times { |i| knowledge.remember(category: "fact", content: "fact #{i}") }

      expect {
        knowledge.remember(category: "fact", content: "one too many")
      }.to raise_error(Kodo::Error, /full/)
    end
  end

  describe "#forget" do
    it "soft-deletes a fact" do
      fact = knowledge.remember(category: "fact", content: "test")
      knowledge.forget(fact["id"])

      expect(knowledge.all_active).to be_empty
    end

    it "returns the forgotten fact" do
      fact = knowledge.remember(category: "fact", content: "test")
      result = knowledge.forget(fact["id"])

      expect(result["active"]).to be false
      expect(result["content"]).to eq("test")
    end

    it "returns nil for unknown id" do
      expect(knowledge.forget("nonexistent")).to be_nil
    end

    it "does not count forgotten facts toward active count" do
      fact = knowledge.remember(category: "fact", content: "test")
      knowledge.forget(fact["id"])

      expect(knowledge.count).to eq(0)
    end
  end

  describe "#all_active" do
    it "returns only active facts" do
      f1 = knowledge.remember(category: "fact", content: "active")
      f2 = knowledge.remember(category: "fact", content: "will forget")
      knowledge.forget(f2["id"])

      active = knowledge.all_active
      expect(active.length).to eq(1)
      expect(active.first["id"]).to eq(f1["id"])
    end
  end

  describe "#recall" do
    before do
      knowledge.remember(category: "preference", content: "Prefers Ruby over Python")
      knowledge.remember(category: "fact", content: "Lives in Portland")
      knowledge.remember(category: "preference", content: "Likes concise answers")
    end

    it "returns all active facts with no filters" do
      expect(knowledge.recall.length).to eq(3)
    end

    it "filters by category" do
      results = knowledge.recall(category: "preference")
      expect(results.length).to eq(2)
      expect(results.all? { |f| f["category"] == "preference" }).to be true
    end

    it "filters by keyword query (case-insensitive)" do
      results = knowledge.recall(query: "ruby")
      expect(results.length).to eq(1)
      expect(results.first["content"]).to include("Ruby")
    end

    it "combines category and query filters" do
      results = knowledge.recall(category: "preference", query: "concise")
      expect(results.length).to eq(1)
      expect(results.first["content"]).to include("concise")
    end

    it "returns empty for no matches" do
      expect(knowledge.recall(query: "nonexistent")).to be_empty
    end
  end

  describe "#count" do
    it "returns number of active facts" do
      3.times { |i| knowledge.remember(category: "fact", content: "fact #{i}") }
      expect(knowledge.count).to eq(3)
    end
  end

  describe "#for_prompt" do
    it "returns nil when no facts exist" do
      expect(knowledge.for_prompt).to be_nil
    end

    it "returns formatted markdown grouped by category" do
      knowledge.remember(category: "preference", content: "Likes Ruby")
      knowledge.remember(category: "fact", content: "Lives in Portland")

      prompt = knowledge.for_prompt
      expect(prompt).to include("Preferences")
      expect(prompt).to include("- Likes Ruby")
      expect(prompt).to include("Facts")
      expect(prompt).to include("- Lives in Portland")
    end

    it "truncates at MAX_PROMPT_CHARS" do
      stub_const("Kodo::Memory::Knowledge::MAX_PROMPT_CHARS", 100)

      10.times { |i| knowledge.remember(category: "fact", content: "A long fact number #{i} " * 5) }

      prompt = knowledge.for_prompt
      expect(prompt.length).to be <= 100 + 30 # room for truncation message
      expect(prompt).to include("[Knowledge truncated]")
    end
  end

  describe "persistence" do
    it "loads facts from disk on initialization" do
      knowledge.remember(category: "fact", content: "persisted fact")

      new_knowledge = described_class.new
      expect(new_knowledge.count).to eq(1)
      expect(new_knowledge.all_active.first["content"]).to eq("persisted fact")
    end
  end

  describe "encrypted persistence" do
    let(:passphrase) { "test-secret" }
    let(:encrypted_knowledge) do
      allow(Kodo).to receive(:home_dir).and_return(tmpdir)
      FileUtils.mkdir_p(File.join(tmpdir, "memory", "knowledge"))
      described_class.new(passphrase: passphrase)
    end

    it "encrypts data on disk" do
      encrypted_knowledge.remember(category: "fact", content: "secret fact")

      path = File.join(tmpdir, "memory", "knowledge", "global.jsonl")
      raw = File.binread(path)
      expect(Kodo::Memory::Encryption.encrypted?(raw)).to be true
      expect(raw).not_to include("secret fact")
    end

    it "decrypts on reload" do
      encrypted_knowledge.remember(category: "fact", content: "secret fact")

      reloaded = described_class.new(passphrase: passphrase)
      expect(reloaded.count).to eq(1)
      expect(reloaded.all_active.first["content"]).to eq("secret fact")
    end
  end
end
