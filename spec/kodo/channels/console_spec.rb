# frozen_string_literal: true

RSpec.describe Kodo::Channels::Console do
  subject(:console) { described_class.new }

  describe "#connect!" do
    it "sets the channel as running" do
      console.connect!
      expect(console).to be_running
    end
  end

  describe "#disconnect!" do
    it "stops the channel" do
      console.connect!
      console.disconnect!
      expect(console).not_to be_running
    end
  end

  describe "#channel_id" do
    it "returns 'console'" do
      expect(console.channel_id).to eq("console")
    end
  end

  describe "#push and #poll" do
    it "delivers pushed messages via poll" do
      console.push("Hello!")

      messages = console.poll
      expect(messages.length).to eq(1)
      expect(messages.first.content).to eq("Hello!")
      expect(messages.first.sender).to eq(:user)
      expect(messages.first.channel_id).to eq("console")
    end

    it "returns empty when nothing is queued" do
      expect(console.poll).to eq([])
    end

    it "delivers multiple messages in order" do
      console.push("first")
      console.push("second")
      console.push("third")

      messages = console.poll
      expect(messages.map(&:content)).to eq(%w[first second third])
    end

    it "drains the queue on poll" do
      console.push("once")

      expect(console.poll.length).to eq(1)
      expect(console.poll).to eq([])
    end
  end

  describe "#send_message" do
    it "prints to stdout with formatting" do
      msg = Kodo::Message.new(
        channel_id: "console",
        sender: :agent,
        content: "Hello, human!"
      )

      expect { console.send_message(msg) }.to output(/Kodo:.*Hello, human!/).to_stdout
    end
  end
end
