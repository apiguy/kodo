# frozen_string_literal: true

RSpec.describe Kodo::Search::Result do
  describe "construction" do
    it "creates a result with all fields" do
      result = described_class.new(
        title: "Ruby Lang",
        url: "https://ruby-lang.org",
        snippet: "A dynamic language",
        content: "Full page content here"
      )

      expect(result.title).to eq("Ruby Lang")
      expect(result.url).to eq("https://ruby-lang.org")
      expect(result.snippet).to eq("A dynamic language")
      expect(result.content).to eq("Full page content here")
    end

    it "defaults content to nil" do
      result = described_class.new(
        title: "Ruby Lang",
        url: "https://ruby-lang.org",
        snippet: "A dynamic language"
      )

      expect(result.content).to be_nil
    end
  end

  describe "immutability" do
    it "is frozen" do
      result = described_class.new(
        title: "Ruby Lang",
        url: "https://ruby-lang.org",
        snippet: "A dynamic language"
      )

      expect(result).to be_frozen
    end
  end

  describe "equality" do
    it "is equal to another result with the same fields" do
      a = described_class.new(title: "T", url: "U", snippet: "S")
      b = described_class.new(title: "T", url: "U", snippet: "S")

      expect(a).to eq(b)
    end
  end
end
