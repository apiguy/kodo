# frozen_string_literal: true

require "ruby_llm"
require "time"

module Kodo
  module Tools
    class SetReminder < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Reminders'
      capability_primary true
      enabled_guidance 'Set, list, and dismiss reminders. Reminders are delivered proactively when due.'

      MAX_PER_TURN = 3
      MAX_CONTENT_LENGTH = 500

      description "Set a reminder for a future time. The reminder will be delivered proactively " \
                  "when the time arrives, even if the user hasn't sent a message."

      param :content, desc: "What to remind the user about (max 500 chars)"
      param :due_at, desc: "When to deliver the reminder, in ISO 8601 format (e.g. 2025-01-15T14:30:00-05:00)"

      attr_writer :channel_id, :chat_id

      def initialize(reminders:, audit:)
        super()
        @reminders = reminders
        @audit = audit
        @turn_count = 0
        @channel_id = nil
        @chat_id = nil
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(content:, due_at:)
        if content.length > MAX_CONTENT_LENGTH
          return "Content too long (#{content.length} chars). Maximum is #{MAX_CONTENT_LENGTH}."
        end

        if Memory::Redactor.sensitive?(content)
          return "Cannot store sensitive data in reminders."
        end

        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} reminders per message). Try again next message."
        end

        parsed_time = parse_time(due_at)
        return parsed_time if parsed_time.is_a?(String) # error message

        if parsed_time <= Time.now
          return "Cannot set a reminder in the past. Please provide a future time."
        end

        reminder = @reminders.add(
          content: content,
          due_at: parsed_time,
          channel_id: @channel_id,
          chat_id: @chat_id
        )

        @audit.log(
          event: "reminder_set",
          detail: "id:#{reminder['id']} due:#{reminder['due_at']} content:#{content.slice(0, 60)}"
        )

        "Reminder set for #{reminder['due_at']}: #{content} (id: #{reminder['id']})"
      rescue Kodo::Error => e
        e.message
      end

      def name
        "set_reminder"
      end

      private

      def parse_time(due_at)
        Time.parse(due_at)
      rescue ArgumentError, TypeError
        "Invalid time format '#{due_at}'. Use ISO 8601 (e.g. 2025-01-15T14:30:00-05:00)."
      end
    end
  end
end
