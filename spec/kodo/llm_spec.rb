# frozen_string_literal: true

RSpec.describe Kodo::LLM do
  let(:config) do
    Kodo::Config.new(
      Kodo::Config::DEFAULTS.merge(
        "llm" => Kodo::Config::DEFAULTS["llm"].merge(
          "utility_model" => "claude-haiku-4-5-20251001"
        )
      )
    )
  end

  before do
    allow(Kodo).to receive(:config).and_return(config)
  end

  describe ".utility_chat" do
    it "creates a chat with the configured utility model" do
      chat = instance_double("RubyLLM::Chat")
      allow(RubyLLM).to receive(:chat).with(model: "claude-haiku-4-5-20251001").and_return(chat)

      expect(described_class.utility_chat).to eq(chat)
    end

    it "accepts a model override" do
      chat = instance_double("RubyLLM::Chat")
      allow(RubyLLM).to receive(:chat).with(model: "custom-model").and_return(chat)

      expect(described_class.utility_chat(model: "custom-model")).to eq(chat)
    end

    it "uses haiku by default" do
      default_config = Kodo::Config.new(Kodo::Config::DEFAULTS)
      allow(Kodo).to receive(:config).and_return(default_config)

      chat = instance_double("RubyLLM::Chat")
      allow(RubyLLM).to receive(:chat).with(model: "claude-haiku-4-5-20251001").and_return(chat)

      expect(described_class.utility_chat).to eq(chat)
    end
  end
end
