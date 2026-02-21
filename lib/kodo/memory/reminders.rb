# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"

module Kodo
  module Memory
    class Reminders
      MAX_ACTIVE = 50
      MAX_CONTENT_LENGTH = 500

      def initialize(passphrase: nil)
        @reminders_dir = File.join(Kodo.home_dir, "memory", "reminders")
        @passphrase = passphrase
        FileUtils.mkdir_p(@reminders_dir)
        @reminders = load_reminders
      end

      def add(content:, due_at:, channel_id: nil, chat_id: nil)
        if active_count >= MAX_ACTIVE
          raise Kodo::Error, "Too many active reminders (max #{MAX_ACTIVE}). Dismiss some first."
        end

        now = Time.now.iso8601
        reminder = {
          "id" => SecureRandom.uuid,
          "content" => content,
          "due_at" => due_at.is_a?(Time) ? due_at.iso8601 : due_at,
          "channel_id" => channel_id,
          "chat_id" => chat_id,
          "status" => "active",
          "created_at" => now
        }

        @reminders << reminder
        save_reminders
        reminder
      end

      def dismiss(id)
        reminder = @reminders.find { |r| r["id"] == id && r["status"] == "active" }
        return nil unless reminder

        reminder["status"] = "dismissed"
        save_reminders
        reminder
      end

      def fire!(id)
        reminder = @reminders.find { |r| r["id"] == id && r["status"] == "active" }
        return nil unless reminder

        reminder["status"] = "fired"
        save_reminders
        reminder
      end

      def due_reminders
        now = Time.now
        all_active.select { |r| Time.parse(r["due_at"]) <= now }
      end

      def all_active
        @reminders.select { |r| r["status"] == "active" }
      end

      def active_count
        all_active.length
      end

      private

      def reminders_path
        File.join(@reminders_dir, "reminders.jsonl")
      end

      def load_reminders
        path = reminders_path
        return [] unless File.exist?(path)

        raw = File.binread(path)

        if Encryption.encrypted?(raw)
          raise Kodo::Error, "Encrypted reminders file but no passphrase provided" unless @passphrase
          raw = Encryption.decrypt(raw, key: @passphrase)
        end

        raw.each_line.filter_map do |line|
          line = line.strip
          next if line.empty?
          JSON.parse(line)
        end
      rescue JSON::ParserError => e
        Kodo.logger.warn("Corrupt reminders file #{path}: #{e.message}")
        []
      end

      def save_reminders
        path = reminders_path
        jsonl = @reminders.map { |r| JSON.generate(r) }.join("\n") + "\n"

        if @passphrase
          File.binwrite(path, Encryption.encrypt(jsonl, key: @passphrase))
        else
          File.write(path, jsonl)
        end
      end
    end
  end
end
