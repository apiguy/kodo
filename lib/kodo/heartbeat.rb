# frozen_string_literal: true

module Kodo
  class Heartbeat
    def initialize(channels:, router:, audit:, interval: 60)
      @channels = channels
      @router = router
      @audit = audit
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

      # Phase 3: Schedule — check cron-like pulses (future)
      # TODO: scheduled tasks

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
