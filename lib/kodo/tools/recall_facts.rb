# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class RecallFacts < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Knowledge'

      description "Search your knowledge store for facts about the user. " \
                  "Use this when you need to look up specific information, especially " \
                  "if the knowledge was truncated in your system prompt."

      param :query, desc: "Keyword to search for in fact content (case-insensitive)", required: false
      param :category, desc: "Filter by category: preference, fact, instruction, or context", required: false

      def initialize(knowledge:, audit:)
        super()
        @knowledge = knowledge
        @audit = audit
      end

      def execute(query: nil, category: nil)
        if category && !Memory::Knowledge::VALID_CATEGORIES.include?(category)
          return "Invalid category '#{category}'. Use: #{Memory::Knowledge::VALID_CATEGORIES.join(', ')}"
        end

        results = @knowledge.recall(query: query, category: category)

        @audit.log(
          event: "tool_recall_facts",
          detail: "query:#{query || '*'} cat:#{category || '*'} results:#{results.length}"
        )

        if results.empty?
          "No facts found#{" matching '#{query}'" if query}#{" in category '#{category}'" if category}."
        else
          lines = results.map { |f| "- [#{f['category']}] #{f['content']} (id: #{f['id']})" }
          "Found #{results.length} fact(s):\n#{lines.join("\n")}"
        end
      end

      def name
        "recall_facts"
      end
    end
  end
end
