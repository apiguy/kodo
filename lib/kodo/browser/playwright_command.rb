# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module Browser
    # The only tool exposed to the browser sub-agent.
    # Wraps playwright-cli shell invocations with an allowlist, URL validation,
    # and audit logging. Raw snapshot YAML is read from the per-session temp dir
    # and returned inline so the sub-agent can reason over page structure.
    class PlaywrightCommand < RubyLLM::Tool
      include Web::UrlValidator

      ALLOWED_COMMANDS = %w[goto snapshot click fill type press go-back reload hover].freeze
      MAX_PER_TURN = 10

      description 'Execute a playwright-cli browser command and return the result. ' \
                  'Allowed commands: goto URL, snapshot, click ref, fill ref text, ' \
                  'type ref text, press key, go-back, reload, hover ref.'
      param :command, desc: 'Playwright CLI command string (e.g. "snapshot", "goto https://example.com", "click e3")'

      def initialize(session_id:, session_dir:, audit:, sensitive_values_fn: nil)
        super()
        @session_id = session_id
        @session_dir = session_dir
        @audit = audit
        @sensitive_values_fn = sensitive_values_fn
        @turn_count = 0
      end

      def execute(command:)
        @turn_count += 1
        return "Error: command limit reached (max #{MAX_PER_TURN} per session)." if @turn_count > MAX_PER_TURN

        verb, args_str = command.strip.split(/\s+/, 2)

        return "Error: command '#{verb}' is not allowed." unless ALLOWED_COMMANDS.include?(verb)

        if verb == 'goto'
          url = args_str&.strip
          validate_url!(url, sensitive_values_fn: @sensitive_values_fn)
          @audit.log(event: 'browser_navigate', detail: "url:#{url}")
        end

        stdout = Dir.chdir(@session_dir) do
          `playwright-cli -s=#{@session_id} #{command} 2>&1`
        end

        @audit.log(event: 'browser_action', detail: "cmd:#{verb}")

        # If playwright-cli references a snapshot file in its output, read and inline it
        if (match = stdout.match(/\[Snapshot\]\((.+?\.yml)\)/))
          snapshot_path = File.join(@session_dir, match[1])
          if File.exist?(snapshot_path)
            snapshot_yaml = File.read(snapshot_path)
            stdout = stdout.sub(/\[Snapshot\]\(.+?\.yml\)/, '[Snapshot content below]') +
                     "\n\n### Snapshot\n#{snapshot_yaml}"
          end
        end

        stdout
      rescue Kodo::Error => e
        "Error: #{e.message}"
      end

      def name
        'playwright_command'
      end
    end
  end
end
