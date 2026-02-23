# frozen_string_literal: true

RSpec.describe Kodo::Tools::ApproveAction, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }
  let(:on_rule_added) { instance_double(Proc, call: nil) }

  let(:rule_store) do
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, 'memory', 'autonomy'))
    Kodo::Autonomy::RuleStore.new
  end

  let(:tool) do
    described_class.new(rule_store: rule_store, audit: audit, on_rule_added: on_rule_added)
  end

  describe '#execute' do
    it 'registers an approval and returns confirmation' do
      result = tool.execute(action: 'fetch_url')

      expect(result).to include('Approval registered')
      expect(result).to include('fetch_url')
    end

    it 'stores a persistent rule in the rule store' do
      tool.execute(action: 'fetch_url', scope: { 'domain' => 'example.com' })

      rules = rule_store.active_rules
      expect(rules.length).to eq(1)
      expect(rules.first.action).to eq(:fetch_url)
      expect(rules.first.level).to eq(:free)
    end

    it 'calls the on_rule_added callback' do
      tool.execute(action: 'fetch_url')

      expect(on_rule_added).to have_received(:call)
    end

    it 'logs the approval to audit' do
      tool.execute(action: 'fetch_url')

      expect(audit).to have_received(:log).with(
        event: 'autonomy_approval',
        detail: a_string_including('fetch_url')
      )
    end

    it 'accepts "notify" as a level' do
      result = tool.execute(action: 'smtp_send', level: 'notify')

      expect(result).to include('level: notify')
      expect(rule_store.active_rules.first.level).to eq(:notify)
    end

    it 'rejects invalid levels' do
      result = tool.execute(action: 'fetch_url', level: 'never')

      expect(result).to include("Invalid level")
      expect(rule_store.active_rules).to be_empty
    end

    it 'parses JSON string scope' do
      result = tool.execute(action: 'fetch_url', scope: '{"domain": "example.com"}')

      expect(result).to include('Approval registered')
      rules = rule_store.active_rules
      expect(rules.first.scope).to eq({ domain: 'example.com' })
    end

    it 'handles invalid JSON scope gracefully' do
      result = tool.execute(action: 'fetch_url', scope: 'not json')

      expect(result).to include('Invalid scope')
    end

    it 'enforces rate limit' do
      3.times { |i| tool.execute(action: "action_#{i}") }
      result = tool.execute(action: 'action_4')

      expect(result).to include('Rate limit')
    end

    it 'resets rate limit on reset_turn_count!' do
      3.times { |i| tool.execute(action: "action_#{i}") }
      tool.reset_turn_count!
      result = tool.execute(action: 'action_4')

      expect(result).to include('Approval registered')
    end
  end

  describe '#name' do
    it 'returns approve_action' do
      expect(tool.name).to eq('approve_action')
    end
  end
end
