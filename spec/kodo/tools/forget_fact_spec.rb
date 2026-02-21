# frozen_string_literal: true

RSpec.describe Kodo::Tools::ForgetFact, :tmpdir do
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
    it "returns 'forget'" do
      expect(tool.name).to eq("forget")
    end
  end

  describe "#execute" do
    it "soft-deletes a fact and returns confirmation" do
      fact = knowledge.remember(category: "fact", content: "test")

      result = tool.execute(id: fact["id"])

      expect(result).to include("Forgot fact")
      expect(result).to include("test")
      expect(knowledge.count).to eq(0)
    end

    it "returns error for unknown id" do
      result = tool.execute(id: "nonexistent")

      expect(result).to include("No active fact found")
    end

    it "logs to audit trail" do
      fact = knowledge.remember(category: "fact", content: "to forget")
      tool.execute(id: fact["id"])

      events = audit.today
      expect(events.any? { |e| e["event"] == "knowledge_forgotten" }).to be true
    end

    it "cannot forget an already forgotten fact" do
      fact = knowledge.remember(category: "fact", content: "test")
      tool.execute(id: fact["id"])

      result = tool.execute(id: fact["id"])
      expect(result).to include("No active fact found")
    end
  end
end
