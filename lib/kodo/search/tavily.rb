# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Kodo
  module Search
    class Tavily < Base
      API_URL = 'https://api.tavily.com/search'
      READ_TIMEOUT = 15
      OPEN_TIMEOUT = 10

      def initialize(api_key:)
        super()
        @api_key = api_key
      end

      def search(query, max_results: 5)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = READ_TIMEOUT
        http.open_timeout = OPEN_TIMEOUT

        request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        request.body = JSON.generate(
          api_key: @api_key,
          query: query,
          max_results: max_results,
          include_answer: false
        )

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Kodo::Error, "Tavily API error: #{response.code} #{response.message}"
        end

        data = JSON.parse(response.body)
        results = data['results'] || []

        results.map do |r|
          Result.new(
            title: r['title'] || '',
            url: r['url'] || '',
            snippet: r['content'] || '',
            content: r['raw_content']
          )
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Kodo::Error, "Tavily API timeout: #{e.message}"
      rescue JSON::ParserError => e
        raise Kodo::Error, "Tavily API returned invalid JSON: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED => e
        raise Kodo::Error, "Tavily API connection failed: #{e.message}"
      end
    end
  end
end
