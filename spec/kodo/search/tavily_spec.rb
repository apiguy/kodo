# frozen_string_literal: true

RSpec.describe Kodo::Search::Tavily do
  let(:api_key) { "tvly-test-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  let(:success_body) do
    {
      "results" => [
        {
          "title" => "Ruby 3.3 Released",
          "url" => "https://ruby-lang.org/news/ruby-3-3",
          "content" => "Ruby 3.3 brings performance improvements.",
          "raw_content" => "Full article text here."
        },
        {
          "title" => "Ruby Changelog",
          "url" => "https://example.com/changelog",
          "content" => "Changelog for Ruby releases.",
          "raw_content" => nil
        }
      ]
    }.to_json
  end

  def stub_tavily_request(status: 200, body: success_body)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).with("api.tavily.com", 443).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:open_timeout=)

    response = instance_double(Net::HTTPResponse, code: status.to_s, message: "OK", body: body)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == 200)
    allow(http).to receive(:request).and_return(response)

    http
  end

  describe "#search" do
    it "returns an array of Result objects" do
      stub_tavily_request

      results = provider.search("Ruby 3.3")

      expect(results.length).to eq(2)
      expect(results.first).to be_a(Kodo::Search::Result)
      expect(results.first.title).to eq("Ruby 3.3 Released")
      expect(results.first.url).to eq("https://ruby-lang.org/news/ruby-3-3")
      expect(results.first.snippet).to eq("Ruby 3.3 brings performance improvements.")
      expect(results.first.content).to eq("Full article text here.")
    end

    it "handles results with nil raw_content" do
      stub_tavily_request

      results = provider.search("Ruby 3.3")

      expect(results.last.content).to be_nil
    end

    it "sends the correct request body" do
      http = stub_tavily_request

      expect(http).to receive(:request) do |req|
        body = JSON.parse(req.body)
        expect(body["api_key"]).to eq("tvly-test-key")
        expect(body["query"]).to eq("Ruby 3.3")
        expect(body["max_results"]).to eq(3)

        response = instance_double(Net::HTTPResponse, code: "200", message: "OK", body: success_body)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        response
      end

      provider.search("Ruby 3.3", max_results: 3)
    end

    it "raises Kodo::Error on non-success HTTP status" do
      stub_tavily_request(status: 401, body: '{"error":"invalid api key"}')

      expect { provider.search("test") }.to raise_error(Kodo::Error, /Tavily API error: 401/)
    end

    it "raises Kodo::Error on timeout" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout, "execution expired")

      expect { provider.search("test") }.to raise_error(Kodo::Error, /timeout/i)
    end

    it "raises Kodo::Error on invalid JSON response" do
      stub_tavily_request(body: "not json at all")

      expect { provider.search("test") }.to raise_error(Kodo::Error, /invalid JSON/i)
    end

    it "raises Kodo::Error on connection failure" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_raise(SocketError, "getaddrinfo: Name or service not known")

      expect { provider.search("test") }.to raise_error(Kodo::Error, /connection failed/i)
    end

    it "returns empty array when results key is missing" do
      stub_tavily_request(body: '{}')

      results = provider.search("test")
      expect(results).to eq([])
    end
  end
end
