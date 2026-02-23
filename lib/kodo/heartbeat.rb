# frozen_string_literal: true

module Kodo
  class Heartbeat
    def initialize(channels:, router:, audit:, reminders: nil, interval: 60, on_reload: nil)
      @channels = channels
      @router = router
      @audit = audit
      @reminders = reminders
      @interval = interval
      @on_reload = on_reload
      @running = false
      @beat_count = 0
      @last_pulse_at = nil
      @config_mtime = current_config_mtime
      @reload_requested = false
    end

    def start!
      @running = true
      Kodo.logger.info("💓 Heartbeat started (interval: #{@interval}s)")
      @audit.log(event: 'heartbeat_start', detail: "interval:#{@interval}s")

      loop do
        break unless @running

        check_config_reload!
        beat!
        sleep(@interval)
      end
    rescue Interrupt
      stop!
    end

    def stop!
      @running = false
      Kodo.logger.info("💓 Heartbeat stopped after #{@beat_count} beats")
      @audit.log(event: 'heartbeat_stop', detail: "beats:#{@beat_count}")
    end

    def running? = @running

    def request_reload!
      @reload_requested = true
    end

    private

    def check_config_reload!
      return unless @on_reload

      mtime = current_config_mtime
      reload_needed = @reload_requested || (mtime && mtime != @config_mtime)
      return unless reload_needed

      @config_mtime = mtime
      @reload_requested = false
      @on_reload.call
    rescue StandardError => e
      Kodo.logger.error("Config reload check failed: #{e.message}")
    end

    def current_config_mtime
      File.stat(Config.config_path).mtime
    rescue Errno::ENOENT
      nil
    end

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

      # Phase 4: Pulse evaluation on idle beats
      if incoming.empty? && pulse_interval_elapsed?
        evaluate_pulse!
        @last_pulse_at = Time.now
      end
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

      Kodo.logger.debug("Collected #{messages.length} message(s) from #{@channels.length} channel(s)") if messages.any?

      messages
    end

    def deliver_due_reminders!
      return unless @reminders

      @reminders.due_reminders.each do |reminder|
        channel = find_channel(reminder['channel_id'])
        next unless channel

        message = Message.new(
          channel_id: reminder['channel_id'],
          sender: :agent,
          content: "Reminder: #{reminder['content']}",
          metadata: { chat_id: reminder['chat_id'] }
        )

        channel.send_message(message)
        @reminders.fire!(reminder['id'])

        @audit.log(
          event: 'reminder_fired',
          channel: reminder['channel_id'],
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

    def pulse_interval_elapsed?
      return true if @last_pulse_at.nil?

      Time.now - @last_pulse_at >= Kodo.config.pulse_interval
    end

    def evaluate_pulse!
      channel = primary_channel
      return unless channel

      pulse_message = Message.new(
        channel_id: channel.channel_id,
        sender: :system,
        content: 'Pulse check. Evaluate your pulse instructions and take any appropriate actions.',
        metadata: { chat_id: 'pulse', pulse: true }
      )

      response = @router.route_pulse(pulse_message, channel: channel)
      return unless response&.content && !response.content.strip.empty?

      channel.send_message(response)
    rescue StandardError => e
      Kodo.logger.error("Pulse evaluation error: #{e.message}")
      Kodo.logger.debug(e.backtrace&.first(5)&.join("\n"))
    end

    def primary_channel
      @channels.find(&:running?)
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
        content: 'Sorry, I hit an error processing that. Check the logs for details.',
        metadata: { chat_id: message.metadata[:chat_id] || message.metadata['chat_id'] }
      )
      begin
        channel.send_message(error_msg)
      rescue StandardError
        nil
      end
    end
  end
end
