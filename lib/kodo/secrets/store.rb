# frozen_string_literal: true

require 'json'
require 'fileutils'

module Kodo
  module Secrets
    class Store
      def initialize(passphrase:, secrets_dir: nil)
        @secrets_dir = secrets_dir || Kodo.home_dir
        @passphrase = passphrase
        FileUtils.mkdir_p(@secrets_dir)
        @secrets = load_secrets
      end

      def put(name, value, source: 'user', validated: false)
        @secrets[name] = {
          'value' => value,
          'source' => source,
          'validated' => validated,
          'stored_at' => Time.now.iso8601
        }
        save_secrets
        @secrets[name]
      end

      def get(name)
        entry = @secrets[name]
        entry&.fetch('value', nil)
      end

      def exists?(name)
        @secrets.key?(name)
      end

      def delete(name)
        removed = @secrets.delete(name)
        save_secrets if removed
        !removed.nil?
      end

      def names
        @secrets.keys
      end

      private

      def secrets_path
        File.join(@secrets_dir, 'secrets.enc')
      end

      def load_secrets
        path = secrets_path
        return {} unless File.exist?(path)

        raw = File.binread(path)

        raw = Memory::Encryption.decrypt(raw, key: @passphrase) if Memory::Encryption.encrypted?(raw)

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Kodo.logger.warn("Corrupt secrets file #{path}: #{e.message}")
        {}
      end

      def save_secrets
        json = JSON.generate(@secrets)
        File.binwrite(secrets_path, Memory::Encryption.encrypt(json, key: @passphrase))
      end
    end
  end
end
