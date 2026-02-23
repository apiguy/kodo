# frozen_string_literal: true

module Kodo
  module Autonomy
    # Prepended onto each tool instance's singleton class to intercept
    # tool execution with autonomy policy checks.
    module Gated
      attr_writer :autonomy_policy, :autonomy_audit, :autonomy_rule_store

      def call(args = {})
        return super unless @autonomy_policy

        action = name.to_sym
        context = args.transform_keys(&:to_sym)
        decision = @autonomy_policy.evaluate(action: action, context: context)

        @autonomy_audit&.log(
          event: 'autonomy_check',
          detail: "tool:#{name} action:#{action} level:#{decision.level} reason:#{decision.reason}"
        )

        case decision.level
        when :free    then super
        when :notify  then super
        when :propose
          response = "This action requires user approval. Reason: #{decision.reason}. " \
                     'Please explain what you want to do and ask the user for permission before trying again.'
          ratchet_suggestion = build_ratchet_suggestion(action)
          ratchet_suggestion ? "#{response}\n\n#{ratchet_suggestion}" : response
        when :never
          "This action is not permitted. Reason: #{decision.reason}"
        end
      end

      private

      def build_ratchet_suggestion(action)
        return nil unless @autonomy_rule_store

        candidates = @autonomy_rule_store.ratchet_candidates(threshold: 5)
        match = candidates.find { |c| c['action'] == action.to_s }
        return nil unless match

        "Note: You've approved '#{action}' #{match['approval_count']} times. " \
          'You could suggest the user upgrade this to automatic.'
      end
    end
  end
end
