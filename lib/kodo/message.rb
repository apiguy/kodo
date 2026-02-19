# frozen_string_literal: true

module Kodo
  Message = Data.define(
    :id,
    :channel_id,
    :sender,       # :user, :agent, :system
    :content,
    :timestamp,
    :metadata      # Hash — channel-specific extras
  ) do
    def initialize(id: SecureRandom.uuid, channel_id:, sender:, content:, timestamp: Time.now, metadata: {})
      super
    end

    def from_user? = sender == :user
    def from_agent? = sender == :agent
    def from_system? = sender == :system

    # Convert to the format expected by LLM providers
    def to_llm_message
      role = from_user? ? "user" : "assistant"
      { role: role, content: content }
    end
  end
end
