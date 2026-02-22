# frozen_string_literal: true

module Kodo
  module Web
    # Detection-only scanner for common prompt injection patterns in web content.
    #
    # IMPORTANT: This is not a security boundary. An attacker who reads Kodo's
    # source can phrase injections to avoid these patterns. The scanner's value
    # is in catching unsophisticated/automated attacks and producing audit events.
    # The actual security boundary is the nonce-based content isolation in TurnContext.
    class InjectionScanner
      # Result value object
      Result = Data.define(:signal_count, :signals) do
        def suspicious?
          signal_count.positive?
        end
      end

      # Patterns that commonly appear in prompt injection attempts.
      # Deliberately broad — false positives are acceptable since we only log, not block.
      PATTERNS = [
        /ignore\s+(all\s+)?previous\s+instructions?/i,
        /disregard\s+(all\s+)?previous\s+instructions?/i,
        /forget\s+(all\s+)?previous\s+instructions?/i,
        /you\s+are\s+now\s+a\s+/i,
        /new\s+instructions?:/i,
        /system\s+prompt:/i,
        /\[\s*system\s*\]/i,
        /exfiltrate/i,
        /send\s+(all\s+)?memory\s+to/i,
        /reveal\s+(your\s+)?(system\s+)?prompt/i,
        /print\s+(your\s+)?(system\s+)?prompt/i,
        /override\s+(your\s+)?directives?/i,
        /DAN\s+mode/i,
        /jailbreak/i
      ].freeze

      def self.scan(text)
        return Result.new(signal_count: 0, signals: []) if text.nil? || text.empty?

        matched = PATTERNS.filter_map do |pattern|
          match = text.match(pattern)
          match[0] if match
        end

        Result.new(signal_count: matched.length, signals: matched)
      end
    end
  end
end
