# frozen_string_literal: true

RSpec.describe Kodo::Memory::Store, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:store) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "conversations"))
    described_class.new
  end

  describe "#append" do
    it "adds a message to a conversation" do
      store.append("chat1", role: "user", content: "hello")

      history = store.conversation("chat1")
      expect(history.length).to eq(1)
      expect(history.first[:role]).to eq("user")
      expect(history.first[:content]).to eq("hello")
    end

    it "persists messages to disk" do
      store.append("chat1", role: "user", content: "hello")

      # Create a new store instance to verify persistence
      new_store = described_class.new
      history = new_store.conversation("chat1")
      expect(history.length).to eq(1)
      expect(history.first[:content]).to eq("hello")
    end

    it "trims to MAX_CONTEXT_MESSAGES" do
      (described_class::MAX_CONTEXT_MESSAGES + 10).times do |i|
        store.append("chat1", role: "user", content: "message #{i}")
      end

      history = store.conversation("chat1")
      expect(history.length).to eq(described_class::MAX_CONTEXT_MESSAGES)
      expect(history.last[:content]).to eq("message #{described_class::MAX_CONTEXT_MESSAGES + 9}")
    end

    it "converts chat_id to string" do
      store.append(123, role: "user", content: "numeric id")

      history = store.conversation(123)
      expect(history.length).to eq(1)
    end
  end

  describe "#conversation" do
    it "returns empty array for unknown chat" do
      expect(store.conversation("nonexistent")).to eq([])
    end

    it "returns messages in LLM-ready format" do
      store.append("chat1", role: "user", content: "hello")
      store.append("chat1", role: "assistant", content: "hi there")

      history = store.conversation("chat1")
      expect(history).to eq([
        { role: "user", content: "hello" },
        { role: "assistant", content: "hi there" }
      ])
    end
  end

  describe "#clear" do
    it "removes conversation from memory and disk" do
      store.append("chat1", role: "user", content: "hello")
      store.clear("chat1")

      expect(store.conversation("chat1")).to eq([])

      # Verify file is deleted
      new_store = described_class.new
      expect(new_store.conversation("chat1")).to eq([])
    end
  end

  describe "corrupt file handling" do
    it "returns empty array for corrupt JSON" do
      conv_dir = File.join(tmpdir, "memory", "conversations")
      FileUtils.mkdir_p(conv_dir)
      File.write(File.join(conv_dir, "corrupt.json"), "not json{{{")

      expect(store.conversation("corrupt")).to eq([])
    end
  end

  describe "filesystem safety" do
    it "sanitizes chat_id for filenames" do
      store.append("../../../etc/passwd", role: "user", content: "sneaky")

      # Should not create files outside the conversations directory
      expect(File.exist?("/etc/passwd.json")).to be false

      history = store.conversation("../../../etc/passwd")
      expect(history.length).to eq(1)
    end
  end
end
