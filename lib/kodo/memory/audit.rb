# frozen_string_literal: true

require "json"
require "fileutils"

module Kodo
  module Memory
    class Audit
      def initialize
        @audit_dir = File.join(Kodo.home_dir, "memory", "audit")
        FileUtils.mkdir_p(@audit_dir)
      end

      # Log an event to the audit trail
      def log(event:, channel: nil, detail: nil)
        entry = {
          "timestamp" => Time.now.iso8601,
          "event" => event,
          "channel" => channel,
          "detail" => detail
        }.compact

        append_to_daily_log(entry)
        Kodo.logger.debug("Audit: #{event} #{detail&.slice(0, 80)}")
      end

      # Read today's audit log
      def today
        read_log(Date.today)
      end

      private

      def append_to_daily_log(entry)
        path = log_path(Date.today)
        File.open(path, "a") do |f|
          f.puts(JSON.generate(entry))
        end
      end

      def log_path(date)
        File.join(@audit_dir, "#{date.iso8601}.jsonl")
      end

      def read_log(date)
        path = log_path(date)
        return [] unless File.exist?(path)

        File.readlines(path).map { |line| JSON.parse(line) }
      rescue JSON::ParserError
        []
      end
    end
  end
end
