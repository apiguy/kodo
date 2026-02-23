# frozen_string_literal: true

RSpec.describe Kodo::Autonomy::Policy do
  describe '#evaluate' do
    it 'returns :free for built-in read-only tools' do
      policy = described_class.new
      decision = policy.evaluate(action: :get_current_time)

      expect(decision.level).to eq(:free)
      expect(decision.reason).to include('Read-only')
    end

    it 'returns :free for memory tools' do
      policy = described_class.new
      %i[remember_fact forget_fact update_fact recall_facts].each do |action|
        decision = policy.evaluate(action: action)
        expect(decision.level).to eq(:free)
      end
    end

    it 'returns :free for web search and fetch' do
      policy = described_class.new
      %i[web_search fetch_url browse_web].each do |action|
        decision = policy.evaluate(action: action)
        expect(decision.level).to eq(:free)
      end
    end

    it 'returns :notify for store_secret' do
      policy = described_class.new
      decision = policy.evaluate(action: :store_secret)

      expect(decision.level).to eq(:notify)
    end

    it 'returns :propose for unknown actions' do
      policy = described_class.new
      decision = policy.evaluate(action: :unknown_action)

      expect(decision.level).to eq(:propose)
      expect(decision.reason).to include('No matching rule')
    end

    it 'accepts string action names' do
      policy = described_class.new
      decision = policy.evaluate(action: 'get_current_time')

      expect(decision.level).to eq(:free)
    end
  end

  describe 'config rules override built-in rules' do
    it 'uses config rule when it matches' do
      config_rules = [
        Kodo::Autonomy::Rule.new(action: :fetch_url, level: :never, reason: 'Blocked by config')
      ]
      policy = described_class.new(config_rules: config_rules)
      decision = policy.evaluate(action: :fetch_url)

      expect(decision.level).to eq(:never)
      expect(decision.reason).to eq('Blocked by config')
    end
  end

  describe 'persistent rules' do
    it 'uses persistent rules for matching actions' do
      persistent_rules = [
        Kodo::Autonomy::Rule.new(
          action: :smtp_send,
          scope: { to: 'user@example.com' },
          level: :free,
          reason: 'Previously approved'
        )
      ]
      policy = described_class.new(persistent_rules: persistent_rules)
      decision = policy.evaluate(action: :smtp_send, context: { to: 'user@example.com' })

      expect(decision.level).to eq(:free)
    end

    it 'config rules win over persistent rules with same specificity' do
      persistent_rules = [
        Kodo::Autonomy::Rule.new(action: :fetch_url, level: :free, reason: 'Approved')
      ]
      config_rules = [
        Kodo::Autonomy::Rule.new(action: :fetch_url, level: :never, reason: 'Config blocked')
      ]
      policy = described_class.new(persistent_rules: persistent_rules, config_rules: config_rules)
      decision = policy.evaluate(action: :fetch_url)

      # Both have empty scope (size 0), max_by returns last match (config is last in array)
      expect(decision.level).to eq(:never)
    end
  end

  describe 'scope specificity' do
    it 'prefers more specific scoped rules' do
      rules = [
        Kodo::Autonomy::Rule.new(action: :fetch_url, level: :propose, reason: 'Default'),
        Kodo::Autonomy::Rule.new(
          action: :fetch_url,
          scope: { domain: 'example.com' },
          level: :free,
          reason: 'Trusted domain'
        )
      ]
      policy = described_class.new(builtin_rules: rules)
      decision = policy.evaluate(action: :fetch_url, context: { domain: 'example.com' })

      expect(decision.level).to eq(:free)
      expect(decision.reason).to eq('Trusted domain')
    end
  end

  describe 'posture' do
    it 'balanced posture leaves levels unchanged' do
      policy = described_class.new(posture: :balanced)
      decision = policy.evaluate(action: :store_secret)

      expect(decision.level).to eq(:notify)
    end

    it 'conservative posture upgrades :notify to :propose' do
      policy = described_class.new(posture: :conservative)
      decision = policy.evaluate(action: :store_secret)

      expect(decision.level).to eq(:propose)
    end

    it 'conservative posture does not change :free' do
      policy = described_class.new(posture: :conservative)
      decision = policy.evaluate(action: :get_current_time)

      expect(decision.level).to eq(:free)
    end

    it 'autonomous posture downgrades :propose to :notify' do
      policy = described_class.new(posture: :autonomous)
      decision = policy.evaluate(action: :unknown_action)

      expect(decision.level).to eq(:notify)
    end

    it 'autonomous posture does not change :never' do
      rules = [
        Kodo::Autonomy::Rule.new(action: :danger, level: :never, reason: 'Forbidden')
      ]
      policy = described_class.new(builtin_rules: rules, posture: :autonomous)
      decision = policy.evaluate(action: :danger)

      expect(decision.level).to eq(:never)
    end

    it 'accepts string posture' do
      policy = described_class.new(posture: 'conservative')
      decision = policy.evaluate(action: :store_secret)

      expect(decision.level).to eq(:propose)
    end
  end
end
