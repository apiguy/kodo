# frozen_string_literal: true

module Kodo
  class Heartbeat
    def initialize(channels:, router:, audit:, reminders: nil, interval: 60)
      @channels = channels
      @router = router
      @audit = audit
      @reminders = reminders
      @interval = interval
      @running = false
      @beat_count = 0
    end

    def start!
      @running = true
      Kodo.logger.info("💓 Heartbeat started (interval: #{@interval}s)")
      @audit.log(event: "heartbeat_start", detail: "interval:#{@interval}s")

      loop do
        break unless @running

        beat!
        sleep(@interval)
      end
    rescue Interrupt
      stop!
    end

    def stop!
      @running = false
      Kodo.logger.info("💓 Heartbeat stopped after #{@beat_count} beats")
      @audit.log(event: "heartbeat_stop", detail: "beats:#{@beat_count}")
    end

    def running? = @running

    private

    def beat!
      @beat_count += 1
      Kodo.logger.debug("💓 Beat ##{@beat_count}")

      # Phase 1: Collect — poll all channels for new messages
      incoming = collect_messages

      # Phase 2: Route — send each message through the router and respond
      incoming.each do |message, channel|
        process_message(message, channel)
      end

      # Phase 3: Reminders — deliver any due reminders
      deliver_due_reminders!

    rescue StandardError => e
      Kodo.logger.error("Heartbeat error: #{e.message}")
      Kodo.logger.debug(e.backtrace&.first(5)&.join("\n"))
    end

    def collect_messages
      messages = []

      @channels.each do |channel|
        next unless channel.running?

        channel_messages = channel.poll
        channel_messages.each do |msg|
          messages << [msg, channel]
        end
      end

      if messages.any?
        Kodo.logger.debug("Collected #{messages.length} message(s) from #{@channels.length} channel(s)")
      end

      messages
    end

    def deliver_due_reminders!
      return unless @reminders

      @reminders.due_reminders.each do |reminder|
        channel = find_channel(reminder["channel_id"])
        next unless channel

        message = Message.new(
          channel_id: reminder["channel_id"],
          sender: :agent,
          content: "Reminder: #{reminder['content']}",
          metadata: { chat_id: reminder["chat_id"] }
        )

        channel.send_message(message)
        @reminders.fire!(reminder["id"])

        @audit.log(
          event: "reminder_fired",
          channel: reminder["channel_id"],
          detail: "id:#{reminder['id']} content:#{reminder['content']&.slice(0, 60)}"
        )

        Kodo.logger.info("Fired reminder: #{reminder['content']&.slice(0, 60)}")
      rescue StandardError => e
        Kodo.logger.error("Error firing reminder #{reminder['id']}: #{e.message}")
      end
    end

    def find_channel(channel_id)
      @channels.find { |c| c.channel_id == channel_id && c.running? }
    end

    def process_message(message, channel)
      Kodo.logger.info("Processing: [#{channel.channel_id}] #{message.content.slice(0, 60)}...")

      response = @router.route(message, channel: channel)
      channel.send_message(response)

    rescue StandardError => e
      Kodo.logger.error("Error processing message: #{e.message}")

      # Try to send an error message back to the user
      error_msg = Message.new(
        channel_id: channel.channel_id,
        sender: :agent,
        content: "Sorry, I hit an error processing that. Check the logs for details.",
        metadata: { chat_id: message.metadata[:chat_id] || message.metadata["chat_id"] }
      )
      channel.send_message(error_msg) rescue nil
    end
  end
end
