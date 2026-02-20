# frozen_string_literal: true

RSpec.describe Kodo::Memory::Audit, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    described_class.new
  end

  describe "#log" do
    it "writes an event to the daily log" do
      audit.log(event: "test_event", detail: "something happened")

      entries = audit.today
      expect(entries.length).to eq(1)
      expect(entries.first["event"]).to eq("test_event")
      expect(entries.first["detail"]).to eq("something happened")
    end

    it "includes a timestamp" do
      audit.log(event: "test_event")

      entry = audit.today.first
      expect(entry["timestamp"]).not_to be_nil
      expect { Time.iso8601(entry["timestamp"]) }.not_to raise_error
    end

    it "includes channel when provided" do
      audit.log(event: "msg", channel: "telegram", detail: "test")

      entry = audit.today.first
      expect(entry["channel"]).to eq("telegram")
    end

    it "omits nil fields" do
      audit.log(event: "bare_event")

      entry = audit.today.first
      expect(entry).not_to have_key("channel")
      expect(entry).not_to have_key("detail")
    end

    it "appends multiple events" do
      audit.log(event: "first")
      audit.log(event: "second")
      audit.log(event: "third")

      expect(audit.today.length).to eq(3)
      expect(audit.today.map { |e| e["event"] }).to eq(%w[first second third])
    end
  end

  describe "#today" do
    it "returns empty array when no log exists" do
      expect(audit.today).to eq([])
    end
  end

  describe "JSONL format" do
    it "writes one JSON object per line" do
      audit.log(event: "a")
      audit.log(event: "b")

      log_dir = File.join(tmpdir, "memory", "audit")
      log_file = Dir.glob(File.join(log_dir, "*.jsonl")).first
      lines = File.readlines(log_file)

      expect(lines.length).to eq(2)
      lines.each do |line|
        expect { JSON.parse(line) }.not_to raise_error
      end
    end
  end

  describe "daily file creation" do
    it "names the file with today's date" do
      audit.log(event: "test")

      log_dir = File.join(tmpdir, "memory", "audit")
      expected_file = File.join(log_dir, "#{Date.today.iso8601}.jsonl")
      expect(File.exist?(expected_file)).to be true
    end
  end
end
