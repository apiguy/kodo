# frozen_string_literal: true

RSpec.describe Kodo::Tools::FetchUrl, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end

  let(:tool) { described_class.new(audit: audit) }

  # Stub DNS resolution to return a safe public IP
  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  def stub_http_response(body: "<html><body>Hello World</body></html>", status: "200", headers: {})
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:open_timeout=)

    response = instance_double(Net::HTTPSuccess, code: status, message: "OK", body: body)
    allow(response).to receive(:is_a?).with(anything).and_return(false)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(response).to receive(:[]) { |key| headers[key] }
    allow(http).to receive(:request).and_return(response)

    http
  end

  def stub_redirect(location:, final_body: "<html><body>Final</body></html>")
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:open_timeout=)

    redirect_response = instance_double(Net::HTTPRedirection, code: "301", message: "Moved")
    allow(redirect_response).to receive(:is_a?).with(anything).and_return(false)
    allow(redirect_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
    allow(redirect_response).to receive(:[]).with("location").and_return(location)

    final_response = instance_double(Net::HTTPSuccess, code: "200", message: "OK", body: final_body)
    allow(final_response).to receive(:is_a?).with(anything).and_return(false)
    allow(final_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

    allow(http).to receive(:request).and_return(redirect_response, final_response)

    http
  end

  describe "#name" do
    it "returns 'fetch_url'" do
      expect(tool.name).to eq("fetch_url")
    end
  end

  describe "#execute" do
    it "fetches and extracts text from a URL" do
      stub_http_response(body: "<html><body><p>Hello World</p></body></html>")

      result = tool.execute(url: "https://example.com")
      expect(result).to include("Hello World")
    end

    it "rejects non-HTTP schemes" do
      result = tool.execute(url: "ftp://example.com/file")
      expect(result).to include("Only http and https")
    end

    it "rejects invalid URLs" do
      result = tool.execute(url: "not a url at all ://")
      expect(result).to include("Error:")
    end

    it "logs to audit trail" do
      stub_http_response

      tool.execute(url: "https://example.com")

      events = audit.today
      expect(events.any? { |e| e["event"] == "url_fetched" }).to be true
    end

    it "returns message for empty content" do
      stub_http_response(body: "<html><body></body></html>")

      result = tool.execute(url: "https://example.com/empty")
      expect(result).to include("No readable content")
    end
  end

  describe "SSRF protection" do
    it "blocks localhost" do
      allow(Resolv).to receive(:getaddresses).and_return(["127.0.0.1"])

      result = tool.execute(url: "https://localhost/admin")
      expect(result).to include("private/internal network")
    end

    it "blocks 10.x.x.x range" do
      allow(Resolv).to receive(:getaddresses).and_return(["10.0.0.1"])

      result = tool.execute(url: "https://internal.corp/secret")
      expect(result).to include("private/internal network")
    end

    it "blocks 172.16.x.x range" do
      allow(Resolv).to receive(:getaddresses).and_return(["172.16.0.1"])

      result = tool.execute(url: "https://internal.corp/secret")
      expect(result).to include("private/internal network")
    end

    it "blocks 192.168.x.x range" do
      allow(Resolv).to receive(:getaddresses).and_return(["192.168.1.1"])

      result = tool.execute(url: "https://router.local/config")
      expect(result).to include("private/internal network")
    end

    it "blocks link-local addresses" do
      allow(Resolv).to receive(:getaddresses).and_return(["169.254.1.1"])

      result = tool.execute(url: "https://metadata.internal/latest")
      expect(result).to include("private/internal network")
    end

    it "blocks IPv6 loopback" do
      allow(Resolv).to receive(:getaddresses).and_return(["::1"])

      result = tool.execute(url: "https://localhost/admin")
      expect(result).to include("private/internal network")
    end

    it "allows public IP addresses" do
      allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
      stub_http_response

      result = tool.execute(url: "https://example.com")
      expect(result).not_to include("private/internal network")
    end

    it "blocks unresolvable hostnames" do
      allow(Resolv).to receive(:getaddresses).and_return([])

      result = tool.execute(url: "https://nonexistent.invalid/page")
      expect(result).to include("Could not resolve")
    end
  end

  describe "redirect handling" do
    it "follows redirects" do
      stub_redirect(location: "https://example.com/final", final_body: "<p>Redirected content</p>")

      result = tool.execute(url: "https://example.com/old")
      expect(result).to include("Redirected content")
    end

    it "SSRF-checks redirect targets" do
      # First call resolves to public IP, redirect target resolves to private
      call_count = 0
      allow(Resolv).to receive(:getaddresses) do
        call_count += 1
        call_count <= 2 ? ["93.184.216.34"] : ["127.0.0.1"]
      end

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)

      redirect_response = instance_double(Net::HTTPRedirection, code: "301", message: "Moved")
      allow(redirect_response).to receive(:is_a?).with(anything).and_return(false)
      allow(redirect_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
      allow(redirect_response).to receive(:[]).with("location").and_return("https://evil.com/steal")
      allow(http).to receive(:request).and_return(redirect_response)

      result = tool.execute(url: "https://example.com/redirect")
      expect(result).to include("private/internal network")
    end

    it "limits redirect depth" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)

      redirect_response = instance_double(Net::HTTPRedirection, code: "301", message: "Moved")
      allow(redirect_response).to receive(:is_a?).with(anything).and_return(false)
      allow(redirect_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
      allow(redirect_response).to receive(:[]).with("location").and_return("https://example.com/loop")
      allow(http).to receive(:request).and_return(redirect_response)

      result = tool.execute(url: "https://example.com/loop")
      expect(result).to include("Too many redirects")
    end
  end

  describe "HTML extraction" do
    it "strips script tags" do
      stub_http_response(body: "<p>Hello</p><script>alert('xss')</script><p>World</p>")

      result = tool.execute(url: "https://example.com")
      expect(result).to include("Hello")
      expect(result).to include("World")
      expect(result).not_to include("alert")
    end

    it "strips style tags" do
      stub_http_response(body: "<p>Content</p><style>body { color: red; }</style>")

      result = tool.execute(url: "https://example.com")
      expect(result).to include("Content")
      expect(result).not_to include("color")
    end

    it "converts block tags to newlines" do
      stub_http_response(body: "<p>Paragraph 1</p><p>Paragraph 2</p>")

      result = tool.execute(url: "https://example.com")
      expect(result).to include("Paragraph 1")
      expect(result).to include("Paragraph 2")
    end

    it "decodes HTML entities" do
      stub_http_response(body: "<p>Tom &amp; Jerry &lt;3&gt;</p>")

      result = tool.execute(url: "https://example.com")
      expect(result).to include("Tom & Jerry <3>")
    end

    it "handles plain text (non-HTML) content" do
      stub_http_response(body: "Just plain text content here")

      result = tool.execute(url: "https://example.com/text")
      expect(result).to include("Just plain text content here")
    end
  end

  describe "content truncation" do
    it "truncates content beyond MAX_CONTENT_LENGTH" do
      long_content = "<p>#{"x" * 60_000}</p>"
      stub_http_response(body: long_content)

      result = tool.execute(url: "https://example.com/long")
      expect(result.length).to be <= described_class::MAX_CONTENT_LENGTH
    end
  end

  describe "rate limiting" do
    before do
      stub_http_response
    end

    it "allows up to MAX_PER_TURN fetches" do
      described_class::MAX_PER_TURN.times do
        result = tool.execute(url: "https://example.com")
        expect(result).not_to include("Rate limit")
      end
    end

    it "rejects fetches beyond MAX_PER_TURN" do
      described_class::MAX_PER_TURN.times { tool.execute(url: "https://example.com") }

      result = tool.execute(url: "https://example.com/another")
      expect(result).to include("Rate limit")
    end

    it "resets after reset_turn_count!" do
      described_class::MAX_PER_TURN.times { tool.execute(url: "https://example.com") }

      tool.reset_turn_count!

      result = tool.execute(url: "https://example.com")
      expect(result).not_to include("Rate limit")
    end
  end

  describe "error handling" do
    it "handles timeouts" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout, "execution expired")

      result = tool.execute(url: "https://slow.example.com")
      expect(result).to include("timed out")
    end

    it "handles connection failures" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_raise(SocketError, "getaddrinfo failed")

      result = tool.execute(url: "https://down.example.com")
      expect(result).to include("Connection failed")
    end

    it "handles HTTP error responses" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)

      error_response = instance_double(Net::HTTPResponse, code: "404", message: "Not Found")
      allow(error_response).to receive(:is_a?).with(anything).and_return(false)
      allow(http).to receive(:request).and_return(error_response)

      result = tool.execute(url: "https://example.com/missing")
      expect(result).to include("404")
    end
  end
end
