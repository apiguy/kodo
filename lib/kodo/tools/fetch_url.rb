# frozen_string_literal: true

require 'ruby_llm'
require 'net/http'
require 'uri'
require 'resolv'
require 'ipaddr'

module Kodo
  module Tools
    class FetchUrl < RubyLLM::Tool
      extend PromptContributor

      capability_name 'URL Fetch'
      capability_primary true
      enabled_guidance 'Read the contents of a specific URL the user provides.'
      disabled_guidance 'URL fetching is disabled. Set web.fetch_url_enabled: true in ~/.kodo/config.yml.'

      MAX_PER_TURN = 3
      MAX_CONTENT_LENGTH = 50_000
      MAX_REDIRECTS = 5
      READ_TIMEOUT = 15
      OPEN_TIMEOUT = 10
      USER_AGENT = "Kodo/#{VERSION} (bot; +https://kodo.bot)".freeze

      # RFC 1918, loopback, link-local
      BLOCKED_RANGES = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('169.254.0.0/16'),
        IPAddr.new('0.0.0.0/8'),
        IPAddr.new('::1/128'),
        IPAddr.new('fc00::/7'),
        IPAddr.new('fe80::/10')
      ].freeze

      description 'Fetch and read the contents of a web page. Use this to read articles, ' \
                  'documentation, or any publicly accessible URL the user provides.'

      param :url, desc: 'The URL to fetch (http or https only)'

      attr_writer :turn_context

      def initialize(audit:)
        super()
        @audit = audit
        @turn_count = 0
        @turn_context = nil
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(url:)
        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} fetches per message). Try again next message."
        end

        uri = validate_url(url)
        return uri if uri.is_a?(String) # error message

        content = fetch_with_redirects(uri)
        return content if content.is_a?(String) && content.start_with?('Error:')

        text = extract_text(content)
        text = text[0...MAX_CONTENT_LENGTH] if text.length > MAX_CONTENT_LENGTH

        # Audit-log injection signals (detection only — not a security boundary)
        if Kodo.config.web_injection_scan?
          scan = Web::InjectionScanner.scan(text)
          if scan.suspicious?
            @audit.log(
              event: 'injection_suspected',
              detail: "url:#{Kodo.config.web_audit_urls? ? url : '[redacted]'} signals:#{scan.signal_count}"
            )
          end
        end

        audit_url = Kodo.config.web_audit_urls? ? url : '[redacted]'
        @audit.log(
          event: 'url_fetched',
          detail: "url:#{audit_url} len:#{text.length}"
        )

        # Mark that web content was fetched this turn (used by RememberFact gate)
        @turn_context&.web_fetched!

        result = text.empty? ? "No readable content found at #{url}" : text
        wrap_as_untrusted(url, result)
      rescue Kodo::Error => e
        e.message
      end

      def name
        'fetch_url'
      end

      private

      def wrap_as_untrusted(url, text)
        nonce = @turn_context&.nonce || 'no-nonce'
        # If the content somehow contains our nonce, replace it (near-impossible but defensive)
        safe_text = text.gsub(nonce, '[nonce-collision-redacted]')
        <<~CONTENT
          [WEB:#{nonce}:START]
          Source: #{url}
          ---
          #{safe_text}
          ---
          [WEB:#{nonce}:END]
        CONTENT
      end

      def validate_url(url)
        uri = URI.parse(url)
        return 'Error: Only http and https URLs are supported.' unless %w[http https].include?(uri.scheme)

        check_domain_policy!(uri.host)
        check_ssrf!(uri.host)
        uri
      rescue URI::InvalidURIError
        'Error: Invalid URL format.'
      rescue Kodo::Error => e
        "Error: #{e.message}"
      end

      def check_domain_policy!(hostname)
        blocklist = Kodo.config.web_fetch_blocklist
        if blocklist.any? { |pattern| domain_matches?(hostname, pattern) }
          raise Kodo::Error, "#{hostname} is blocked by fetch_blocklist policy."
        end

        allowlist = Kodo.config.web_fetch_allowlist
        return if allowlist.empty?

        return if allowlist.any? { |pattern| domain_matches?(hostname, pattern) }

        raise Kodo::Error, "#{hostname} is not in the fetch_allowlist."
      end

      def domain_matches?(hostname, pattern)
        if pattern.start_with?('*.')
          suffix = pattern[1..] # e.g. ".example.com"
          hostname == pattern[2..] || hostname.end_with?(suffix)
        else
          hostname == pattern
        end
      end

      def check_ssrf!(hostname)
        return if Kodo.config.web_ssrf_bypass_hosts.include?(hostname)

        addresses = Resolv.getaddresses(hostname)

        raise Kodo::Error, "Could not resolve hostname: #{hostname}" if addresses.empty?

        addresses.each do |addr|
          ip = IPAddr.new(addr)
          if BLOCKED_RANGES.any? { |range| range.include?(ip) }
            raise Kodo::Error, 'Access to private/internal network addresses is not allowed.'
          end
        end
      end

      def fetch_with_redirects(uri, redirects_remaining = MAX_REDIRECTS)
        check_ssrf!(uri.host)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = READ_TIMEOUT
        http.open_timeout = OPEN_TIMEOUT

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = USER_AGENT

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          response.body || ''
        elsif response.is_a?(Net::HTTPRedirection)
          return 'Error: Too many redirects.' if redirects_remaining <= 0

          location = response['location']
          return 'Error: Redirect with no location header.' unless location

          redirect_uri = URI.parse(location)
          # Handle relative redirects
          redirect_uri = uri + location unless redirect_uri.host

          return 'Error: Redirect to non-HTTP scheme.' unless %w[http https].include?(redirect_uri.scheme)

          fetch_with_redirects(redirect_uri, redirects_remaining - 1)
        else
          "Error: HTTP #{response.code} #{response.message}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout
        'Error: Request timed out.'
      rescue SocketError, Errno::ECONNREFUSED => e
        "Error: Connection failed: #{e.message}"
      rescue Kodo::Error => e
        "Error: #{e.message}"
      end

      def extract_text(html)
        return '' if html.nil? || html.empty?

        text = html.dup

        # Remove script and style blocks
        text.gsub!(%r{<script[^>]*>.*?</script>}mi, '')
        text.gsub!(%r{<style[^>]*>.*?</style>}mi, '')

        # Remove HTML comments
        text.gsub!(/<!--.*?-->/m, '')

        # Convert block-level tags to newlines
        text.gsub!(%r{<(?:br|p|div|h[1-6]|li|tr|blockquote|hr)[^>]*/?>}i, "\n")
        text.gsub!(%r{</(?:p|div|h[1-6]|li|tr|blockquote|table|ul|ol)>}i, "\n")

        # Strip remaining tags
        text.gsub!(/<[^>]+>/, '')

        # Decode common HTML entities
        text.gsub!('&amp;', '&')
        text.gsub!('&lt;', '<')
        text.gsub!('&gt;', '>')
        text.gsub!('&quot;', '"')
        text.gsub!('&#39;', "'")
        text.gsub!('&apos;', "'")
        text.gsub!('&nbsp;', ' ')

        # Normalize whitespace
        text.gsub!(/[ \t]+/, ' ')
        text.gsub!(/\n[ \t]+/, "\n")
        text.gsub!(/[ \t]+\n/, "\n")
        text.gsub!(/\n{3,}/, "\n\n")
        text.strip!

        text
      end
    end
  end
end
