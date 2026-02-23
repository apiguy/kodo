# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module Tools
    class UpdatePulse < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Pulse Configuration'
      capability_primary true
      enabled_guidance 'Use update_pulse to modify the pulse.md file that controls idle heartbeat behavior.'

      description 'Update the pulse.md file that controls what Kodo does during idle heartbeat cycles.'
      param :content, desc: 'New pulse.md content (Markdown, max 10000 chars)'

      MAX_PER_TURN = 1
      MAX_CONTENT_LENGTH = 10_000

      def initialize(audit:)
        super()
        @audit = audit
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(content:)
        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} pulse update per message). Try again next message."
        end

        return "Content too long (max #{MAX_CONTENT_LENGTH} chars)." if content.length > MAX_CONTENT_LENGTH

        pulse_path = File.join(Kodo.home_dir, 'pulse.md')

        # Back up current pulse.md before overwriting
        if File.exist?(pulse_path)
          backup_path = File.join(Kodo.home_dir, 'pulse.md.bak')
          FileUtils.cp(pulse_path, backup_path)
        end

        File.write(pulse_path, content)
        @audit.log(event: 'pulse_updated', detail: "len:#{content.length}")

        "Pulse updated (#{content.length} chars). Previous version backed up to pulse.md.bak."
      end

      def name
        'update_pulse'
      end
    end
  end
end
