# frozen_string_literal: true

require "time"

RSpec.describe Kodo::Memory::Reminders, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:reminders) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "reminders"))
    described_class.new
  end

  describe "#add" do
    it "creates a reminder and returns it" do
      due = (Time.now + 300).iso8601
      reminder = reminders.add(content: "Stretch!", due_at: due, channel_id: "console", chat_id: "chat1")

      expect(reminder["id"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(reminder["content"]).to eq("Stretch!")
      expect(reminder["due_at"]).to eq(due)
      expect(reminder["channel_id"]).to eq("console")
      expect(reminder["chat_id"]).to eq("chat1")
      expect(reminder["status"]).to eq("active")
    end

    it "persists to disk" do
      reminders.add(content: "Test", due_at: (Time.now + 300).iso8601)

      path = File.join(tmpdir, "memory", "reminders", "reminders.jsonl")
      expect(File.exist?(path)).to be true

      lines = File.readlines(path).reject(&:empty?)
      expect(lines.length).to eq(1)
    end

    it "accepts Time objects for due_at" do
      due_time = Time.now + 600
      reminder = reminders.add(content: "Test", due_at: due_time)

      expect(reminder["due_at"]).to eq(due_time.iso8601)
    end

    it "enforces MAX_ACTIVE limit" do
      stub_const("Kodo::Memory::Reminders::MAX_ACTIVE", 3)

      3.times { |i| reminders.add(content: "r#{i}", due_at: (Time.now + 300).iso8601) }

      expect {
        reminders.add(content: "overflow", due_at: (Time.now + 300).iso8601)
      }.to raise_error(Kodo::Error, /Too many/)
    end
  end

  describe "#dismiss" do
    it "marks a reminder as dismissed" do
      r = reminders.add(content: "Test", due_at: (Time.now + 300).iso8601)
      result = reminders.dismiss(r["id"])

      expect(result["status"]).to eq("dismissed")
      expect(reminders.active_count).to eq(0)
    end

    it "returns nil for unknown id" do
      expect(reminders.dismiss("nonexistent")).to be_nil
    end

    it "cannot dismiss an already dismissed reminder" do
      r = reminders.add(content: "Test", due_at: (Time.now + 300).iso8601)
      reminders.dismiss(r["id"])

      expect(reminders.dismiss(r["id"])).to be_nil
    end
  end

  describe "#fire!" do
    it "marks a reminder as fired" do
      r = reminders.add(content: "Test", due_at: (Time.now + 300).iso8601)
      result = reminders.fire!(r["id"])

      expect(result["status"]).to eq("fired")
      expect(reminders.active_count).to eq(0)
    end

    it "returns nil for unknown id" do
      expect(reminders.fire!("nonexistent")).to be_nil
    end
  end

  describe "#due_reminders" do
    it "returns active reminders past due" do
      reminders.add(content: "Past due", due_at: (Time.now - 60).iso8601)
      reminders.add(content: "Not yet", due_at: (Time.now + 3600).iso8601)

      due = reminders.due_reminders
      expect(due.length).to eq(1)
      expect(due.first["content"]).to eq("Past due")
    end

    it "does not include dismissed reminders" do
      r = reminders.add(content: "Dismissed", due_at: (Time.now - 60).iso8601)
      reminders.dismiss(r["id"])

      expect(reminders.due_reminders).to be_empty
    end

    it "does not include fired reminders" do
      r = reminders.add(content: "Fired", due_at: (Time.now - 60).iso8601)
      reminders.fire!(r["id"])

      expect(reminders.due_reminders).to be_empty
    end
  end

  describe "#all_active" do
    it "returns only active reminders" do
      reminders.add(content: "Active", due_at: (Time.now + 300).iso8601)
      r2 = reminders.add(content: "Dismissed", due_at: (Time.now + 300).iso8601)
      reminders.dismiss(r2["id"])

      active = reminders.all_active
      expect(active.length).to eq(1)
      expect(active.first["content"]).to eq("Active")
    end
  end

  describe "persistence" do
    it "loads reminders from disk on initialization" do
      reminders.add(content: "Persisted", due_at: (Time.now + 300).iso8601)

      new_reminders = described_class.new
      expect(new_reminders.active_count).to eq(1)
      expect(new_reminders.all_active.first["content"]).to eq("Persisted")
    end
  end

  describe "encrypted persistence" do
    let(:passphrase) { "test-secret" }
    let(:encrypted_reminders) do
      allow(Kodo).to receive(:home_dir).and_return(tmpdir)
      FileUtils.mkdir_p(File.join(tmpdir, "memory", "reminders"))
      described_class.new(passphrase: passphrase)
    end

    it "encrypts data on disk" do
      encrypted_reminders.add(content: "Secret reminder", due_at: (Time.now + 300).iso8601)

      path = File.join(tmpdir, "memory", "reminders", "reminders.jsonl")
      raw = File.binread(path)
      expect(Kodo::Memory::Encryption.encrypted?(raw)).to be true
      expect(raw).not_to include("Secret reminder")
    end

    it "decrypts on reload" do
      encrypted_reminders.add(content: "Secret reminder", due_at: (Time.now + 300).iso8601)

      reloaded = described_class.new(passphrase: passphrase)
      expect(reloaded.active_count).to eq(1)
      expect(reloaded.all_active.first["content"]).to eq("Secret reminder")
    end
  end
end
