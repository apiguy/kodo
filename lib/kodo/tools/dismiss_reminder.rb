# frozen_string_literal: true

require "ruby_llm"

module Kodo
  module Tools
    class DismissReminder < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Reminders'

      description "Dismiss (cancel) an active reminder by its ID."

      param :id, desc: "The UUID of the reminder to dismiss"

      def initialize(reminders:, audit:)
        super()
        @reminders = reminders
        @audit = audit
      end

      def execute(id:)
        reminder = @reminders.dismiss(id)

        if reminder
          @audit.log(
            event: "reminder_dismissed",
            detail: "id:#{id} content:#{reminder['content']&.slice(0, 60)}"
          )
          "Dismissed reminder: #{reminder['content']}"
        else
          "No active reminder found with id: #{id}"
        end
      end

      def name
        "dismiss_reminder"
      end
    end
  end
end
