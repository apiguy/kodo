# frozen_string_literal: true

require 'ruby_llm'

module Kodo
  module Tools
    class ApproveAction < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Autonomy'
      capability_primary true
      enabled_guidance 'You have an autonomy system. When a tool action is blocked ' \
                       'with "requires user approval", explain your intent, get permission, ' \
                       'then call approve_action to register the approval and retry.'

      description 'Register user approval for an action that required permission. ' \
                  'Only call this AFTER the user has explicitly approved.'

      param :action,  desc: 'The tool/action name that was blocked (e.g. "fetch_url")'
      param :scope,   desc: 'JSON scope narrowing the approval (e.g. {"domain": "example.com"})', required: false
      param :level,   desc: 'Autonomy level to grant: "free" or "notify" (default: "free")', required: false
      param :persist, desc: 'Whether to persist this rule for future sessions (default: true)', required: false

      MAX_PER_TURN = 3

      def initialize(rule_store:, audit:, on_rule_added: nil)
        super()
        @rule_store = rule_store
        @audit = audit
        @on_rule_added = on_rule_added
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(action:, scope: {}, level: 'free', persist: true) # rubocop:disable Lint/UnusedMethodArgument
        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} approvals per message). Try again next message."
        end

        level_sym = level.to_sym
        return "Invalid level '#{level}'. Must be 'free' or 'notify'." unless %i[free notify].include?(level_sym)

        parsed_scope = scope.is_a?(String) ? JSON.parse(scope) : (scope || {})

        rule = @rule_store.add(
          action: action.to_sym,
          scope: parsed_scope,
          level: level_sym,
          reason: 'Approved by user via chat',
          granted_via: 'chat'
        )

        @audit.log(
          event: 'autonomy_approval',
          detail: "action:#{action} level:#{level} scope:#{parsed_scope}"
        )

        @on_rule_added&.call

        "Approval registered for '#{action}' (level: #{rule.level}). You can now retry the action."
      rescue JSON::ParserError
        'Invalid scope format. Provide a valid JSON object.'
      end

      def name
        'approve_action'
      end
    end
  end
end
