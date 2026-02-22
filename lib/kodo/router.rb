# frozen_string_literal: true

module Kodo
  class Router
    TOOL_CLASSES = [
      Tools::GetCurrentTime,
      Tools::RememberFact,
      Tools::ForgetFact,
      Tools::RecallFacts,
      Tools::UpdateFact,
      Tools::SetReminder,
      Tools::ListReminders,
      Tools::DismissReminder,
      Tools::WebSearch,
      Tools::FetchUrl,
      Tools::StoreSecret
    ].freeze

    def initialize(memory:, audit:, prompt_assembler: nil, knowledge: nil, reminders: nil,
                   search_provider: nil, broker: nil, on_secret_stored: nil)
      @memory = memory
      @audit = audit
      @prompt_assembler = prompt_assembler || PromptAssembler.new
      @knowledge = knowledge
      @reminders = reminders
      @search_provider = search_provider
      @broker = broker
      @on_secret_stored = on_secret_stored
      @tools = build_tools
    end

    # Rebuild the tool list (e.g. after a new secret activates a provider)
    def reload_tools!(search_provider: nil)
      @search_provider = search_provider if search_provider
      @tools = build_tools
    end

    # Process an incoming message and return a response message
    def route(message, channel:)
      chat_id = message.metadata[:chat_id] || message.metadata['chat_id']

      # Fresh per-turn context: nonce for content isolation, web_fetched flag
      turn_context = Web::TurnContext.new
      set_turn_context(turn_context)

      # Set channel context on SetReminder so it knows where to deliver
      set_reminder_context(channel.channel_id, chat_id)

      # Store the user's message
      @memory.append(chat_id, role: 'user', content: message.content)

      @audit.log(
        event: 'message_received',
        channel: message.channel_id,
        detail: "from:#{message.metadata[:sender_name] || 'user'} len:#{message.content.length}"
      )

      # Assemble the system prompt from layered files
      knowledge_text = @knowledge&.for_prompt
      system_prompt = @prompt_assembler.assemble(
        runtime_context: {
          model: Kodo.config.llm_model,
          channels: channel.channel_id,
          web_nonce: turn_context.nonce
        },
        knowledge: knowledge_text,
        capabilities: build_capabilities_from_tools
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

      @memory.append(chat_id, role: 'assistant', content: response_text)

      @audit.log(
        event: 'message_sent',
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

      # URL fetching (no API key required)
      tools << Tools::FetchUrl.new(audit: @audit) if Kodo.config.web_fetch_url_enabled?

      # Web search (requires search provider API key)
      if @search_provider && Kodo.config.web_search_enabled?
        tools << Tools::WebSearch.new(search_provider: @search_provider, audit: @audit)
      end

      # Secret storage tool (requires broker)
      tools << Tools::StoreSecret.new(broker: @broker, audit: @audit, on_secret_stored: @on_secret_stored) if @broker

      tools
    end

    def reset_tool_rate_limits!
      @tools.each do |tool|
        tool.reset_turn_count! if tool.respond_to?(:reset_turn_count!)
      end
    end

    def build_capabilities_from_tools # rubocop:disable Metrics
      active_tool_classes = @tools.map(&:class)
      active_capability_names = active_tool_classes
                                .select { |klass| klass.respond_to?(:capability_name) && klass.capability_name }
                                .map(&:capability_name)
                                .uniq
      secret_storage_active = active_capability_names.include?('Secret Storage')

      caps = {}
      TOOL_CLASSES.each do |klass|
        next unless klass.respond_to?(:capability_name) && klass.capability_name
        next unless klass.respond_to?(:capability_primary) && klass.capability_primary

        name = klass.capability_name
        next if caps.key?(name)

        enabled = active_capability_names.include?(name)
        guidance = if enabled
                     klass.enabled_guidance
                   elsif name == 'Web Search' && secret_storage_active
                     Tools::WebSearch::DISABLED_GUIDANCE_WITH_SECRET_STORAGE
                   else
                     klass.disabled_guidance
                   end

        caps[name] = { status: enabled ? :enabled : :disabled, guidance: guidance }
      end

      caps
    end

    def set_reminder_context(channel_id, chat_id)
      @tools.each do |tool|
        if tool.is_a?(Tools::SetReminder)
          tool.channel_id = channel_id
          tool.chat_id = chat_id
        end
      end
    end

    def set_turn_context(turn_context)
      @tools.each do |tool|
        tool.turn_context = turn_context if tool.respond_to?(:turn_context=)
      end
    end
  end
end
