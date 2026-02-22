# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module LLM
    class << self
      # Map of canonical secret names to RubyLLM config setter names
      PROVIDER_SECRETS = {
        'anthropic_api_key' => 'anthropic',
        'openai_api_key' => 'openai',
        'gemini_api_key' => 'gemini',
        'deepseek_api_key' => 'deepseek',
        'mistral_api_key' => 'mistral',
        'openrouter_api_key' => 'openrouter',
        'perplexity_api_key' => 'perplexity',
        'xai_api_key' => 'xai'
      }.freeze

      # Configure RubyLLM from Kodo's config, optionally resolving keys via broker
      def configure!(config, broker: nil)
        RubyLLM.configure do |c|
          if broker
            configure_via_broker(c, broker)
          else
            config.llm_api_keys.each do |provider, key|
              setter = "#{provider}_api_key="
              c.send(setter, key) if c.respond_to?(setter)
            end
          end

          if (ollama_url = config.ollama_api_base)
            c.ollama_api_base = ollama_url
          end
        end

        # Refresh model registry so newly released models are recognized
        RubyLLM.models.refresh!

        Kodo.logger.info("LLM configured: #{config.llm_model}")
      end

      # Create a new chat instance with the configured model
      def chat(model: nil)
        RubyLLM.chat(model: model || Kodo.config.llm_model)
      end

      # Create a chat instance with the utility model (for lightweight tasks like redaction)
      def utility_chat(model: nil)
        RubyLLM.chat(model: model || Kodo.config.utility_model)
      end

      private

      def configure_via_broker(ruby_llm_config, broker)
        PROVIDER_SECRETS.each do |secret_name, provider|
          key = broker.fetch(secret_name, requestor: 'llm')
          next unless key

          setter = "#{provider}_api_key="
          ruby_llm_config.send(setter, key) if ruby_llm_config.respond_to?(setter)
        end
      end
    end
  end
end
