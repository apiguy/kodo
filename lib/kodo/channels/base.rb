# frozen_string_literal: true

module Kodo
  module Channels
    class Base
      attr_reader :channel_id

      def initialize(channel_id:)
        @channel_id = channel_id
        @running = false
      end

      def connect!
        raise NotImplementedError
      end

      def disconnect!
        @running = false
      end

      # Check for new messages. Returns Array<Kodo::Message>
      def poll
        raise NotImplementedError
      end

      # Send a message through this channel
      def send_message(message)
        raise NotImplementedError
      end

      def running?
        @running
      end
    end
  end
end
