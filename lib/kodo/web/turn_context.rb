# frozen_string_literal: true

require 'securerandom'

module Kodo
  module Web
    # Created fresh for each Router#route call. Shared across all tools in a turn.
    # The nonce is used to wrap web content in markers that cannot be forged by
    # an attacker who knows the source code, because the nonce is generated on
    # Kodo's machine at request time.
    class TurnContext
      attr_reader :nonce, :web_fetched

      def initialize
        @nonce = SecureRandom.hex(12) # 96 bits — unguessable at page-write time
        @web_fetched = false
      end

      # Called mechanically by FetchUrl and WebSearch — not by the LLM.
      def web_fetched!
        @web_fetched = true
      end
    end
  end
end
