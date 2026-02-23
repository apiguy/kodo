# frozen_string_literal: true

module Kodo
  module Autonomy
    Rule = Data.define(:action, :scope, :level, :reason, :granted_at, :granted_via) do
      def initialize(action:, level:, reason:, scope: {}, granted_at: nil, granted_via: nil)
        super
      end

      def matches?(action_name, context)
        return false unless action == action_name.to_sym || action == :any
        return true if scope.nil? || scope.empty?

        scope.all? { |key, pattern| match_value?(context[key], pattern) }
      end

      private

      def match_value?(actual, pattern)
        return actual == pattern if pattern.is_a?(Symbol) || !pattern.is_a?(String)
        return false if actual.nil?

        if pattern.start_with?('*.')
          actual.to_s.end_with?(pattern[1..])
        elsif pattern == '*'
          true
        else
          actual.to_s == pattern
        end
      end
    end
  end
end
