# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'fileutils'

module Kodo
  module Autonomy
    class RuleStore
      MAX_RULES = 200

      def initialize(passphrase: nil)
        @rules_dir = File.join(Kodo.home_dir, 'memory', 'autonomy')
        @passphrase = passphrase
        FileUtils.mkdir_p(@rules_dir)
        @rules = load_rules
      end

      def add(action:, scope:, level:, reason:, granted_via: 'chat')
        if @rules.count { |r| r['active'] } >= MAX_RULES
          raise Kodo::Error, "Autonomy rule store is full (#{MAX_RULES} rules). Revoke some rules first."
        end

        rule_data = {
          'id' => SecureRandom.uuid,
          'action' => action.to_s,
          'scope' => scope || {},
          'level' => level.to_s,
          'reason' => reason,
          'granted_at' => Time.now.iso8601,
          'granted_via' => granted_via,
          'active' => true,
          'approval_count' => 1
        }
        @rules << rule_data
        save_rules
        to_rule(rule_data)
      end

      def revoke(id)
        rule = @rules.find { |r| r['id'] == id }
        return nil unless rule

        rule['active'] = false
        save_rules
        rule
      end

      def increment_approval(action, scope)
        matching = @rules.find do |r|
          r['active'] && r['action'] == action.to_s && (r['scope'] || {}) == (scope || {})
        end
        return nil unless matching

        matching['approval_count'] = (matching['approval_count'] || 1) + 1
        save_rules
        matching
      end

      def active_rules
        @rules.select { |r| r['active'] }.map { |r| to_rule(r) }
      end

      def ratchet_candidates(threshold: 5)
        @rules.select { |r| r['active'] && (r['approval_count'] || 0) >= threshold && r['level'] != 'free' }
      end

      private

      def to_rule(data)
        Autonomy::Rule.new(
          action: data['action'].to_sym,
          scope: (data['scope'] || {}).transform_keys(&:to_sym),
          level: data['level'].to_sym,
          reason: data['reason'],
          granted_at: data['granted_at'],
          granted_via: data['granted_via']
        )
      end

      def rules_path
        File.join(@rules_dir, 'rules.jsonl')
      end

      def load_rules
        path = rules_path
        return [] unless File.exist?(path)

        raw = File.binread(path)

        if Memory::Encryption.encrypted?(raw)
          raise Kodo::Error, 'Encrypted autonomy rules file but no passphrase provided' unless @passphrase

          raw = Memory::Encryption.decrypt(raw, key: @passphrase)
        end

        raw.each_line.filter_map do |line|
          line = line.strip
          next if line.empty?

          JSON.parse(line)
        end
      rescue JSON::ParserError => e
        Kodo.logger.warn("Corrupt autonomy rules file #{path}: #{e.message}")
        []
      end

      def save_rules
        path = rules_path
        jsonl = @rules.map { |r| JSON.generate(r) }.join("\n") + "\n"

        if @passphrase
          File.binwrite(path, Memory::Encryption.encrypt(jsonl, key: @passphrase))
        else
          File.write(path, jsonl)
        end
      end
    end
  end
end
