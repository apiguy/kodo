# frozen_string_literal: true

module Kodo
  module Autonomy
    class Policy
      LEVELS = %i[free notify propose never].freeze
      DEFAULT_LEVEL = :propose

      BUILTIN_RULES = [
        Rule.new(action: :get_current_time, level: :free, reason: 'Read-only, no side effects'),
        Rule.new(action: :recall_facts,     level: :free, reason: 'Read-only memory query'),
        Rule.new(action: :list_reminders,   level: :free, reason: 'Read-only'),
        Rule.new(action: :remember_fact,    level: :free, reason: 'Internal memory, reversible'),
        Rule.new(action: :forget_fact,      level: :free, reason: 'Internal memory, reversible'),
        Rule.new(action: :update_fact,      level: :free, reason: 'Internal memory, reversible'),
        Rule.new(action: :set_reminder,     level: :free, reason: 'Internal scheduling, reversible'),
        Rule.new(action: :dismiss_reminder, level: :free, reason: 'Internal, reversible'),
        Rule.new(action: :web_search,       level: :free, reason: 'Read-only web search'),
        Rule.new(action: :fetch_url,        level: :free, reason: 'Read-only URL fetch'),
        Rule.new(action: :browse_web,       level: :free, reason: 'Read-only via sandboxed sub-agent'),
        Rule.new(action: :store_secret,     level: :notify, reason: 'Stores credential'),
        Rule.new(action: :smtp_send,       level: :propose, reason: 'Email to new recipient requires approval'),
        Rule.new(action: :approve_action,  level: :free, reason: 'Approval registration is always allowed'),
        Rule.new(action: :update_pulse,    level: :notify, reason: 'Modifies heartbeat behavior')
      ].freeze

      def initialize(builtin_rules: BUILTIN_RULES, config_rules: [], persistent_rules: [], posture: :balanced)
        @rules = builtin_rules + persistent_rules + config_rules # config wins over persistent
        @posture = posture.to_sym
      end

      def evaluate(action:, context: {})
        rule = find_matching_rule(action.to_sym, context)
        level = rule ? rule.level : DEFAULT_LEVEL
        level = apply_posture(level)
        Decision.new(level: level, reason: rule&.reason || 'No matching rule (default: propose)', rule: rule)
      end

      private

      def find_matching_rule(action, context)
        matching = @rules.each_with_index.select { |r, _i| r.matches?(action, context) }
        return nil if matching.empty?

        # Most specific scope wins; ties broken by array position (later = higher priority)
        matching.max_by { |r, i| [r.scope&.size || 0, i] }&.first
      end

      def apply_posture(level)
        case @posture
        when :conservative then level == :notify ? :propose : level
        when :autonomous   then level == :propose ? :notify : level
        else level
        end
      end
    end
  end
end
