# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class UpdateFact < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Knowledge'

      MAX_PER_TURN = 5
      MAX_CONTENT_LENGTH = 500

      description "Update an existing fact with new content. Use this instead of forget+remember " \
                  "when a fact needs correction or updating."

      param :id, desc: "The UUID of the fact to update"
      param :content, desc: "The new content for the fact (max 500 chars)"

      def initialize(knowledge:, audit:)
        super()
        @knowledge = knowledge
        @audit = audit
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(id:, content:)
        if content.length > MAX_CONTENT_LENGTH
          return "Content too long (#{content.length} chars). Maximum is #{MAX_CONTENT_LENGTH}."
        end

        if Memory::Redactor.sensitive?(content)
          return "Cannot store sensitive data (passwords, API keys, SSNs, credit card numbers)."
        end

        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} updates per message). Try again next message."
        end

        old_fact = @knowledge.all_active.find { |f| f["id"] == id }
        unless old_fact
          return "No active fact found with id: #{id}"
        end

        @knowledge.forget(id)
        new_fact = @knowledge.remember(
          category: old_fact["category"],
          content: content,
          source: old_fact["source"]
        )

        @audit.log(
          event: "knowledge_updated",
          detail: "old:#{id} new:#{new_fact['id']} cat:#{old_fact['category']}"
        )

        "Updated fact: #{content} (new id: #{new_fact['id']}, replaces: #{id})"
      rescue Kodo::Error => e
        e.message
      end

      def name
        "update_fact"
      end
    end
  end
end
