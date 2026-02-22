# frozen_string_literal: true

module Kodo
  class Daemon
    attr_reader :config, :channels, :router, :heartbeat

    def initialize(config: nil, heartbeat_interval: nil)
      @config = config || Kodo.config
      @heartbeat_interval = heartbeat_interval || @config.heartbeat_interval

      passphrase = resolve_passphrase
      @memory = Memory::Store.new(passphrase: passphrase)
      @audit = Memory::Audit.new
      @knowledge = Memory::Knowledge.new(passphrase: passphrase)
      @reminders = Memory::Reminders.new(passphrase: passphrase)
      @prompt_assembler = PromptAssembler.new
      @search_provider = resolve_search_provider
      @broker = build_broker
      @router = Router.new(
        memory: @memory,
        audit: @audit,
        prompt_assembler: @prompt_assembler,
        knowledge: @knowledge,
        reminders: @reminders,
        search_provider: @search_provider,
        broker: @broker,
        on_secret_stored: method(:on_secret_stored)
      )
      @channels = []
    end

    def start!
      Kodo.logger.info("Kodo v#{VERSION} starting...")
      Kodo.logger.info("   Home: #{Kodo.home_dir}")

      Config.ensure_home_dir!
      @prompt_assembler.ensure_default_files!
      configure_llm!
      connect_channels!

      # Log which prompt files were found
      %w[persona.md user.md pulse.md origin.md].each do |f|
        path = File.join(Kodo.home_dir, f)
        status = File.exist?(path) ? '+' : ' '
        Kodo.logger.info("   #{status} #{f}")
      end

      Kodo.logger.info('   Memory encryption: enabled') if @config.memory_encryption?

      Kodo.logger.info("   Search: #{@config.search_provider}") if @search_provider

      Kodo.logger.info("   Knowledge facts: #{@knowledge.count}")
      Kodo.logger.info("   Active reminders: #{@reminders.active_count}")

      start_heartbeat!
    end

    def stop!
      Kodo.logger.info('Kodo shutting down...')
      @heartbeat&.stop!
      @channels.each(&:disconnect!)
      Kodo.logger.info('Goodbye.')
    end

    private

    def build_broker
      secrets_store = Secrets::Store.new(passphrase: @config.secrets_passphrase)
      Secrets::Broker.new(store: secrets_store, audit: @audit)
    end

    def on_secret_stored(_secret_name)
      rebuild_search_provider!
      @router.reload_tools!(search_provider: @search_provider)
      LLM.configure!(config, broker: @broker)
    end

    def rebuild_search_provider!
      return unless @broker.available?('tavily_api_key')

      api_key = @broker.fetch('tavily_api_key', requestor: 'search')
      @search_provider = Search::Tavily.new(api_key: api_key) if api_key
    rescue Kodo::Error => e
      Kodo.logger.warn("Failed to rebuild search provider: #{e.message}")
    end

    def resolve_search_provider
      @config.search_provider_instance
    rescue Kodo::Error => e
      Kodo.logger.warn("Search disabled: #{e.message}")
      nil
    end

    def resolve_passphrase
      return nil unless @config.memory_encryption?

      passphrase = @config.memory_passphrase
      unless passphrase
        Kodo.logger.warn('Memory encryption enabled but no passphrase set. Data will be stored in plaintext.')
      end
      passphrase
    end

    def configure_llm!
      LLM.configure!(config, broker: @broker)
      Kodo.logger.info("   Model: #{config.llm_model}")
    end

    def connect_channels!
      if config.telegram_enabled?
        telegram = Channels::Telegram.new(bot_token: config.telegram_bot_token)
        telegram.connect!
        @channels << telegram
      end

      Kodo.logger.warn('No channels configured! Enable at least one in ~/.kodo/config.yml') if @channels.empty?

      Kodo.logger.info("Connected #{@channels.length} channel(s)")
    end

    def start_heartbeat!
      @heartbeat = Heartbeat.new(
        channels: @channels,
        router: @router,
        audit: @audit,
        reminders: @reminders,
        interval: @heartbeat_interval
      )

      trap('INT') { stop! }
      trap('TERM') { stop! }

      @heartbeat.start!
    end
  end
end
