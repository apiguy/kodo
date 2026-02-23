# frozen_string_literal: true

RSpec.describe Kodo::Autonomy::Gated do
  # Create a minimal tool-like class for testing
  let(:tool_class) do
    Class.new do
      def name
        'test_tool'
      end

      def call(args = {})
        execute(**args.transform_keys(&:to_sym))
      end

      def execute(**_args)
        'executed successfully'
      end
    end
  end

  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }

  def build_gated_tool(policy)
    tool = tool_class.new
    tool.singleton_class.prepend(described_class)
    tool.autonomy_policy = policy
    tool.autonomy_audit = audit
    tool
  end

  describe '#call' do
    context 'when level is :free' do
      it 'executes the tool normally' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :free, reason: 'Safe')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        result = tool.call({})
        expect(result).to eq('executed successfully')
      end

      it 'logs the autonomy check' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :free, reason: 'Safe')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        tool.call({})
        expect(audit).to have_received(:log).with(
          event: 'autonomy_check',
          detail: a_string_including('test_tool', 'free')
        )
      end
    end

    context 'when level is :notify' do
      it 'executes the tool normally' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :notify, reason: 'Log it')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        result = tool.call({})
        expect(result).to eq('executed successfully')
      end
    end

    context 'when level is :propose' do
      it 'returns guidance instead of executing' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :propose, reason: 'Needs approval')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        result = tool.call({})
        expect(result).to include('requires user approval')
        expect(result).to include('Needs approval')
      end

      it 'does not execute the underlying tool' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :propose, reason: 'Needs approval')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        allow(tool).to receive(:execute)
        tool.call({})
        expect(tool).not_to have_received(:execute)
      end
    end

    context 'when level is :never' do
      it 'returns refusal string' do
        rules = [Kodo::Autonomy::Rule.new(action: :test_tool, level: :never, reason: 'Forbidden')]
        policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
        tool = build_gated_tool(policy)

        result = tool.call({})
        expect(result).to include('not permitted')
        expect(result).to include('Forbidden')
      end
    end

    context 'when no policy is set' do
      it 'executes normally (bypass)' do
        tool = tool_class.new
        tool.singleton_class.prepend(described_class)

        result = tool.call({})
        expect(result).to eq('executed successfully')
      end
    end

    it 'passes args to the policy for scoped evaluation' do
      rules = [
        Kodo::Autonomy::Rule.new(
          action: :test_tool,
          scope: { target: 'allowed' },
          level: :free,
          reason: 'Scoped allow'
        )
      ]
      policy = Kodo::Autonomy::Policy.new(builtin_rules: rules)
      tool = build_gated_tool(policy)

      # With matching scope → free → executes
      result = tool.call('target' => 'allowed')
      expect(result).to eq('executed successfully')

      # Without matching scope → default propose
      result2 = tool.call('target' => 'other')
      expect(result2).to include('requires user approval')
    end
  end
end
