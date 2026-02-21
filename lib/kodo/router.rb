# frozen_string_literal: true

module Kodo
  class Router
    def initialize(memory:, audit:, prompt_assembler: nil, knowledge: nil)
      @memory = memory
      @audit = audit
      @prompt_assembler = prompt_assembler || PromptAssembler.new
      @knowledge = knowledge
      @tools = build_tools
    end

    # Process an incoming message and return a response message
    def route(message, channel:)
      chat_id = message.metadata[:chat_id] || message.metadata["chat_id"]

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

      # Register tools if knowledge store is available
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
      return [] unless @knowledge

      [
        Tools::RememberFact.new(knowledge: @knowledge, audit: @audit),
        Tools::ForgetFact.new(knowledge: @knowledge, audit: @audit)
      ]
    end

    def reset_tool_rate_limits!
      @tools.each do |tool|
        tool.reset_turn_count! if tool.respond_to?(:reset_turn_count!)
      end
    end
  end
end
