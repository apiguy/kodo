# frozen_string_literal: true

require "time"

RSpec.describe Kodo::Tools::SetReminder, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:reminders) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "reminders"))
    Kodo::Memory::Reminders.new
  end
  let(:audit) do
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end
  let(:tool) do
    t = described_class.new(reminders: reminders, audit: audit)
    t.channel_id = "console"
    t.chat_id = "chat1"
    t
  end

  let(:future_time) { (Time.now + 3600).iso8601 }

  describe "#name" do
    it "returns 'set_reminder'" do
      expect(tool.name).to eq("set_reminder")
    end
  end

  describe "#execute" do
    it "creates a reminder and returns confirmation" do
      result = tool.execute(content: "Stretch!", due_at: future_time)

      expect(result).to include("Reminder set")
      expect(result).to include("Stretch!")
      expect(reminders.active_count).to eq(1)
    end

    it "stores channel_id and chat_id" do
      tool.execute(content: "Test", due_at: future_time)

      reminder = reminders.all_active.first
      expect(reminder["channel_id"]).to eq("console")
      expect(reminder["chat_id"]).to eq("chat1")
    end

    it "rejects content over 500 chars" do
      result = tool.execute(content: "x" * 501, due_at: future_time)

      expect(result).to include("too long")
      expect(reminders.active_count).to eq(0)
    end

    it "rejects sensitive content" do
      result = tool.execute(content: "password: hunter2", due_at: future_time)

      expect(result).to include("sensitive data")
      expect(reminders.active_count).to eq(0)
    end

    it "rejects past times" do
      past = (Time.now - 3600).iso8601
      result = tool.execute(content: "Test", due_at: past)

      expect(result).to include("past")
      expect(reminders.active_count).to eq(0)
    end

    it "rejects invalid time format" do
      result = tool.execute(content: "Test", due_at: "not-a-time")

      expect(result).to include("Invalid time format")
      expect(reminders.active_count).to eq(0)
    end

    it "logs to audit trail" do
      tool.execute(content: "Test", due_at: future_time)

      events = audit.today
      expect(events.any? { |e| e["event"] == "reminder_set" }).to be true
    end
  end

  describe "rate limiting" do
    it "allows up to MAX_PER_TURN calls" do
      described_class::MAX_PER_TURN.times do |i|
        result = tool.execute(content: "reminder #{i}", due_at: (Time.now + 3600 + i).iso8601)
        expect(result).to include("Reminder set")
      end
    end

    it "rejects calls beyond MAX_PER_TURN" do
      described_class::MAX_PER_TURN.times do |i|
        tool.execute(content: "reminder #{i}", due_at: (Time.now + 3600 + i).iso8601)
      end

      result = tool.execute(content: "one too many", due_at: future_time)
      expect(result).to include("Rate limit")
    end

    it "resets after reset_turn_count!" do
      described_class::MAX_PER_TURN.times do |i|
        tool.execute(content: "reminder #{i}", due_at: (Time.now + 3600 + i).iso8601)
      end

      tool.reset_turn_count!

      result = tool.execute(content: "after reset", due_at: future_time)
      expect(result).to include("Reminder set")
    end
  end
end
