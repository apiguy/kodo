# frozen_string_literal: true

RSpec.describe Kodo::Tools::GetCurrentTime, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end
  let(:tool) { described_class.new(audit: audit) }

  describe "#name" do
    it "returns 'get_current_time'" do
      expect(tool.name).to eq("get_current_time")
    end
  end

  describe "#execute" do
    it "returns a string with day of week, date, and time" do
      result = tool.execute

      expect(result).to match(/\A\w+day, \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end

    it "includes time period" do
      result = tool.execute

      expect(result).to match(/\((morning|afternoon|evening|night)\)\z/)
    end

    it "logs to audit trail" do
      tool.execute

      events = audit.today
      expect(events.any? { |e| e["event"] == "tool_get_current_time" }).to be true
    end
  end
end
