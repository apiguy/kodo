# frozen_string_literal: true

RSpec.describe Kodo::Router, :tmpdir do
  let(:tmpdir) { @tmpdir }

  let(:memory) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "conversations"))
    Kodo::Memory::Store.new
  end

  let(:audit) do
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "audit"))
    Kodo::Memory::Audit.new
  end

  let(:knowledge) do
    FileUtils.mkdir_p(File.join(tmpdir, "memory", "knowledge"))
    Kodo::Memory::Knowledge.new
  end

  let(:assembler) { Kodo::PromptAssembler.new(home_dir: tmpdir) }
  let(:router) { described_class.new(memory: memory, audit: audit, prompt_assembler: assembler, knowledge: knowledge) }

  let(:channel) do
    instance_double(Kodo::Channels::Console, channel_id: "console")
  end

  let(:incoming_message) do
    Kodo::Message.new(
      channel_id: "console",
      sender: :user,
      content: "What is Ruby?",
      metadata: { chat_id: "test-chat" }
    )
  end

  # Stub the LLM to avoid real API calls
  let(:mock_response) { double("Response", content: "Ruby is a programming language.") }
  let(:mock_chat) do
    instance_double(RubyLLM::Chat).tap do |chat|
      allow(chat).to receive(:with_instructions)
      allow(chat).to receive(:with_tools).and_return(chat)
      allow(chat).to receive(:add_message)
      allow(chat).to receive(:ask).and_return(mock_response)
    end
  end

  before do
    allow(Kodo::LLM).to receive(:chat).and_return(mock_chat)
    allow(Kodo).to receive(:config).and_return(
      Kodo::Config.new(Kodo::Config::DEFAULTS)
    )
  end

  describe "#route" do
    it "returns a response message" do
      response = router.route(incoming_message, channel: channel)

      expect(response).to be_a(Kodo::Message)
      expect(response.sender).to eq(:agent)
      expect(response.content).to eq("Ruby is a programming language.")
      expect(response.channel_id).to eq("console")
    end

    it "stores user message in memory" do
      router.route(incoming_message, channel: channel)

      history = memory.conversation("test-chat")
      expect(history.first[:role]).to eq("user")
      expect(history.first[:content]).to eq("What is Ruby?")
    end

    it "stores assistant response in memory" do
      router.route(incoming_message, channel: channel)

      history = memory.conversation("test-chat")
      expect(history.last[:role]).to eq("assistant")
      expect(history.last[:content]).to eq("Ruby is a programming language.")
    end

    it "logs message_received and message_sent audit events" do
      router.route(incoming_message, channel: channel)

      events = audit.today.map { |e| e["event"] }
      expect(events).to include("message_received")
      expect(events).to include("message_sent")
    end

    it "passes conversation history to the LLM" do
      # Pre-populate history
      memory.append("test-chat", role: "user", content: "previous question")
      memory.append("test-chat", role: "assistant", content: "previous answer")

      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:add_message).with(role: "user", content: "previous question")
      expect(mock_chat).to have_received(:add_message).with(role: "assistant", content: "previous answer")
    end

    it "sets reply_to_message_id in response metadata" do
      msg = Kodo::Message.new(
        channel_id: "console",
        sender: :user,
        content: "test",
        metadata: { chat_id: "test-chat", message_id: 42 }
      )

      response = router.route(msg, channel: channel)
      expect(response.metadata[:reply_to_message_id]).to eq(42)
    end

    it "assembles a system prompt with runtime context" do
      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:with_instructions).with(
        a_string_including("Security Invariants")
      )
    end

    it "registers tools with the chat" do
      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:with_tools).with(
        an_instance_of(Kodo::Tools::GetCurrentTime),
        an_instance_of(Kodo::Tools::RememberFact),
        an_instance_of(Kodo::Tools::ForgetFact),
        an_instance_of(Kodo::Tools::RecallFacts),
        an_instance_of(Kodo::Tools::UpdateFact)
      )
    end

    it "passes knowledge to the prompt assembler" do
      knowledge.remember(category: "fact", content: "Likes Ruby")

      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:with_instructions).with(
        a_string_including("Likes Ruby")
      )
    end
  end

  describe "without knowledge store" do
    let(:router) { described_class.new(memory: memory, audit: audit, prompt_assembler: assembler) }

    it "works without knowledge (backwards compatible)" do
      response = router.route(incoming_message, channel: channel)
      expect(response.content).to eq("Ruby is a programming language.")
    end

    it "registers only GetCurrentTime tool" do
      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:with_tools).with(
        an_instance_of(Kodo::Tools::GetCurrentTime)
      )
    end
  end

  describe "with reminders store" do
    let(:reminders) do
      FileUtils.mkdir_p(File.join(tmpdir, "memory", "reminders"))
      Kodo::Memory::Reminders.new
    end
    let(:router) do
      described_class.new(
        memory: memory, audit: audit, prompt_assembler: assembler,
        knowledge: knowledge, reminders: reminders
      )
    end

    it "registers reminder tools with the chat" do
      router.route(incoming_message, channel: channel)

      expect(mock_chat).to have_received(:with_tools).with(
        an_instance_of(Kodo::Tools::GetCurrentTime),
        an_instance_of(Kodo::Tools::RememberFact),
        an_instance_of(Kodo::Tools::ForgetFact),
        an_instance_of(Kodo::Tools::RecallFacts),
        an_instance_of(Kodo::Tools::UpdateFact),
        an_instance_of(Kodo::Tools::SetReminder),
        an_instance_of(Kodo::Tools::ListReminders),
        an_instance_of(Kodo::Tools::DismissReminder)
      )
    end
  end
end
