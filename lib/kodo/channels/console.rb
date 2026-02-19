# frozen_string_literal: true

module Kodo
  module Channels
    class Console < Base
      def initialize
        @inbox = Queue.new
        super(channel_id: "console")
      end

      def connect!
        @running = true
        Kodo.logger.info("Console channel ready")
        self
      end

      def disconnect!
        @running = false
      end

      def poll
        messages = []
        messages << @inbox.pop(true) until @inbox.empty?
        messages
      rescue ThreadError
        # Queue.pop(true) raises ThreadError when empty
        messages
      end

      def send_message(message)
        puts "\n\e[36mKodo:\e[0m #{message.content}\n\n"
      end

      # Push a message into the inbox (called from CLI input thread)
      def push(text)
        @inbox << Message.new(
          channel_id: channel_id,
          sender: :user,
          content: text,
          metadata: { chat_id: "console" }
        )
      end
    end
  end
end
