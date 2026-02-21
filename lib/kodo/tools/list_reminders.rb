# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class ListReminders < RubyLLM::Tool
      description "List all active reminders, sorted by due time."

      def initialize(reminders:, audit:)
        super()
        @reminders = reminders
        @audit = audit
      end

      def execute
        active = @reminders.all_active.sort_by { |r| r["due_at"] }

        @audit.log(event: "tool_list_reminders", detail: "count:#{active.length}")

        if active.empty?
          "No active reminders."
        else
          lines = active.map do |r|
            "- [#{r['due_at']}] #{r['content']} (id: #{r['id']})"
          end
          "#{active.length} active reminder(s):\n#{lines.join("\n")}"
        end
      end

      def name
        "list_reminders"
      end
    end
  end
end
