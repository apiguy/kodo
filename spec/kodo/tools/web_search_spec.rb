# frozen_string_literal: true

RSpec.describe Kodo::Tools::WebSearch, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end

  let(:search_provider) { instance_double(Kodo::Search::Tavily) }
  let(:tool) { described_class.new(search_provider: search_provider, audit: audit) }

  let(:sample_results) do
    [
      Kodo::Search::Result.new(
        title: "Ruby 3.3 Released",
        url: "https://ruby-lang.org/news",
        snippet: "Ruby 3.3 brings performance improvements."
      ),
      Kodo::Search::Result.new(
        title: "Ruby Changelog",
        url: "https://example.com/changelog",
        snippet: "Full changelog for Ruby releases."
      )
    ]
  end

  describe "#name" do
    it "returns 'web_search'" do
      expect(tool.name).to eq("web_search")
    end
  end

  describe "#execute" do
    it "returns formatted search results" do
      allow(search_provider).to receive(:search).and_return(sample_results)

      result = tool.execute(query: "Ruby 3.3")

      expect(result).to include("1. Ruby 3.3 Released")
      expect(result).to include("https://ruby-lang.org/news")
      expect(result).to include("Ruby 3.3 brings performance improvements.")
      expect(result).to include("2. Ruby Changelog")
    end

    it "passes max_results to search provider" do
      allow(search_provider).to receive(:search).with("test", max_results: 3).and_return([])

      tool.execute(query: "test", max_results: "3")
    end

    it "clamps max_results to 1-10 range" do
      allow(search_provider).to receive(:search).with("test", max_results: 10).and_return([])
      tool.execute(query: "test", max_results: "99")

      allow(search_provider).to receive(:search).with("test", max_results: 1).and_return([])
      tool.execute(query: "test", max_results: "0")
    end

    it "returns message when no results found" do
      allow(search_provider).to receive(:search).and_return([])

      result = tool.execute(query: "obscure query xyz")
      expect(result).to include("No results found")
    end

    it "logs to audit trail" do
      allow(search_provider).to receive(:search).and_return(sample_results)

      tool.execute(query: "Ruby 3.3")

      events = audit.today
      expect(events.any? { |e| e["event"] == "web_search" }).to be true
    end

    it "returns error message on search failure" do
      allow(search_provider).to receive(:search).and_raise(Kodo::Error, "Tavily API timeout")

      result = tool.execute(query: "test")
      expect(result).to eq("Tavily API timeout")
    end
  end

  describe "rate limiting" do
    before do
      allow(search_provider).to receive(:search).and_return(sample_results)
    end

    it "allows up to MAX_PER_TURN searches" do
      described_class::MAX_PER_TURN.times do
        result = tool.execute(query: "test")
        expect(result).not_to include("Rate limit")
      end
    end

    it "rejects searches beyond MAX_PER_TURN" do
      described_class::MAX_PER_TURN.times { tool.execute(query: "test") }

      result = tool.execute(query: "one more")
      expect(result).to include("Rate limit")
    end

    it "resets after reset_turn_count!" do
      described_class::MAX_PER_TURN.times { tool.execute(query: "test") }

      tool.reset_turn_count!

      result = tool.execute(query: "after reset")
      expect(result).not_to include("Rate limit")
    end
  end
end
