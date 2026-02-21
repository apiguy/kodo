# frozen_string_literal: true

require "time"

RSpec.describe Kodo::Tools::ListReminders, :tmpdir do
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
    it "returns 'list_reminders'" do
      expect(tool.name).to eq("list_reminders")
    end
  end

  describe "#execute" do
    it "returns message when no reminders exist" do
      result = tool.execute

      expect(result).to include("No active reminders")
    end

    it "lists active reminders sorted by due time" do
      later = (Time.now + 7200).iso8601
      sooner = (Time.now + 3600).iso8601

      reminders.add(content: "Later", due_at: later)
      reminders.add(content: "Sooner", due_at: sooner)

      result = tool.execute

      expect(result).to include("2 active reminder(s)")
      sooner_pos = result.index("Sooner")
      later_pos = result.index("Later")
      expect(sooner_pos).to be < later_pos
    end

    it "does not list dismissed reminders" do
      r = reminders.add(content: "Dismissed", due_at: (Time.now + 3600).iso8601)
      reminders.dismiss(r["id"])

      result = tool.execute
      expect(result).to include("No active reminders")
    end

    it "logs to audit trail" do
      tool.execute

      events = audit.today
      expect(events.any? { |e| e["event"] == "tool_list_reminders" }).to be true
    end
  end
end
