# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module LLM
    class << self
      # Configure RubyLLM from Kodo's config
      def configure!(config)
        RubyLLM.configure do |c|
          config.llm_api_keys.each do |provider, key|
            setter = "#{provider}_api_key="
            c.send(setter, key) if c.respond_to?(setter)
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
    end
  end
end
