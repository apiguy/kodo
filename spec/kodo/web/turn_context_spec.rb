# frozen_string_literal: true

RSpec.describe Kodo::Web::TurnContext do
  subject(:ctx) { described_class.new }

  describe '#nonce' do
    it 'generates a hex string' do
      expect(ctx.nonce).to match(/\A[0-9a-f]+\z/)
    end

    it 'is 24 chars (96 bits as hex)' do
      expect(ctx.nonce.length).to eq(24)
    end

    it 'is unique per instance' do
      other = described_class.new
      expect(ctx.nonce).not_to eq(other.nonce)
    end
  end

  describe '#web_fetched' do
    it 'starts as false' do
      expect(ctx.web_fetched).to be false
    end

    it 'becomes true after web_fetched!' do
      ctx.web_fetched!
      expect(ctx.web_fetched).to be true
    end

    it 'stays true after multiple web_fetched! calls' do
      ctx.web_fetched!
      ctx.web_fetched!
      expect(ctx.web_fetched).to be true
    end
  end
end
