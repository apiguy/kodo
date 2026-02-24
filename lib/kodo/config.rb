# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'securerandom'

module Kodo
  class Config
    # Map of Kodo config key → RubyLLM config setter name
    PROVIDER_KEY_MAP = {
      'anthropic' => 'anthropic',
      'openai' => 'openai',
      'gemini' => 'gemini',
      'deepseek' => 'deepseek',
      'mistral' => 'mistral',
      'openrouter' => 'openrouter',
      'perplexity' => 'perplexity',
      'xai' => 'xai'
    }.freeze

    DEFAULTS = {
      'daemon' => {
        'port' => 7377,
        'heartbeat_interval' => 60
      },
      'llm' => {
        'model' => 'claude-sonnet-4-6',
        'utility_model' => 'claude-haiku-4-5-20251001',
        'providers' => {
          'anthropic' => { 'api_key_env' => 'ANTHROPIC_API_KEY' }
        }
      },
      'channels' => {
        'telegram' => {
          'enabled' => false,
          'bot_token_env' => 'TELEGRAM_BOT_TOKEN'
        }
      },
      'memory' => {
        'encryption' => false,
        'passphrase_env' => 'KODO_PASSPHRASE',
        'store' => 'file'
      },
      'search' => {
        'provider' => nil,
        'providers' => {
          'tavily' => { 'api_key_env' => 'TAVILY_API_KEY' }
        }
      },
      'logging' => {
        'level' => 'info',
        'audit' => true
      },
      'web' => {
        'fetch_url_enabled' => true,
        'web_search_enabled' => true,
        'injection_scan' => true,
        'audit_urls' => true,
        'fetch_blocklist' => [],
        'fetch_allowlist' => [],
        'ssrf_bypass_hosts' => [],
        'browser_enabled' => false,
        'browser_timeout' => 30
      },
      'autonomy' => {
        'enabled' => false,
        'posture' => 'balanced',
        'rules' => []
      },
      'agent' => {
        'name' => 'Kodo',
        'email' => nil,
        'email_provider' => nil
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
        File.join(Kodo.home_dir, 'config.yml')
      end

      def ensure_home_dir!
        dirs = [
          Kodo.home_dir,
          File.join(Kodo.home_dir, 'memory', 'conversations'),
          File.join(Kodo.home_dir, 'memory', 'knowledge'),
          File.join(Kodo.home_dir, 'memory', 'reminders'),
          File.join(Kodo.home_dir, 'memory', 'audit'),
          File.join(Kodo.home_dir, 'memory', 'autonomy'),
          File.join(Kodo.home_dir, 'skills')
        ]
        dirs.each { |d| FileUtils.mkdir_p(d) }

        return if File.exist?(config_path)

        File.write(config_path, YAML.dump(DEFAULTS))
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
    def port               = data.dig('daemon', 'port')
    def heartbeat_interval = data.dig('daemon', 'heartbeat_interval')

    # --- LLM ---
    def llm_model = data.dig('llm', 'model')
    def utility_model = data.dig('llm', 'utility_model') || llm_model
    def pulse_model = data.dig('llm', 'pulse_model') || utility_model

    # Returns a hash of { "provider_name" => "actual_api_key" } for all configured providers
    def llm_api_keys
      providers = data.dig('llm', 'providers') || {}
      keys = {}

      providers.each do |provider, settings|
        env_var = settings['api_key_env']
        next unless env_var

        key = ENV[env_var]
        if key && !key.empty?
          ruby_llm_name = PROVIDER_KEY_MAP[provider] || provider
          keys[ruby_llm_name] = key
        end
      end

      raise Error, 'No LLM API keys found. Set at least one provider key (e.g. ANTHROPIC_API_KEY)' if keys.empty?

      keys
    end

    # Optional: Ollama base URL for local models
    def ollama_api_base
      data.dig('llm', 'providers', 'ollama', 'api_base') || ENV['OLLAMA_API_BASE']
    end

    # --- Memory / Encryption ---
    def memory_encryption? = data.dig('memory', 'encryption') == true

    def memory_passphrase_env
      data.dig('memory', 'passphrase_env') || 'KODO_PASSPHRASE'
    end

    def memory_passphrase
      passphrase = ENV[memory_passphrase_env]
      if memory_encryption? && (passphrase.nil? || passphrase.empty?)
        raise Error, "Memory encryption is enabled but #{memory_passphrase_env} is not set"
      end

      passphrase
    end

    # --- Secrets ---
    def secrets_passphrase
      passphrase_path = File.join(Kodo.home_dir, '.passphrase')
      if File.exist?(passphrase_path)
        File.read(passphrase_path).strip
      else
        passphrase = SecureRandom.hex(32)
        FileUtils.mkdir_p(Kodo.home_dir)
        File.write(passphrase_path, passphrase)
        File.chmod(0o600, passphrase_path)
        passphrase
      end
    end

    # --- Logging ---
    def log_level       = data.dig('logging', 'level')&.to_sym || :info
    def audit_enabled?  = data.dig('logging', 'audit') != false

    # --- Channels ---
    def telegram_bot_token
      env_var = data.dig('channels', 'telegram', 'bot_token_env')
      ENV.fetch(env_var) { raise Error, "Missing environment variable: #{env_var}" }
    end

    def telegram_enabled?
      data.dig('channels', 'telegram', 'enabled') == true
    end

    # --- Search ---
    def search_provider
      data.dig('search', 'provider')
    end

    def search_configured?
      !search_provider.nil? && !search_provider.empty?
    end

    def search_api_key
      return nil unless search_configured?

      provider = search_provider
      env_var = data.dig('search', 'providers', provider, 'api_key_env')
      return nil unless env_var

      ENV[env_var]
    end

    # --- Web ---
    def web_fetch_url_enabled? = data.dig('web', 'fetch_url_enabled') != false
    def web_search_enabled?    = data.dig('web', 'web_search_enabled') != false
    def web_injection_scan?    = data.dig('web', 'injection_scan') != false
    def web_audit_urls?        = data.dig('web', 'audit_urls') != false

    def web_fetch_blocklist
      data.dig('web', 'fetch_blocklist') || []
    end

    def web_fetch_allowlist
      data.dig('web', 'fetch_allowlist') || []
    end

    def web_ssrf_bypass_hosts
      data.dig('web', 'ssrf_bypass_hosts') || []
    end

    # --- Browser ---
    def browser_enabled?  = data.dig('web', 'browser_enabled') == true
    def browser_timeout   = data.dig('web', 'browser_timeout') || 30
    def browser_model     = data.dig('web', 'browser_model') || utility_model
    def browser_path      = data.dig('web', 'browser_path')

    # --- Autonomy ---
    def autonomy_enabled? = data.dig('autonomy', 'enabled') == true
    def autonomy_posture  = (data.dig('autonomy', 'posture') || 'balanced').to_sym

    def autonomy_rules
      raw = data.dig('autonomy', 'rules') || []
      raw.filter_map do |entry|
        next unless entry.is_a?(Hash) && entry['action']

        Autonomy::Rule.new(
          action: entry['action'].to_sym,
          scope: (entry['scope'] || {}).transform_keys(&:to_sym),
          level: (entry['level'] || 'propose').to_sym,
          reason: entry['reason'] || 'Configured in config.yml'
        )
      end
    end

    # --- Agent Identity ---
    def agent_name     = data.dig('agent', 'name') || 'Kodo'
    def agent_email    = data.dig('agent', 'email')
    def email_provider = data.dig('agent', 'email_provider')

    # --- Daemon (extended) ---
    def pulse_interval = data.dig('daemon', 'pulse_interval') || 3600

    def search_provider_instance
      return nil unless search_configured?

      case search_provider
      when 'tavily'
        api_key = search_api_key
        unless api_key
          raise Error,
                "Tavily API key not set (#{data.dig('search', 'providers', 'tavily', 'api_key_env')})"
        end

        Search::Tavily.new(api_key: api_key)
      else
        raise Error, "Unknown search provider: #{search_provider}"
      end
    end
  end
end
