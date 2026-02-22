# frozen_string_literal: true

require 'uri'
require 'resolv'
require 'ipaddr'

module Kodo
  module Web
    # Shared URL security checks included by FetchUrl, BrowseWeb, and PlaywrightCommand.
    # Provides a single #validate_url! entry point that enforces scheme, SSRF, domain
    # policy, and secret-exfiltration checks, raising Kodo::Error on violation.
    module UrlValidator
      # RFC 1918, loopback, link-local, and other non-routable ranges
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

      # Validate a URL string and return a URI object.
      # Raises Kodo::Error with a descriptive message on any violation.
      def validate_url!(url_string, sensitive_values_fn: nil)
        uri = URI.parse(url_string)
        raise Kodo::Error, 'Only http and https URLs are supported.' unless
          %w[http https].include?(uri.scheme)

        check_secret_exfiltration!(url_string, sensitive_values_fn)
        check_domain_policy!(uri.host)
        check_ssrf!(uri.host)
        uri
      rescue URI::InvalidURIError
        raise Kodo::Error, 'Invalid URL format.'
      end

      private

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

      def check_secret_exfiltration!(url_string, sensitive_values_fn)
        return unless sensitive_values_fn

        sensitive_values_fn.call.each do |secret|
          next if secret.nil? || secret.length < 8

          if url_string.include?(secret)
            raise Kodo::Error, 'URL contains a stored secret — fetch blocked to prevent exfiltration.'
          end
        end
      end

      def domain_matches?(hostname, pattern)
        if pattern.start_with?('*.')
          suffix = pattern[1..] # e.g. ".example.com"
          hostname == pattern[2..] || hostname.end_with?(suffix)
        else
          hostname == pattern
        end
      end
    end
  end
end
