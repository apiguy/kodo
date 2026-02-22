# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class ForgetFact < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Knowledge'

      description "Forget a previously remembered fact. Use this when the user asks you " \
                  "to forget something or when information is outdated."

      param :id, desc: "The UUID of the fact to forget"

      def initialize(knowledge:, audit:)
        super()
        @knowledge = knowledge
        @audit = audit
      end

      def execute(id:)
        fact = @knowledge.forget(id)

        if fact
          @audit.log(
            event: "knowledge_forgotten",
            detail: "id:#{id} content:#{fact['content']&.slice(0, 80)}"
          )
          "Forgot fact: #{fact['content']}"
        else
          "No active fact found with id: #{id}"
        end
      end

      def name
        "forget"
      end
    end
  end
end
