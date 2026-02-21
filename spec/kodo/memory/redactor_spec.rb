# frozen_string_literal: true

RSpec.describe Kodo::Memory::Redactor do
  describe ".sensitive?" do
    it "detects SSN patterns" do
      expect(described_class.sensitive?("My SSN is 123-45-6789")).to be true
    end

    it "detects credit card patterns" do
      expect(described_class.sensitive?("Card: 4111 1111 1111 1111")).to be true
    end

    it "detects API key patterns" do
      expect(described_class.sensitive?("sk-abc123def456ghi789")).to be true
    end

    it "detects password patterns" do
      expect(described_class.sensitive?("password: hunter2")).to be true
    end

    it "returns false for normal content" do
      expect(described_class.sensitive?("I'm a Ruby developer")).to be false
    end
  end

  describe ".redact" do
    it "replaces SSNs with [REDACTED]" do
      result = described_class.redact("My SSN is 123-45-6789 ok?")
      expect(result).to eq("My SSN is [REDACTED] ok?")
      expect(result).not_to include("123-45-6789")
    end

    it "replaces credit card numbers" do
      result = described_class.redact("Pay with 4111 1111 1111 1111 please")
      expect(result).not_to include("4111")
      expect(result).to include("[REDACTED]")
    end

    it "replaces API keys" do
      result = described_class.redact("Use sk-abc123def456ghi789 for auth")
      expect(result).not_to include("sk-abc123def456ghi789")
      expect(result).to include("[REDACTED]")
    end

    it "replaces password values" do
      result = described_class.redact("The password: hunter2 is weak")
      expect(result).not_to include("hunter2")
      expect(result).to include("[REDACTED]")
    end

    it "replaces multiple sensitive values in one string" do
      result = described_class.redact("SSN: 123-45-6789 and password: secret123")
      expect(result).not_to include("123-45-6789")
      expect(result).not_to include("secret123")
      expect(result.scan("[REDACTED]").length).to eq(2)
    end

    it "returns the string unchanged when nothing is sensitive" do
      input = "I like Ruby and live in Portland"
      expect(described_class.redact(input)).to eq(input)
    end

    it "does not modify the original string" do
      input = "password: hunter2"
      described_class.redact(input)
      expect(input).to include("hunter2")
    end
  end

  describe ".redact_smart" do
    let(:llm_chat) { instance_double("RubyLLM::Chat") }
    let(:llm_response) { instance_double("RubyLLM::Response", content: "[]") }

    before do
      allow(Kodo::LLM).to receive(:utility_chat).and_return(llm_chat)
      allow(llm_chat).to receive(:ask).and_return(llm_response)
    end

    it "uses regex for messages with obvious patterns and skips LLM" do
      result = described_class.redact_smart("password: hunter2")
      expect(result).to include("[REDACTED]")
      expect(result).not_to include("hunter2")
      expect(Kodo::LLM).not_to have_received(:utility_chat)
    end

    it "calls LLM for messages regex does not flag" do
      allow(llm_response).to receive(:content).and_return('[{"start": 24, "end": 35}]')

      result = described_class.redact_smart("my database password is fluffybunny and that's it")
      expect(result).to include("[REDACTED]")
      expect(result).not_to include("fluffybunny")
      expect(Kodo::LLM).to have_received(:utility_chat)
    end

    it "returns original text when LLM finds nothing sensitive" do
      input = "I like Ruby and live in Portland"
      result = described_class.redact_smart(input)
      expect(result).to eq(input)
    end

    it "returns original text when LLM call fails" do
      allow(llm_chat).to receive(:ask).and_raise(StandardError.new("API timeout"))

      input = "my secret phrase is open sesame"
      result = described_class.redact_smart(input)
      expect(result).to eq(input)
    end
  end

  describe ".redact_with_llm" do
    let(:llm_chat) { instance_double("RubyLLM::Chat") }
    let(:llm_response) { instance_double("RubyLLM::Response") }

    before do
      allow(Kodo::LLM).to receive(:utility_chat).and_return(llm_chat)
      allow(llm_chat).to receive(:ask).and_return(llm_response)
    end

    it "redacts spans identified by the LLM" do
      allow(llm_response).to receive(:content).and_return('[{"start": 24, "end": 35}]')

      result = described_class.redact_with_llm("my database password is fluffybunny and that's it")
      expect(result).to eq("my database password is [REDACTED] and that's it")
    end

    it "returns original text when LLM returns empty array" do
      allow(llm_response).to receive(:content).and_return("[]")

      input = "nothing sensitive here"
      expect(described_class.redact_with_llm(input)).to eq(input)
    end

    it "handles multiple spans" do
      allow(llm_response).to receive(:content).and_return('[{"start": 16, "end": 22}, {"start": 42, "end": 51}]')

      result = described_class.redact_with_llm("my db password: secret and my api token is xyzzy1234")
      expect(result).to include("[REDACTED]")
      expect(result).not_to include("secret")
      expect(result).not_to include("xyzzy1234")
    end

    it "handles LLM response wrapped in markdown code fences" do
      allow(llm_response).to receive(:content).and_return("```json\n[{\"start\": 24, \"end\": 35}]\n```")

      result = described_class.redact_with_llm("my database password is fluffybunny and that's it")
      expect(result).to eq("my database password is [REDACTED] and that's it")
    end

    it "returns original text on invalid JSON response" do
      allow(llm_response).to receive(:content).and_return("I found a password!")

      input = "my secret is foobar"
      expect(described_class.redact_with_llm(input)).to eq(input)
    end

    it "returns original text when LLM raises an error" do
      allow(llm_chat).to receive(:ask).and_raise(StandardError.new("connection refused"))

      input = "my secret is foobar"
      expect(described_class.redact_with_llm(input)).to eq(input)
    end

    it "ignores spans with invalid offsets" do
      allow(llm_response).to receive(:content).and_return('[{"start": -1, "end": 5}, {"start": 10, "end": 3}]')

      input = "nothing to redact"
      expect(described_class.redact_with_llm(input)).to eq(input)
    end
  end
end
