# frozen_string_literal: true

module Kodo
  module Tools
    # Mixin for tool classes to declare prompt-level capability metadata.
    # Tools `extend` this module and use getter/setter class methods to
    # describe how they appear in the assembled system prompt.
    #
    #   class WebSearch < RubyLLM::Tool
    #     extend PromptContributor
    #     capability_name "Web Search"
    #     capability_primary true
    #     enabled_guidance "Search the web for current information."
    #   end
    #
    module PromptContributor
      def capability_name(name = :__unset__)
        if name == :__unset__
          @capability_name
        else
          @capability_name = name
        end
      end

      def capability_primary(val = :__unset__)
        if val == :__unset__
          @capability_primary || false
        else
          @capability_primary = val
        end
      end

      def enabled_guidance(text = :__unset__)
        if text == :__unset__
          @enabled_guidance
        else
          @enabled_guidance = text
        end
      end

      def disabled_guidance(text = :__unset__)
        if text == :__unset__
          @disabled_guidance
        else
          @disabled_guidance = text
        end
      end
    end
  end
end
