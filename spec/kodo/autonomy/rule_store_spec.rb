# frozen_string_literal: true

RSpec.describe Kodo::Autonomy::RuleStore, :tmpdir do
  let(:tmpdir) { @tmpdir }

  before do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, 'memory', 'autonomy'))
  end

  let(:store) { described_class.new }

  describe '#add' do
    it 'adds a rule and returns it' do
      rule = store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test')

      expect(rule).to be_a(Kodo::Autonomy::Rule)
      expect(rule.action).to eq(:fetch_url)
      expect(rule.level).to eq(:free)
      expect(rule.reason).to eq('test')
    end

    it 'persists rules to disk' do
      store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test')

      reloaded = described_class.new
      expect(reloaded.active_rules.length).to eq(1)
      expect(reloaded.active_rules.first.action).to eq(:fetch_url)
    end

    it 'sets granted_at and granted_via' do
      rule = store.add(action: :test, scope: {}, level: :free, reason: 'test', granted_via: 'chat')

      expect(rule.granted_at).not_to be_nil
      expect(rule.granted_via).to eq('chat')
    end

    it 'raises when at max capacity' do
      allow(store).to receive(:save_rules)
      Kodo::Autonomy::RuleStore::MAX_RULES.times do |i|
        store.instance_variable_get(:@rules) << { 'active' => true, 'id' => i.to_s }
      end

      expect do
        store.add(action: :test, scope: {}, level: :free, reason: 'test')
      end.to raise_error(Kodo::Error, /full/)
    end
  end

  describe '#revoke' do
    it 'deactivates a rule by id' do
      rule = store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test')
      raw = store.instance_variable_get(:@rules).find { |r| r['action'] == 'fetch_url' }

      store.revoke(raw['id'])

      expect(store.active_rules).to be_empty
    end

    it 'returns nil for unknown id' do
      expect(store.revoke('nonexistent')).to be_nil
    end

    it 'persists revocation to disk' do
      store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test')
      raw = store.instance_variable_get(:@rules).first
      store.revoke(raw['id'])

      reloaded = described_class.new
      expect(reloaded.active_rules).to be_empty
    end
  end

  describe '#increment_approval' do
    it 'increments the approval count for a matching rule' do
      store.add(action: :fetch_url, scope: {}, level: :notify, reason: 'test')

      result = store.increment_approval(:fetch_url, {})
      expect(result['approval_count']).to eq(2)
    end

    it 'returns nil when no matching rule exists' do
      expect(store.increment_approval(:nonexistent, {})).to be_nil
    end
  end

  describe '#active_rules' do
    it 'returns only active rules as Rule objects' do
      store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test1')
      store.add(action: :web_search, scope: {}, level: :notify, reason: 'test2')
      raw = store.instance_variable_get(:@rules).first
      store.revoke(raw['id'])

      active = store.active_rules
      expect(active.length).to eq(1)
      expect(active.first.action).to eq(:web_search)
    end
  end

  describe '#ratchet_candidates' do
    it 'returns rules with approval_count at or above threshold' do
      store.add(action: :fetch_url, scope: {}, level: :notify, reason: 'test')
      # Manually set approval count high
      store.instance_variable_get(:@rules).first['approval_count'] = 5

      candidates = store.ratchet_candidates(threshold: 5)
      expect(candidates.length).to eq(1)
      expect(candidates.first['action']).to eq('fetch_url')
    end

    it 'excludes rules already at :free level' do
      store.add(action: :fetch_url, scope: {}, level: :free, reason: 'test')
      store.instance_variable_get(:@rules).first['approval_count'] = 10

      candidates = store.ratchet_candidates(threshold: 5)
      expect(candidates).to be_empty
    end
  end
end
