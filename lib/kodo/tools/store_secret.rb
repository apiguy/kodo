# frozen_string_literal: true

require 'ruby_llm'
require 'net/http'
require 'uri'
require 'json'

module Kodo
  module Tools
    class StoreSecret < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Secret Storage'
      capability_primary true
      enabled_guidance 'Use store_secret to store and activate API keys securely — no restart required.'

      MAX_PER_TURN = 2
      VALIDATION_TIMEOUT = 5

      KNOWN_SECRETS = {
        'anthropic_api_key' => { description: 'Anthropic API key', prefix: 'sk-ant-' },
        'openai_api_key' => { description: 'OpenAI API key', prefix: 'sk-' },
        'gemini_api_key' => { description: 'Google Gemini API key' },
        'deepseek_api_key' => { description: 'DeepSeek API key' },
        'mistral_api_key' => { description: 'Mistral API key' },
        'openrouter_api_key' => { description: 'OpenRouter API key', prefix: 'sk-or-' },
        'perplexity_api_key' => { description: 'Perplexity API key' },
        'xai_api_key' => { description: 'xAI API key' },
        'tavily_api_key' => { description: 'Tavily API key', prefix: 'tvly-' },
        'telegram_bot_token' => { description: 'Telegram bot token' }
      }.freeze

      description 'Securely store an API key or token. Use this when the user provides ' \
                  'a key they want to configure. The key is encrypted at rest and ' \
                  'activated immediately without requiring a restart.'

      param :secret_name, desc: "The secret identifier. One of: #{KNOWN_SECRETS.keys.join(', ')}"
      param :secret_value, desc: 'The secret value (API key or token)'

      def initialize(broker:, audit:, on_secret_stored: nil)
        super()
        @broker = broker
        @audit = audit
        @on_secret_stored = on_secret_stored
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(secret_name:, secret_value:) # rubocop:disable Metrics/MethodLength
        unless KNOWN_SECRETS.key?(secret_name)
          return "Unknown secret '#{secret_name}'. Known secrets: #{KNOWN_SECRETS.keys.join(', ')}"
        end

        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} secrets per message). Try again next message."
        end

        prefix_error = validate_prefix(secret_name, secret_value)
        return prefix_error if prefix_error

        validated = validate_key(secret_name, secret_value)

        @broker.store(secret_name, secret_value, source: 'chat', validated: validated)

        @audit.log(
          event: 'secret_stored_via_tool',
          detail: "secret:#{secret_name} validated:#{validated}"
        )

        @on_secret_stored&.call(secret_name)

        desc = KNOWN_SECRETS[secret_name][:description]
        if validated
          "#{desc} stored and validated successfully. It's now active — no restart needed."
        else
          "#{desc} stored and activated. Couldn't verify it online, but it's ready to use."
        end
      rescue Kodo::Error => e
        e.message
      end

      def name
        'store_secret'
      end

      private

      def validate_prefix(secret_name, value)
        expected = KNOWN_SECRETS.dig(secret_name, :prefix)
        return nil unless expected

        return nil if value.start_with?(expected)

        "Invalid #{KNOWN_SECRETS[secret_name][:description]}: expected to start with '#{expected}'"
      end

      def validate_key(secret_name, value)
        case secret_name
        when 'tavily_api_key' then validate_tavily(value)
        when 'anthropic_api_key' then validate_anthropic(value)
        else false
        end
      rescue StandardError
        false
      end

      def validate_tavily(key)
        uri = URI('https://api.tavily.com/search')
        body = { api_key: key, query: 'test', max_results: 1 }.to_json
        response = http_post(uri, body, 'application/json')
        response.is_a?(Net::HTTPSuccess)
      end

      def validate_anthropic(key)
        uri = URI('https://api.anthropic.com/v1/messages')
        body = {
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 1,
          messages: [{ role: 'user', content: 'hi' }]
        }.to_json
        response = http_post(uri, body, 'application/json',
                             'x-api-key' => key,
                             'anthropic-version' => '2023-06-01')
        response.is_a?(Net::HTTPSuccess)
      end

      def http_post(uri, body, content_type, extra_headers = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = VALIDATION_TIMEOUT
        http.read_timeout = VALIDATION_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = content_type
        extra_headers.each { |k, v| request[k] = v }
        request.body = body

        http.request(request)
      end
    end
  end
end
