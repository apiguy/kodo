# frozen_string_literal: true

require 'ruby_llm'
require 'net/smtp'

module Kodo
  module Tools
    class SmtpSend < RubyLLM::Tool
      extend PromptContributor

      capability_name 'Email'
      capability_primary true
      enabled_guidance 'Use smtp_send to send emails from the agent email address.'
      disabled_guidance 'Email sending is not configured. Set agent.email and agent.email_provider in config.yml.'

      description 'Send an email. Uses the agent email address configured in config.yml.'
      param :to,      desc: 'Recipient email address'
      param :subject, desc: 'Email subject line'
      param :body,    desc: 'Email body (plain text)'

      MAX_PER_TURN = 3
      MAX_BODY_LENGTH = 5_000

      def initialize(audit:, smtp_config: {})
        super()
        @audit = audit
        @smtp_config = smtp_config
        @turn_count = 0
      end

      def reset_turn_count!
        @turn_count = 0
      end

      def execute(to:, subject:, body:)
        @turn_count += 1
        if @turn_count > MAX_PER_TURN
          return "Rate limit reached (max #{MAX_PER_TURN} emails per message). Try again next message."
        end

        from = Kodo.config.agent_email
        return 'Agent email not configured. Set agent.email in config.yml.' unless from

        return "Body too long (max #{MAX_BODY_LENGTH} chars)." if body.length > MAX_BODY_LENGTH

        send_email(from: from, to: to, subject: subject, body: body)

        @audit.log(
          event: 'email_sent',
          detail: "from:#{from} to:#{to} subject:#{subject.slice(0, 60)}"
        )

        "Email sent to #{to} with subject '#{subject}'."
      rescue Net::SMTPError, Net::SMTPFatalError, Net::SMTPSyntaxError => e
        "Failed to send email: #{e.message}"
      rescue StandardError => e
        "Email error: #{e.message}"
      end

      def name
        'smtp_send'
      end

      private

      def send_email(from:, to:, subject:, body:)
        message = build_message(from: from, to: to, subject: subject, body: body)

        smtp_host = @smtp_config[:host] || 'localhost'
        smtp_port = @smtp_config[:port] || 25
        smtp_user = @smtp_config[:user]
        smtp_pass = @smtp_config[:pass]

        Net::SMTP.start(smtp_host, smtp_port, 'localhost', smtp_user, smtp_pass) do |smtp|
          smtp.send_message(message, from, to)
        end
      end

      def build_message(from:, to:, subject:, body:)
        <<~MSG
          From: #{from}
          To: #{to}
          Subject: #{subject}
          Date: #{Time.now.strftime('%a, %d %b %Y %H:%M:%S %z')}
          Content-Type: text/plain; charset=UTF-8

          #{body}
        MSG
      end
    end
  end
end
