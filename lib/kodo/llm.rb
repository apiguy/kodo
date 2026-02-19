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

        Kodo.logger.info("LLM configured: #{config.llm_model}")
      end

      # Create a new chat instance with the configured model
      def chat(model: nil)
        RubyLLM.chat(model: model || Kodo.config.llm_model)
      end
    end
  end
end
