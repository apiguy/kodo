# frozen_string_literal: true

RSpec.describe Kodo::Autonomy::Decision do
  it 'is a Data.define value object' do
    rule = Kodo::Autonomy::Rule.new(action: :test, level: :free, reason: 'test')
    decision = described_class.new(level: :free, reason: 'test reason', rule: rule)

    expect(decision.level).to eq(:free)
    expect(decision.reason).to eq('test reason')
    expect(decision.rule).to eq(rule)
  end

  it 'accepts nil rule' do
    decision = described_class.new(level: :propose, reason: 'no rule', rule: nil)

    expect(decision.rule).to be_nil
  end
end
