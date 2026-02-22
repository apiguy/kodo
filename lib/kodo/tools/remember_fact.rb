# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module Tools
    class RememberFact < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Knowledge'
      capability_primary true
      enabled_guidance 'Remember, recall, update, and forget facts about the user across sessions.'

      MAX_PER_TURN = 5
      MAX_CONTENT_LENGTH = 500

      description 'Remember a fact about the user for future conversations. ' \
                  'Use this when the user shares preferences, personal info, or instructions ' \
                  "they'd want you to remember across sessions."

      param :category, desc: 'One of: preference, fact, instruction, context'
      param :content, desc: 'The fact to remember (max 500 chars)'
      param :source, desc: 'How you learned this: explicit (user told you) or inference (you deduced it)',
                     required: false

      attr_writer :turn_context

      def initialize(knowledge:, audit:)
        super()
        @knowledge = knowledge
        @audit = audit
        @turn_count = 0
        @turn_context = nil
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(category:, content:, source: 'explicit')
        # Mechanical web-fetched gate: set by FetchUrl/WebSearch tools, not by LLM parameters.
        # Protects against memory poisoning from injected instructions in web content.
        if @turn_context&.web_fetched
          return 'Web content was fetched this turn. To prevent memory poisoning, ' \
                 "I won't store facts automatically. If you explicitly want me to " \
                 "remember: \"#{content}\", say so and I'll do it."
        end

        unless Memory::Knowledge::VALID_CATEGORIES.include?(category)
          return "Invalid category '#{category}'. Use: #{Memory::Knowledge::VALID_CATEGORIES.join(', ')}"
        end

        if content.length > MAX_CONTENT_LENGTH
          return "Content too long (#{content.length} chars). Maximum is #{MAX_CONTENT_LENGTH}."
        end

        if Memory::Redactor.sensitive?(content)
          return 'Cannot store sensitive data (passwords, API keys, SSNs, credit card numbers).'
        end

        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} facts per message). Try again next message."
        end

        fact = @knowledge.remember(category: category, content: content, source: source)

        @audit.log(
          event: 'knowledge_remembered',
          detail: "id:#{fact['id']} cat:#{category} src:#{source}"
        )

        "Remembered: #{content} (id: #{fact['id']})"
      rescue Kodo::Error => e
        e.message
      end

      def name
        'remember'
      end
    end
  end
end
