# frozen_string_literal: true

require "yaml"
require "fileutils"

module Kodo
  class Config
    # Map of Kodo config key → RubyLLM config setter name
    PROVIDER_KEY_MAP = {
      "anthropic"  => "anthropic",
      "openai"     => "openai",
      "gemini"     => "gemini",
      "deepseek"   => "deepseek",
      "mistral"    => "mistral",
      "openrouter" => "openrouter",
      "perplexity" => "perplexity",
      "xai"        => "xai"
    }.freeze

    DEFAULTS = {
      "daemon" => {
        "port" => 7377,
        "heartbeat_interval" => 60
      },
      "llm" => {
        "model" => "claude-sonnet-4-6",
        "utility_model" => "claude-haiku-4-5-20251001",
        "providers" => {
          "anthropic" => { "api_key_env" => "ANTHROPIC_API_KEY" }
        }
      },
      "channels" => {
        "telegram" => {
          "enabled" => false,
          "bot_token_env" => "TELEGRAM_BOT_TOKEN"
        }
      },
      "memory" => {
        "encryption" => false,
        "passphrase_env" => "KODO_PASSPHRASE",
        "store" => "file"
      },
      "logging" => {
        "level" => "info",
        "audit" => true
      }
    }.freeze

    attr_reader :data

    def initialize(data)
      @data = data
    end

    class << self
      def load(path = nil)
        path ||= config_path
        user_config = File.exist?(path) ? YAML.safe_load_file(path) : {}
        merged = deep_merge(DEFAULTS, user_config || {})
        new(merged)
      end

      def config_path
        File.join(Kodo.home_dir, "config.yml")
      end

      def ensure_home_dir!
        dirs = [
          Kodo.home_dir,
          File.join(Kodo.home_dir, "memory", "conversations"),
          File.join(Kodo.home_dir, "memory", "knowledge"),
          File.join(Kodo.home_dir, "memory", "reminders"),
          File.join(Kodo.home_dir, "memory", "audit"),
          File.join(Kodo.home_dir, "skills")
        ]
        dirs.each { |d| FileUtils.mkdir_p(d) }

        unless File.exist?(config_path)
          File.write(config_path, YAML.dump(DEFAULTS))
        end
      end

      private

      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end

    # --- Daemon ---
    def port               = data.dig("daemon", "port")
    def heartbeat_interval = data.dig("daemon", "heartbeat_interval")

    # --- LLM ---
    def llm_model = data.dig("llm", "model")
    def utility_model = data.dig("llm", "utility_model") || llm_model

    # Returns a hash of { "provider_name" => "actual_api_key" } for all configured providers
    def llm_api_keys
      providers = data.dig("llm", "providers") || {}
      keys = {}

      providers.each do |provider, settings|
        env_var = settings["api_key_env"]
        next unless env_var

        key = ENV[env_var]
        if key && !key.empty?
          ruby_llm_name = PROVIDER_KEY_MAP[provider] || provider
          keys[ruby_llm_name] = key
        end
      end

      if keys.empty?
        raise Error, "No LLM API keys found. Set at least one provider key (e.g. ANTHROPIC_API_KEY)"
      end

      keys
    end

    # Optional: Ollama base URL for local models
    def ollama_api_base
      data.dig("llm", "providers", "ollama", "api_base") || ENV["OLLAMA_API_BASE"]
    end

    # --- Memory / Encryption ---
    def memory_encryption? = data.dig("memory", "encryption") == true

    def memory_passphrase_env
      data.dig("memory", "passphrase_env") || "KODO_PASSPHRASE"
    end

    def memory_passphrase
      passphrase = ENV[memory_passphrase_env]
      if memory_encryption? && (passphrase.nil? || passphrase.empty?)
        raise Error, "Memory encryption is enabled but #{memory_passphrase_env} is not set"
      end
      passphrase
    end

    # --- Logging ---
    def log_level       = data.dig("logging", "level")&.to_sym || :info
    def audit_enabled?  = data.dig("logging", "audit") != false

    # --- Channels ---
    def telegram_bot_token
      env_var = data.dig("channels", "telegram", "bot_token_env")
      ENV.fetch(env_var) { raise Error, "Missing environment variable: #{env_var}" }
    end

    def telegram_enabled?
      data.dig("channels", "telegram", "enabled") == true
    end
  end
end
