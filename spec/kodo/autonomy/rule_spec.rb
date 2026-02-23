# frozen_string_literal: true

RSpec.describe Kodo::Autonomy::Rule do
  describe '#matches?' do
    it 'matches by exact action name' do
      rule = described_class.new(action: :fetch_url, level: :free, reason: 'test')
      expect(rule.matches?(:fetch_url, {})).to be true
    end

    it 'does not match a different action' do
      rule = described_class.new(action: :fetch_url, level: :free, reason: 'test')
      expect(rule.matches?(:web_search, {})).to be false
    end

    it 'matches string action names via to_sym' do
      rule = described_class.new(action: :fetch_url, level: :free, reason: 'test')
      expect(rule.matches?('fetch_url', {})).to be true
    end

    it 'matches :any action against all action names' do
      rule = described_class.new(action: :any, level: :never, reason: 'test')
      expect(rule.matches?(:fetch_url, {})).to be true
      expect(rule.matches?(:web_search, {})).to be true
    end

    it 'matches when scope is empty' do
      rule = described_class.new(action: :fetch_url, scope: {}, level: :free, reason: 'test')
      expect(rule.matches?(:fetch_url, { url: 'https://example.com' })).to be true
    end

    it 'matches when scope is nil' do
      rule = described_class.new(action: :fetch_url, scope: nil, level: :free, reason: 'test')
      expect(rule.matches?(:fetch_url, { url: 'https://example.com' })).to be true
    end

    it 'matches exact scope values' do
      rule = described_class.new(
        action: :fetch_url, scope: { domain: 'example.com' }, level: :free, reason: 'test'
      )
      expect(rule.matches?(:fetch_url, { domain: 'example.com' })).to be true
      expect(rule.matches?(:fetch_url, { domain: 'other.com' })).to be false
    end

    it 'matches wildcard suffix patterns' do
      rule = described_class.new(
        action: :fetch_url, scope: { url: '*.example.com' }, level: :free, reason: 'test'
      )
      expect(rule.matches?(:fetch_url, { url: 'api.example.com' })).to be true
      expect(rule.matches?(:fetch_url, { url: 'evil.com' })).to be false
    end

    it 'matches the * wildcard pattern' do
      rule = described_class.new(
        action: :fetch_url, scope: { url: '*' }, level: :free, reason: 'test'
      )
      expect(rule.matches?(:fetch_url, { url: 'anything.com' })).to be true
    end

    it 'returns false when scope key is missing from context' do
      rule = described_class.new(
        action: :fetch_url, scope: { domain: 'example.com' }, level: :free, reason: 'test'
      )
      expect(rule.matches?(:fetch_url, {})).to be false
    end

    it 'requires all scope entries to match' do
      rule = described_class.new(
        action: :fetch_url,
        scope: { domain: 'example.com', method: 'GET' },
        level: :free, reason: 'test'
      )
      expect(rule.matches?(:fetch_url, { domain: 'example.com', method: 'GET' })).to be true
      expect(rule.matches?(:fetch_url, { domain: 'example.com', method: 'POST' })).to be false
    end
  end

  describe 'defaults' do
    it 'defaults scope to empty hash' do
      rule = described_class.new(action: :test, level: :free, reason: 'test')
      expect(rule.scope).to eq({})
    end

    it 'defaults granted_at and granted_via to nil' do
      rule = described_class.new(action: :test, level: :free, reason: 'test')
      expect(rule.granted_at).to be_nil
      expect(rule.granted_via).to be_nil
    end
  end
end
