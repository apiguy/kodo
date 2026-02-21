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
      @prompt_assembler = PromptAssembler.new
      @router = Router.new(
        memory: @memory,
        audit: @audit,
        prompt_assembler: @prompt_assembler,
        knowledge: @knowledge
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
        status = File.exist?(path) ? "+" : " "
        Kodo.logger.info("   #{status} #{f}")
      end

      if @config.memory_encryption?
        Kodo.logger.info("   Memory encryption: enabled")
      end

      Kodo.logger.info("   Knowledge facts: #{@knowledge.count}")

      start_heartbeat!
    end

    def stop!
      Kodo.logger.info("Kodo shutting down...")
      @heartbeat&.stop!
      @channels.each(&:disconnect!)
      Kodo.logger.info("Goodbye.")
    end

    private

    def resolve_passphrase
      return nil unless @config.memory_encryption?

      passphrase = @config.memory_passphrase
      unless passphrase
        Kodo.logger.warn("Memory encryption enabled but no passphrase set. Data will be stored in plaintext.")
      end
      passphrase
    end

    def configure_llm!
      LLM.configure!(config)
      Kodo.logger.info("   Model: #{config.llm_model}")
    end

    def connect_channels!
      if config.telegram_enabled?
        telegram = Channels::Telegram.new(bot_token: config.telegram_bot_token)
        telegram.connect!
        @channels << telegram
      end

      if @channels.empty?
        Kodo.logger.warn("No channels configured! Enable at least one in ~/.kodo/config.yml")
      end

      Kodo.logger.info("Connected #{@channels.length} channel(s)")
    end

    def start_heartbeat!
      @heartbeat = Heartbeat.new(
        channels: @channels,
        router: @router,
        audit: @audit,
        interval: @heartbeat_interval
      )

      trap("INT") { stop! }
      trap("TERM") { stop! }

      @heartbeat.start!
    end
  end
end
