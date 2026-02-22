# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module Tools
    class WebSearch < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Web Search'
      capability_primary true
      enabled_guidance 'Search the web for current information.'
      disabled_guidance \
        "Tavily is the easiest option (free tier, 1000 searches/month, no credit card).\n" \
        "Get an API key from https://app.tavily.com/sign-in\n" \
        "Set the environment variable: export TAVILY_API_KEY=\"tvly-...\"\n" \
        "Add to ~/.kodo/config.yml: search: { provider: tavily }\n" \
        "Then restart Kodo.\n\n" \
        "IMPORTANT: If the user pastes an API key into chat, remind them that credentials " \
        "should be set as environment variables, not shared in conversation. The key will " \
        "be redacted from conversation history for security."

      DISABLED_GUIDANCE_WITH_SECRET_STORAGE =
        "Tavily is the easiest option (free tier, 1000 searches/month, no credit card).\n" \
        "Get an API key from https://app.tavily.com/sign-in\n" \
        "They can paste the key right here in chat and you will store it securely."

      MAX_PER_TURN = 3

      description 'Search the web for current information. Use this when the user asks about ' \
                  "recent events, needs up-to-date facts, or wants information you don't have."

      param :query, desc: 'The search query'
      param :max_results, desc: 'Number of results to return (1-10, default 5)', required: false

      def initialize(search_provider:, audit:)
        super()
        @search_provider = search_provider
        @audit = audit
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(query:, max_results: '5')
        max_results = max_results.to_i.clamp(1, 10)

        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} searches per message). Try again next message."
        end

        results = @search_provider.search(query, max_results: max_results)

        @audit.log(
          event: 'web_search',
          detail: "query:#{query} results:#{results.length}"
        )

        return "No results found for: #{query}" if results.empty?

        format_results(results)
      rescue Kodo::Error => e
        e.message
      end

      def name
        'web_search'
      end

      private

      def format_results(results)
        results.each_with_index.map do |r, i|
          "#{i + 1}. #{r.title}\n   #{r.url}\n   #{r.snippet}"
        end.join("\n\n")
      end
    end
  end
end
