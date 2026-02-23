# frozen_string_literal: true

module Kodo
  class FeatureToggle
    Feature = Data.define(:name, :description, :config_path, :enable_value, :disable_value, :deps)

    FEATURES = {
      'browser' => Feature.new(
        name: 'browser', description: 'Web browser via Playwright (browse_web tool)',
        config_path: 'web.browser_enabled', enable_value: true, disable_value: false,
        deps: [{ type: :command, command: 'node', hint: 'Install Node.js: https://nodejs.org' },
               { type: :command, command: 'playwright-cli',
                 hint: 'Install: npm install -g @playwright/cli && playwright-cli install chromium' }]
      ),
      'search' => Feature.new(
        name: 'search', description: 'Web search via Tavily (web_search tool)',
        config_path: 'search.provider', enable_value: 'tavily', disable_value: nil,
        deps: [{ type: :env, var: 'TAVILY_API_KEY',
                 hint: 'Get a key at https://tavily.com and set TAVILY_API_KEY' }]
      ),
      'autonomy' => Feature.new(
        name: 'autonomy', description: 'Risk-classified action gating for all tools',
        config_path: 'autonomy.enabled', enable_value: true, disable_value: false, deps: []
      ),
      'telegram' => Feature.new(
        name: 'telegram', description: 'Telegram messaging channel',
        config_path: 'channels.telegram.enabled', enable_value: true, disable_value: false,
        deps: [{ type: :env, var: 'TELEGRAM_BOT_TOKEN',
                 hint: 'Get a token from @BotFather on Telegram and set TELEGRAM_BOT_TOKEN' }]
      ),
      'encryption' => Feature.new(
        name: 'encryption', description: 'AES-256-GCM encryption for memory stores',
        config_path: 'memory.encryption', enable_value: true, disable_value: false,
        deps: [{ type: :env, var: 'KODO_PASSPHRASE', hint: 'Set KODO_PASSPHRASE to a secure passphrase' }]
      )
    }.freeze

    def initialize(writer: ConfigWriter.new)
      @writer = writer
    end

    def enable(name)
      feature = FEATURES[name]
      return unknown_feature(name) unless feature
      return unless deps_satisfied?(feature)
      return puts("#{name} is already enabled.") if @writer.read(feature.config_path) == feature.enable_value

      @writer.update(feature.config_path, feature.enable_value)
      puts "#{name} enabled."
      puts "  #{feature.description}"
    end

    def disable(name)
      feature = FEATURES[name]
      return unknown_feature(name) unless feature

      @writer.update(feature.config_path, feature.disable_value)
      puts "#{name} disabled."
    end

    def list
      puts 'Features:'
      puts ''
      FEATURES.each_value do |feature|
        current = @writer.read(feature.config_path)
        enabled = current == feature.enable_value
        status = enabled ? 'enabled ' : 'disabled'
        puts "  #{status}  #{feature.name.ljust(14)} #{feature.description}"
      end
      puts ''
      puts 'Usage: kodo enable <feature> | kodo disable <feature>'
    end

    private

    def deps_satisfied?(feature)
      missing = feature.deps.filter_map { |dep| check_dep(dep) }
      return true if missing.empty?

      puts "Cannot enable #{feature.name} — missing dependencies:"
      missing.each { |m| puts "  - #{m}" }
      false
    end

    def check_dep(dep)
      case dep[:type]
      when :command
        "#{dep[:command]} not found. #{dep[:hint]}" unless command_exists?(dep[:command])
      when :env
        "#{dep[:var]} not set. #{dep[:hint]}" unless ENV[dep[:var]] && !ENV[dep[:var]].empty?
      end
    end

    def command_exists?(cmd)
      system("which #{cmd} > /dev/null 2>&1")
    end

    def unknown_feature(name)
      puts "Unknown feature: #{name}"
      puts ''
      puts "Available features: #{FEATURES.keys.join(', ')}"
    end
  end
end
