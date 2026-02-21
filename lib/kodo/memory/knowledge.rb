# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"

module Kodo
  module Memory
    class Knowledge
      MAX_FACTS = 500
      MAX_PROMPT_CHARS = 5_000
      VALID_CATEGORIES = %w[preference fact instruction context].freeze

      def initialize(passphrase: nil)
        @knowledge_dir = File.join(Kodo.home_dir, "memory", "knowledge")
        @passphrase = passphrase
        FileUtils.mkdir_p(@knowledge_dir)
        @facts = load_facts
      end

      def remember(category:, content:, source: "explicit")
        unless VALID_CATEGORIES.include?(category)
          raise Kodo::Error, "Invalid category: #{category}. Must be one of: #{VALID_CATEGORIES.join(', ')}"
        end

        if count >= MAX_FACTS
          raise Kodo::Error, "Knowledge store is full (#{MAX_FACTS} facts). Forget some facts first."
        end

        now = Time.now.iso8601
        fact = {
          "id" => SecureRandom.uuid,
          "category" => category,
          "content" => content,
          "source" => source,
          "created_at" => now,
          "updated_at" => now,
          "supersedes" => nil,
          "active" => true
        }

        @facts << fact
        save_facts
        fact
      end

      def forget(id)
        fact = @facts.find { |f| f["id"] == id && f["active"] }
        return nil unless fact

        fact["active"] = false
        fact["updated_at"] = Time.now.iso8601
        save_facts
        fact
      end

      def all_active
        @facts.select { |f| f["active"] }
      end

      def recall(query: nil, category: nil)
        results = all_active

        if category
          results = results.select { |f| f["category"] == category }
        end

        if query
          pattern = query.downcase
          results = results.select { |f| f["content"].downcase.include?(pattern) }
        end

        results
      end

      def count
        all_active.length
      end

      def for_prompt
        active = all_active
        return nil if active.empty?

        grouped = active.group_by { |f| f["category"] }
        lines = ["## What You Know About the User\n"]

        VALID_CATEGORIES.each do |cat|
          facts = grouped[cat]
          next unless facts&.any?

          lines << "### #{cat.capitalize}s"
          facts.each { |f| lines << "- #{f['content']}" }
          lines << ""
        end

        result = lines.join("\n")
        if result.length > MAX_PROMPT_CHARS
          result = result[0...MAX_PROMPT_CHARS] + "\n\n_[Knowledge truncated]_"
        end
        result
      end

      private

      def knowledge_path
        File.join(@knowledge_dir, "global.jsonl")
      end

      def load_facts
        path = knowledge_path
        return [] unless File.exist?(path)

        raw = File.binread(path)

        if Encryption.encrypted?(raw)
          raise Kodo::Error, "Encrypted knowledge file but no passphrase provided" unless @passphrase
          raw = Encryption.decrypt(raw, key: @passphrase)
        end

        raw.each_line.filter_map do |line|
          line = line.strip
          next if line.empty?
          JSON.parse(line)
        end
      rescue JSON::ParserError => e
        Kodo.logger.warn("Corrupt knowledge file #{path}: #{e.message}")
        []
      end

      def save_facts
        path = knowledge_path
        jsonl = @facts.map { |f| JSON.generate(f) }.join("\n") + "\n"

        if @passphrase
          File.binwrite(path, Encryption.encrypt(jsonl, key: @passphrase))
        else
          File.write(path, jsonl)
        end
      end
    end
  end
end
