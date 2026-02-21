# frozen_string_literal: true

require "time"

RSpec.describe Kodo::Tools::DismissReminder, :tmpdir do
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
  let(:tool) { described_class.new(reminders: reminders, audit: audit) }

  describe "#name" do
    it "returns 'dismiss_reminder'" do
      expect(tool.name).to eq("dismiss_reminder")
    end
  end

  describe "#execute" do
    it "dismisses a reminder and returns confirmation" do
      r = reminders.add(content: "Test", due_at: (Time.now + 3600).iso8601)
      result = tool.execute(id: r["id"])

      expect(result).to include("Dismissed reminder")
      expect(result).to include("Test")
      expect(reminders.active_count).to eq(0)
    end

    it "returns error for unknown id" do
      result = tool.execute(id: "nonexistent")

      expect(result).to include("No active reminder found")
    end

    it "cannot dismiss an already dismissed reminder" do
      r = reminders.add(content: "Test", due_at: (Time.now + 3600).iso8601)
      tool.execute(id: r["id"])

      result = tool.execute(id: r["id"])
      expect(result).to include("No active reminder found")
    end

    it "logs to audit trail" do
      r = reminders.add(content: "Test", due_at: (Time.now + 3600).iso8601)
      tool.execute(id: r["id"])

      events = audit.today
      expect(events.any? { |e| e["event"] == "reminder_dismissed" }).to be true
    end
  end
end
