# frozen_string_literal: true

require 'ruby_llm'
require 'securerandom'
require 'tmpdir'
require 'fileutils'

module Kodo
  module Tools
    # Browser tool exposed to the main agent. Launches a sandboxed sub-agent that
    # drives playwright-cli and returns a clean summary. Raw page content never
    # enters the main agent's context window.
    class BrowseWeb < RubyLLM::Tool
      extend PromptContributor
      include Web::UrlValidator

      capability_name 'Web Browser'
      capability_primary true
      enabled_guidance 'Browse websites requiring JavaScript or multi-step interaction. ' \
                       'Use when fetch_url cannot render the page.'
      disabled_guidance \
        "Install Node.js and playwright-cli: npm install -g @playwright/cli\n" \
        'Then set web.browser_enabled: true in ~/.kodo/config.yml'

      MAX_PER_TURN = 2

      description 'Browse a website using a real browser (JavaScript, SPAs, multi-step interaction). ' \
                  'Use when fetch_url is insufficient.'
      param :url,  desc: 'Starting URL to browse (http or https)'
      param :task, desc: 'What to find or do on the page (e.g. "get the page title", "fill the login form")'

      attr_writer :turn_context

      def initialize(audit:, sensitive_values_fn: nil)
        super()
        @audit = audit
        @sensitive_values_fn = sensitive_values_fn
        @turn_count = 0
        @turn_context = nil
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(url:, task:)
        @turn_count += 1
        return "Rate limit reached (max #{MAX_PER_TURN} browser sessions per message)." if @turn_count > MAX_PER_TURN

        validate_url!(url, sensitive_values_fn: @sensitive_values_fn)

        session_id = nil
        session_dir = nil
        nonce = @turn_context&.nonce || 'no-nonce'

        session_id = SecureRandom.hex(8)
        session_dir = Dir.mktmpdir("kodo-browser-#{session_id}-")

        # Open browser and navigate in one step
        Dir.chdir(session_dir) { `playwright-cli -s=#{session_id} open #{url} 2>&1` }

        result = Browser::SubAgent.new(audit: @audit, sensitive_values_fn: @sensitive_values_fn)
                                  .run(task: task, url: url, session_id: session_id, session_dir: session_dir)

        @turn_context&.web_fetched!

        wrap_as_untrusted(url, result, nonce)
      rescue Kodo::Error => e
        e.message
      ensure
        system("playwright-cli -s=#{session_id} close 2>/dev/null") if session_id
        FileUtils.rm_rf(session_dir) if session_dir
      end

      def name
        'browse_web'
      end

      private

      def wrap_as_untrusted(url, text, nonce)
        # If the content somehow contains our nonce, replace it (near-impossible but defensive)
        safe_text = text.gsub(nonce, '[nonce-collision-redacted]')
        <<~CONTENT
          [WEB:#{nonce}:START]
          Source: #{url}
          ---
          #{safe_text}
          ---
          [WEB:#{nonce}:END]
        CONTENT
      end
    end
  end
end
