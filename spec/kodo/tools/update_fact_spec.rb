# frozen_string_literal: true

RSpec.describe Kodo::Tools::UpdateFact, :tmpdir do
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
    it "returns 'update_fact'" do
      expect(tool.name).to eq("update_fact")
    end
  end

  describe "#execute" do
    it "updates a fact's content" do
      fact = knowledge.remember(category: "fact", content: "Lives in Portland")

      result = tool.execute(id: fact["id"], content: "Lives in Seattle")

      expect(result).to include("Updated fact")
      expect(result).to include("Lives in Seattle")
      expect(knowledge.count).to eq(1)
      expect(knowledge.all_active.first["content"]).to eq("Lives in Seattle")
    end

    it "preserves category and source" do
      fact = knowledge.remember(category: "preference", content: "Likes Ruby", source: "inference")

      tool.execute(id: fact["id"], content: "Loves Ruby")

      updated = knowledge.all_active.first
      expect(updated["category"]).to eq("preference")
      expect(updated["source"]).to eq("inference")
    end

    it "returns error for unknown id" do
      result = tool.execute(id: "nonexistent", content: "new content")

      expect(result).to include("No active fact found")
    end

    it "rejects content over 500 chars" do
      fact = knowledge.remember(category: "fact", content: "test")

      result = tool.execute(id: fact["id"], content: "x" * 501)

      expect(result).to include("too long")
      expect(knowledge.all_active.first["content"]).to eq("test")
    end

    it "rejects sensitive content" do
      fact = knowledge.remember(category: "fact", content: "test")

      result = tool.execute(id: fact["id"], content: "password: hunter2")

      expect(result).to include("sensitive data")
      expect(knowledge.all_active.first["content"]).to eq("test")
    end

    it "logs to audit trail" do
      fact = knowledge.remember(category: "fact", content: "old")
      tool.execute(id: fact["id"], content: "new")

      events = audit.today
      expect(events.any? { |e| e["event"] == "knowledge_updated" }).to be true
    end
  end

  describe "rate limiting" do
    it "allows up to MAX_PER_TURN calls" do
      described_class::MAX_PER_TURN.times do |i|
        fact = knowledge.remember(category: "fact", content: "fact #{i}")
        result = tool.execute(id: fact["id"], content: "updated #{i}")
        expect(result).to include("Updated")
      end
    end

    it "rejects calls beyond MAX_PER_TURN" do
      facts = (described_class::MAX_PER_TURN + 1).times.map do |i|
        knowledge.remember(category: "fact", content: "fact #{i}")
      end

      described_class::MAX_PER_TURN.times do |i|
        tool.execute(id: facts[i]["id"], content: "updated #{i}")
      end

      result = tool.execute(id: facts.last["id"], content: "one too many")
      expect(result).to include("Rate limit")
    end

    it "resets after reset_turn_count!" do
      facts = (described_class::MAX_PER_TURN + 1).times.map do |i|
        knowledge.remember(category: "fact", content: "fact #{i}")
      end

      described_class::MAX_PER_TURN.times do |i|
        tool.execute(id: facts[i]["id"], content: "updated #{i}")
      end

      tool.reset_turn_count!

      result = tool.execute(id: facts.last["id"], content: "after reset")
      expect(result).to include("Updated")
    end
  end
end
