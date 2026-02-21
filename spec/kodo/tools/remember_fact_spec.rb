# frozen_string_literal: true

RSpec.describe Kodo::Tools::RememberFact, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:knowledge) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "knowledge"))
    Kodo::Memory::Knowledge.new
  end
  let(:audit) do
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end
  let(:tool) { described_class.new(knowledge: knowledge, audit: audit) }

  describe "#name" do
    it "returns 'remember'" do
      expect(tool.name).to eq("remember")
    end
  end

  describe "#execute" do
    it "stores a fact and returns confirmation" do
      result = tool.execute(category: "preference", content: "Likes Ruby")

      expect(result).to include("Remembered")
      expect(result).to include("Likes Ruby")
      expect(knowledge.count).to eq(1)
    end

    it "rejects invalid category" do
      result = tool.execute(category: "invalid", content: "test")

      expect(result).to include("Invalid category")
      expect(knowledge.count).to eq(0)
    end

    it "rejects content over 500 chars" do
      result = tool.execute(category: "fact", content: "x" * 501)

      expect(result).to include("too long")
      expect(knowledge.count).to eq(0)
    end

    it "accepts content at exactly 500 chars" do
      result = tool.execute(category: "fact", content: "x" * 500)

      expect(result).to include("Remembered")
    end

    it "logs to audit trail" do
      tool.execute(category: "fact", content: "test fact")

      events = audit.today
      expect(events.any? { |e| e["event"] == "knowledge_remembered" }).to be true
    end
  end

  describe "sensitive data filtering" do
    it "rejects SSN patterns" do
      result = tool.execute(category: "fact", content: "My SSN is 123-45-6789")
      expect(result).to include("sensitive data")
    end

    it "rejects credit card patterns" do
      result = tool.execute(category: "fact", content: "Card: 4111 1111 1111 1111")
      expect(result).to include("sensitive data")
    end

    it "rejects API key patterns" do
      result = tool.execute(category: "fact", content: "My key is sk-abc123def456ghi789")
      expect(result).to include("sensitive data")
    end

    it "rejects password patterns" do
      result = tool.execute(category: "fact", content: "password: hunter2")
      expect(result).to include("sensitive data")
    end

    it "allows normal content" do
      result = tool.execute(category: "fact", content: "I'm a Ruby developer in Portland")
      expect(result).to include("Remembered")
    end
  end

  describe "rate limiting" do
    it "allows up to MAX_PER_TURN calls" do
      described_class::MAX_PER_TURN.times do |i|
        result = tool.execute(category: "fact", content: "fact #{i}")
        expect(result).to include("Remembered")
      end
    end

    it "rejects calls beyond MAX_PER_TURN" do
      described_class::MAX_PER_TURN.times do |i|
        tool.execute(category: "fact", content: "fact #{i}")
      end

      result = tool.execute(category: "fact", content: "one too many")
      expect(result).to include("Rate limit")
    end

    it "resets after reset_turn_count!" do
      described_class::MAX_PER_TURN.times do |i|
        tool.execute(category: "fact", content: "fact #{i}")
      end

      tool.reset_turn_count!

      result = tool.execute(category: "fact", content: "after reset")
      expect(result).to include("Remembered")
    end
  end

  describe "when knowledge store is full" do
    it "returns an error message" do
      stub_const("Kodo::Memory::Knowledge::MAX_FACTS", 1)
      tool.execute(category: "fact", content: "fills it up")

      result = tool.execute(category: "fact", content: "overflow")
      expect(result).to include("full")
    end
  end
end
