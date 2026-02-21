# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class GetCurrentTime < RubyLLM::Tool
      description "Get the current date and time. Use this when you need to know what time it is, " \
                  "what day of the week it is, or make time-relative decisions."

      def initialize(audit:)
        super()
        @audit = audit
      end

      def execute
        now = Time.now
        day_name = now.strftime("%A")
        date_str = now.strftime("%Y-%m-%d")
        time_str = now.strftime("%H:%M:%S %Z")
        period = time_period(now.hour)

        @audit.log(event: "tool_get_current_time", detail: "#{date_str} #{time_str}")

        "#{day_name}, #{date_str} #{time_str} (#{period})"
      end

      def name
        "get_current_time"
      end

      private

      def time_period(hour)
        case hour
        when 5..11 then "morning"
        when 12..16 then "afternoon"
        when 17..20 then "evening"
        else "night"
        end
      end
    end
  end
end
