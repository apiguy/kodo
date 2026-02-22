# frozen_string_literal: true

module Kodo
  module Secrets
    class Broker
      GRANTS = [
        Grant.new(secret_name: 'anthropic_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'openai_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'gemini_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'deepseek_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'mistral_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'openrouter_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'perplexity_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'xai_api_key', requestor: 'llm'),
        Grant.new(secret_name: 'tavily_api_key', requestor: 'search'),
        Grant.new(secret_name: 'telegram_bot_token', requestor: 'telegram')
      ].freeze

      ENV_FALLBACKS = {
        'anthropic_api_key' => 'ANTHROPIC_API_KEY',
        'openai_api_key' => 'OPENAI_API_KEY',
        'gemini_api_key' => 'GEMINI_API_KEY',
        'deepseek_api_key' => 'DEEPSEEK_API_KEY',
        'mistral_api_key' => 'MISTRAL_API_KEY',
        'openrouter_api_key' => 'OPENROUTER_API_KEY',
        'perplexity_api_key' => 'PERPLEXITY_API_KEY',
        'xai_api_key' => 'XAI_API_KEY',
        'tavily_api_key' => 'TAVILY_API_KEY',
        'telegram_bot_token' => 'TELEGRAM_BOT_TOKEN'
      }.freeze

      def initialize(store:, audit:)
        @store = store
        @audit = audit
      end

      def fetch(name, requestor:)
        unless authorized?(name, requestor)
          @audit.log(
            event: 'secret_access_denied',
            detail: "secret:#{name} requestor:#{requestor}"
          )
          return nil
        end

        value = @store.get(name)
        return value if value

        env_var = ENV_FALLBACKS[name]
        env_value = ENV[env_var] if env_var
        return env_value if env_value && !env_value.empty?

        nil
      end

      def fetch!(name, requestor:)
        value = fetch(name, requestor: requestor)
        raise Kodo::Error, "Secret not available: #{name}" unless value

        value
      end

      def store(name, value, source: 'user', validated: false)
        @store.put(name, value, source: source, validated: validated)
        @audit.log(
          event: 'secret_stored',
          detail: "secret:#{name} source:#{source} validated:#{validated}"
        )
      end

      def available?(name)
        return true if @store.exists?(name)

        env_var = ENV_FALLBACKS[name]
        return false unless env_var

        value = ENV[env_var]
        !value.nil? && !value.empty?
      end

      def configured_secrets
        all_names = GRANTS.map(&:secret_name).uniq
        all_names.select { |name| available?(name) }
      end

      # Returns all current secret values (store + env) for exfiltration prevention.
      # This is a security-internal method — not an LLM-accessible action.
      def sensitive_values
        GRANTS.map(&:secret_name).uniq.filter_map do |name|
          value = @store.get(name)
          next value if value

          env_var = ENV_FALLBACKS[name]
          next unless env_var

          v = ENV[env_var]
          v unless v.nil? || v.empty?
        end
      end

      private

      def authorized?(name, requestor)
        GRANTS.any? { |g| g.secret_name == name && g.requestor == requestor }
      end
    end
  end
end
