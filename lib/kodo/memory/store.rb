# frozen_string_literal: true

require "json"
require "fileutils"

module Kodo
  module Memory
    class Store
      MAX_CONTEXT_MESSAGES = 50  # Keep last N messages per conversation

      def initialize(passphrase: nil)
        @conversations = {}  # chat_id => Array<Hash>
        @conversations_dir = File.join(Kodo.home_dir, "memory", "conversations")
        @passphrase = passphrase
        FileUtils.mkdir_p(@conversations_dir)
      end

      # Append a message to a conversation
      def append(chat_id, role:, content:)
        chat_id = chat_id.to_s
        @conversations[chat_id] ||= load_conversation(chat_id)
        @conversations[chat_id] << {
          "role" => role,
          "content" => content,
          "timestamp" => Time.now.iso8601
        }

        # Trim to max context window
        if @conversations[chat_id].length > MAX_CONTEXT_MESSAGES
          @conversations[chat_id] = @conversations[chat_id].last(MAX_CONTEXT_MESSAGES)
        end

        save_conversation(chat_id)
      end

      # Get conversation history in LLM-ready format
      # Returns Array of {role: "user"|"assistant", content: String}
      def conversation(chat_id)
        chat_id = chat_id.to_s
        @conversations[chat_id] ||= load_conversation(chat_id)
        @conversations[chat_id].map do |msg|
          { role: msg["role"], content: msg["content"] }
        end
      end

      # Clear a conversation
      def clear(chat_id)
        chat_id = chat_id.to_s
        @conversations.delete(chat_id)
        path = conversation_path(chat_id)
        File.delete(path) if File.exist?(path)
      end

      private

      def conversation_path(chat_id)
        # Sanitize chat_id for filesystem safety
        safe_id = chat_id.gsub(/[^a-zA-Z0-9_\-]/, "_")
        File.join(@conversations_dir, "#{safe_id}.json")
      end

      def load_conversation(chat_id)
        path = conversation_path(chat_id)
        return [] unless File.exist?(path)

        raw = File.binread(path)

        # Transparent migration: detect encrypted files by magic header
        if Encryption.encrypted?(raw)
          raise Kodo::Error, "Encrypted conversation file but no passphrase provided" unless @passphrase
          raw = Encryption.decrypt(raw, key: @passphrase)
        end

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Kodo.logger.warn("Corrupt conversation file #{path}: #{e.message}")
        []
      end

      def save_conversation(chat_id)
        path = conversation_path(chat_id)

        # Redact sensitive data before writing to disk.
        # The in-memory array retains originals so the LLM has
        # access to secrets for the current session only.
        # Uses redact_smart: regex first, then LLM for context-dependent secrets.
        redacted = @conversations[chat_id].map do |msg|
          msg.merge("content" => Redactor.redact_smart(msg["content"]))
        end

        json = JSON.pretty_generate(redacted)

        if @passphrase
          File.binwrite(path, Encryption.encrypt(json, key: @passphrase))
        else
          File.write(path, json)
        end
      end
    end
  end
end
