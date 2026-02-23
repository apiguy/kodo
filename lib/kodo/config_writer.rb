# frozen_string_literal: true

require 'yaml'

module Kodo
  class ConfigWriter
    def initialize(path = Config.config_path)
      @path = path
    end

    def update(key_path, value)
      data = load_data
      set_nested(data, key_path.split('.'), value)
      File.write(@path, YAML.dump(data))
    end

    def read(key_path)
      data = load_data
      dig_nested(data, key_path.split('.'))
    end

    private

    def load_data
      File.exist?(@path) ? (YAML.safe_load_file(@path) || {}) : {}
    end

    def set_nested(hash, keys, value)
      key = keys.first
      if keys.length == 1
        hash[key] = value
      else
        hash[key] ||= {}
        set_nested(hash[key], keys[1..], value)
      end
    end

    def dig_nested(hash, keys)
      keys.reduce(hash) { |h, k| h.is_a?(Hash) ? h[k] : nil }
    end
  end
end
