# frozen_string_literal: true

RSpec.describe Kodo::Tools::RecallFacts, :tmpdir do
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
    it "returns 'recall_facts'" do
      expect(tool.name).to eq("recall_facts")
    end
  end

  describe "#execute" do
    before do
      knowledge.remember(category: "preference", content: "Prefers Ruby over Python")
      knowledge.remember(category: "fact", content: "Lives in Portland")
      knowledge.remember(category: "preference", content: "Likes concise answers")
    end

    it "returns all facts with no filters" do
      result = tool.execute

      expect(result).to include("3 fact(s)")
      expect(result).to include("Prefers Ruby over Python")
      expect(result).to include("Lives in Portland")
    end

    it "filters by category" do
      result = tool.execute(category: "preference")

      expect(result).to include("2 fact(s)")
      expect(result).to include("Ruby")
      expect(result).not_to include("Portland")
    end

    it "filters by query" do
      result = tool.execute(query: "ruby")

      expect(result).to include("1 fact(s)")
      expect(result).to include("Ruby")
    end

    it "combines filters" do
      result = tool.execute(query: "concise", category: "preference")

      expect(result).to include("1 fact(s)")
      expect(result).to include("concise")
    end

    it "returns message when no facts match" do
      result = tool.execute(query: "nonexistent")

      expect(result).to include("No facts found")
    end

    it "rejects invalid category" do
      result = tool.execute(category: "invalid")

      expect(result).to include("Invalid category")
    end

    it "includes fact IDs in output" do
      result = tool.execute
      expect(result).to match(/id: [0-9a-f-]{36}/)
    end

    it "logs to audit trail" do
      tool.execute(query: "test")

      events = audit.today
      expect(events.any? { |e| e["event"] == "tool_recall_facts" }).to be true
    end
  end

  describe "with empty knowledge store" do
    it "returns no facts message" do
      result = tool.execute

      expect(result).to include("No facts found")
    end
  end
end
