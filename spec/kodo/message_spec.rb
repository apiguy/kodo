# frozen_string_literal: true

RSpec.describe Kodo::Message do
  subject(:message) do
    described_class.new(
      channel_id: "telegram",
      sender: :user,
      content: "Hello, Kodo!"
    )
  end

  describe "construction" do
    it "generates a UUID id by default" do
      expect(message.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "assigns a timestamp by default" do
      expect(message.timestamp).to be_within(1).of(Time.now)
    end

    it "defaults metadata to an empty hash" do
      expect(message.metadata).to eq({})
    end

    it "preserves all provided fields" do
      msg = described_class.new(
        id: "custom-id",
        channel_id: "console",
        sender: :agent,
        content: "Hi there",
        timestamp: Time.at(0),
        metadata: { chat_id: "123" }
      )

      expect(msg.id).to eq("custom-id")
      expect(msg.channel_id).to eq("console")
      expect(msg.sender).to eq(:agent)
      expect(msg.content).to eq("Hi there")
      expect(msg.timestamp).to eq(Time.at(0))
      expect(msg.metadata).to eq({ chat_id: "123" })
    end

    it "generates unique IDs for different messages" do
      other = described_class.new(channel_id: "console", sender: :user, content: "test")
      expect(message.id).not_to eq(other.id)
    end
  end

  describe "sender predicates" do
    it "#from_user? returns true for user messages" do
      expect(message).to be_from_user
      expect(message).not_to be_from_agent
      expect(message).not_to be_from_system
    end

    it "#from_agent? returns true for agent messages" do
      msg = described_class.new(channel_id: "console", sender: :agent, content: "reply")
      expect(msg).to be_from_agent
      expect(msg).not_to be_from_user
    end

    it "#from_system? returns true for system messages" do
      msg = described_class.new(channel_id: "console", sender: :system, content: "notice")
      expect(msg).to be_from_system
    end
  end

  describe "#to_llm_message" do
    it "maps user sender to user role" do
      expect(message.to_llm_message).to eq({ role: "user", content: "Hello, Kodo!" })
    end

    it "maps agent sender to assistant role" do
      msg = described_class.new(channel_id: "console", sender: :agent, content: "reply")
      expect(msg.to_llm_message).to eq({ role: "assistant", content: "reply" })
    end
  end

  describe "immutability" do
    it "is frozen (Data.define)" do
      expect(message).to be_frozen
    end
  end
end
