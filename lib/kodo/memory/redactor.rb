# frozen_string_literal: true

require "json"

module Kodo
  module Memory
    module Redactor
      PLACEHOLDER = "[REDACTED]"

      SENSITIVE_PATTERNS = [
        /\b\d{3}-\d{2}-\d{4}\b/,                          # SSN
        /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,    # Credit card
        /\b(sk|pk|api|key|token|secret|password)[-_]?\w{10,}/i, # API keys/tokens
        /\bpassword\s*[:=]\s*\S+/i,                        # password: value
      ].freeze

      LLM_PROMPT = <<~PROMPT
        You are a sensitive data classifier. Analyze the following message and identify any sensitive information that should be redacted before storage. This includes but is not limited to:
        - Passwords, passphrases, or secrets mentioned in natural language
        - API keys, tokens, or credentials
        - Personal identifiers (SSN, credit card numbers, etc.)
        - Private keys or certificates

        Return ONLY a JSON array of objects with "start" and "end" character offsets (0-based, exclusive end) for each sensitive span. If nothing is sensitive, return an empty array [].

        Example: for "my database password is fluffybunny and that's it"
        Response: [{"start": 24, "end": 35}]

        Message to analyze:
      PROMPT

      class << self
        def sensitive?(text)
          SENSITIVE_PATTERNS.any? { |pattern| text.match?(pattern) }
        end

        # Regex-only redaction (fast, free)
        def redact(text)
          result = text.dup
          SENSITIVE_PATTERNS.each do |pattern|
            result.gsub!(pattern, PLACEHOLDER)
          end
          result
        end

        # Layered redaction: regex first, then LLM for anything regex missed
        def redact_smart(text)
          if sensitive?(text)
            redact(text)
          else
            redact_with_llm(text)
          end
        end

        # LLM-assisted redaction for context-dependent secrets
        def redact_with_llm(text)
          response = Kodo::LLM.utility_chat.ask("#{LLM_PROMPT}#{text}")
          spans = parse_spans(response.content)
          return text if spans.empty?

          apply_redactions(text, spans)
        rescue StandardError => e
          Kodo.logger.debug("LLM redaction skipped: #{e.message}")
          text
        end

        private

        def parse_spans(response_text)
          # Extract JSON array from the response (may be wrapped in markdown fences)
          json_str = response_text[/\[.*\]/m]
          return [] unless json_str

          spans = JSON.parse(json_str)
          return [] unless spans.is_a?(Array)

          spans.select { |s| s.is_a?(Hash) && s["start"].is_a?(Integer) && s["end"].is_a?(Integer) }
        rescue JSON::ParserError
          []
        end

        def apply_redactions(text, spans)
          result = text.dup
          # Apply spans in reverse order so earlier offsets remain valid
          spans.sort_by { |s| -s["start"] }.each do |span|
            start_pos = span["start"]
            end_pos = span["end"]
            next if start_pos < 0 || end_pos > result.length || start_pos >= end_pos

            result[start_pos...end_pos] = PLACEHOLDER
          end
          result
        end
      end
    end
  end
end
