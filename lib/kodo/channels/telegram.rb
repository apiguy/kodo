# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Kodo
  module Channels
    class Telegram < Base
      API_BASE = "https://api.telegram.org"

      def initialize(bot_token:)
        @bot_token = bot_token
        @last_update_id = 0
        @allowed_chat_ids = []  # empty = allow all (for now)
        super(channel_id: "telegram")
      end

      def connect!
        # Verify the bot token works
        me = api_request("getMe")
        bot_name = me.dig("result", "username")
        Kodo.logger.info("Telegram connected as @#{bot_name}")
        @running = true
        self
      rescue StandardError => e
        raise Error, "Failed to connect Telegram: #{e.message}"
      end

      def disconnect!
        @running = false
        Kodo.logger.info("Telegram disconnected")
      end

      # Poll for new messages using long polling with a short timeout
      # Returns Array<Kodo::Message>
      def poll
        return [] unless running?

        params = {
          offset: @last_update_id + 1,
          timeout: 1,  # short poll — we're inside a heartbeat loop
          allowed_updates: ["message"]
        }

        response = api_request("getUpdates", params)
        updates = response.dig("result") || []

        messages = updates.filter_map do |update|
          @last_update_id = update["update_id"]
          parse_update(update)
        end

        messages
      rescue StandardError => e
        Kodo.logger.warn("Telegram poll error: #{e.message}")
        []
      end

      def send_message(message)
        chat_id = message.metadata[:chat_id] || message.metadata["chat_id"]
        return unless chat_id

        params = {
          chat_id: chat_id,
          text: message.content,
          parse_mode: "Markdown"
        }

        # If replying to a specific message
        if (reply_to = message.metadata[:reply_to_message_id] || message.metadata["reply_to_message_id"])
          params[:reply_to_message_id] = reply_to
        end

        api_request("sendMessage", params)
        Kodo.logger.debug("Sent Telegram message to chat #{chat_id}")
      rescue StandardError => e
        Kodo.logger.error("Telegram send error: #{e.message}")

        # Retry without markdown if parse failed
        if e.message.include?("parse")
          params.delete(:parse_mode)
          api_request("sendMessage", params) rescue nil
        end
      end

      private

      def parse_update(update)
        msg = update["message"]
        return nil unless msg && msg["text"]

        # Skip if we're filtering chat IDs and this isn't allowed
        if @allowed_chat_ids.any? && !@allowed_chat_ids.include?(msg["chat"]["id"])
          return nil
        end

        sender_name = [msg.dig("from", "first_name"), msg.dig("from", "last_name")]
          .compact.join(" ")

        Message.new(
          channel_id: channel_id,
          sender: :user,
          content: msg["text"],
          timestamp: Time.at(msg["date"]),
          metadata: {
            chat_id: msg["chat"]["id"],
            message_id: msg["message_id"],
            sender_name: sender_name,
            sender_username: msg.dig("from", "username"),
            sender_id: msg.dig("from", "id")
          }
        )
      end

      def api_request(method, params = {})
        uri = URI("#{API_BASE}/bot#{@bot_token}/#{method}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(params)

        response = http.request(request)
        parsed = JSON.parse(response.body)

        unless parsed["ok"]
          raise Error, "Telegram API error: #{parsed["description"]}"
        end

        parsed
      end
    end
  end
end
