# frozen_string_literal: true

module Kodo
  class Router
    def initialize(memory:, audit:, prompt_assembler: nil, knowledge: nil, reminders: nil)
      @memory = memory
      @audit = audit
      @prompt_assembler = prompt_assembler || PromptAssembler.new
      @knowledge = knowledge
      @reminders = reminders
      @tools = build_tools
    end

    # Process an incoming message and return a response message
    def route(message, channel:)
      chat_id = message.metadata[:chat_id] || message.metadata["chat_id"]

      # Set channel context on SetReminder so it knows where to deliver
      set_reminder_context(channel.channel_id, chat_id)

      # Store the user's message
      @memory.append(chat_id, role: "user", content: message.content)

      @audit.log(
        event: "message_received",
        channel: message.channel_id,
        detail: "from:#{message.metadata[:sender_name] || 'user'} len:#{message.content.length}"
      )

      # Assemble the system prompt from layered files
      knowledge_text = @knowledge&.for_prompt
      system_prompt = @prompt_assembler.assemble(
        runtime_context: {
          model: Kodo.config.llm_model,
          channels: channel.channel_id
        },
        knowledge: knowledge_text
      )

      # Build a fresh RubyLLM chat with conversation history
      chat = LLM.chat
      chat.with_instructions(system_prompt)

      # Register tools with the LLM chat
      if @tools.any?
        reset_tool_rate_limits!
        chat.with_tools(*@tools)
      end

      history = @memory.conversation(chat_id)
      prior = history[0...-1] || []
      prior.each do |msg|
        chat.add_message(role: msg[:role], content: msg[:content])
      end

      Kodo.logger.debug("Routing to #{Kodo.config.llm_model} with #{history.length} messages")
      response = chat.ask(message.content)
      response_text = response.content

      @memory.append(chat_id, role: "assistant", content: response_text)

      @audit.log(
        event: "message_sent",
        channel: message.channel_id,
        detail: "len:#{response_text.length}"
      )

      Message.new(
        channel_id: message.channel_id,
        sender: :agent,
        content: response_text,
        metadata: {
          chat_id: chat_id,
          reply_to_message_id: message.metadata[:message_id]
        }
      )
    end

    private

    def build_tools
      tools = []

      # Always available
      tools << Tools::GetCurrentTime.new(audit: @audit)

      # Knowledge tools (require knowledge store)
      if @knowledge
        tools << Tools::RememberFact.new(knowledge: @knowledge, audit: @audit)
        tools << Tools::ForgetFact.new(knowledge: @knowledge, audit: @audit)
        tools << Tools::RecallFacts.new(knowledge: @knowledge, audit: @audit)
        tools << Tools::UpdateFact.new(knowledge: @knowledge, audit: @audit)
      end

      # Reminder tools (require reminders store)
      if @reminders
        tools << Tools::SetReminder.new(reminders: @reminders, audit: @audit)
        tools << Tools::ListReminders.new(reminders: @reminders, audit: @audit)
        tools << Tools::DismissReminder.new(reminders: @reminders, audit: @audit)
      end

      tools
    end

    def reset_tool_rate_limits!
      @tools.each do |tool|
        tool.reset_turn_count! if tool.respond_to?(:reset_turn_count!)
      end
    end

    def set_reminder_context(channel_id, chat_id)
      @tools.each do |tool|
        if tool.is_a?(Tools::SetReminder)
          tool.channel_id = channel_id
          tool.chat_id = chat_id
        end
      end
    end
  end
end
