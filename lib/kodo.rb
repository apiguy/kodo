# frozen_string_literal: true

require "zeitwerk"

module Kodo
  class Error < StandardError; end

  class << self
    def loader
      @loader ||= begin
        loader = Zeitwerk::Loader.new
        loader.push_dir(File.join(__dir__))
        loader.inflector.inflect("llm" => "LLM")
        loader.setup
        loader
      end
    end

    def root
      @root ||= File.expand_path("..", __dir__)
    end

    def home_dir
      @home_dir ||= File.join(Dir.home, ".kodo")
    end

    def config
      @config ||= Config.load
    end

    def logger
      @logger ||= begin
        require "logger"
        Logger.new($stdout, level: config.log_level)
      end
    end
  end

  loader
end
