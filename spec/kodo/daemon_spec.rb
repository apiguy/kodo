# frozen_string_literal: true

require 'logger'

RSpec.describe Kodo::Daemon, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:config) { Kodo::Config.new(Kodo::Config::DEFAULTS) }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }
  let(:broker) { instance_double(Kodo::Secrets::Broker, available?: false, fetch: nil) }
  let(:router) { instance_double(Kodo::Router, reload_tools!: nil) }

  before do
    allow(Kodo).to receive(:config).and_return(config)
    allow(Kodo).to receive(:reload_config!).and_return(config)
    allow(Kodo).to receive(:logger).and_return(logger)
    allow(Kodo).to receive(:home_dir).and_return(tmpdir)
    allow(Kodo::LLM).to receive(:configure!)
  end

  let(:daemon) do
    d = described_class.new(config: config)
    d.instance_variable_set(:@audit, audit)
    d.instance_variable_set(:@broker, broker)
    d.instance_variable_set(:@router, router)
    d
  end

  describe '#reload!' do
    it 're-reads config, reconfigures LLM, and reloads tools' do
      daemon.send(:reload!)

      expect(Kodo).to have_received(:reload_config!)
      expect(Kodo::LLM).to have_received(:configure!).with(config, broker: broker)
      expect(router).to have_received(:reload_tools!)
      expect(audit).to have_received(:log).with(event: 'config_reloaded')
    end

    it 'logs errors without raising' do
      d = daemon
      allow(Kodo).to receive(:reload_config!).and_raise(StandardError, 'disk error')

      d.send(:reload!)

      expect(logger).to have_received(:error).with(/Config reload failed: disk error/)
    end
  end

  describe '#reconcile_channels!' do
    context 'when telegram becomes enabled and no existing channel' do
      let(:telegram_config) do
        Kodo::Config.new(
          Kodo::Config::DEFAULTS.merge(
            'channels' => { 'telegram' => { 'enabled' => true, 'bot_token_env' => 'TELEGRAM_BOT_TOKEN' } }
          )
        )
      end

      let(:telegram_channel) do
        instance_double(Kodo::Channels::Telegram, channel_id: 'telegram', connect!: nil, running?: true)
      end

      before do
        allow(Kodo).to receive(:config).and_return(telegram_config)
        allow(broker).to receive(:available?).with('telegram_bot_token').and_return(true)
        allow(broker).to receive(:fetch).with('telegram_bot_token', requestor: 'telegram').and_return('test-token')
        allow(Kodo::Channels::Telegram).to receive(:new).and_return(telegram_channel)
      end

      it 'connects Telegram when enabled with token available via broker' do
        daemon.send(:reconcile_channels!)

        expect(Kodo::Channels::Telegram).to have_received(:new).with(bot_token: 'test-token')
        expect(telegram_channel).to have_received(:connect!)
        expect(daemon.channels).to include(telegram_channel)
        expect(logger).to have_received(:info).with('Telegram channel connected')
      end
    end

    context 'when telegram becomes enabled with token from ENV' do
      let(:telegram_config) do
        Kodo::Config.new(
          Kodo::Config::DEFAULTS.merge(
            'channels' => { 'telegram' => { 'enabled' => true, 'bot_token_env' => 'TELEGRAM_BOT_TOKEN' } }
          )
        )
      end

      let(:telegram_channel) do
        instance_double(Kodo::Channels::Telegram, channel_id: 'telegram', connect!: nil, running?: true)
      end

      before do
        allow(Kodo).to receive(:config).and_return(telegram_config)
        allow(broker).to receive(:available?).with('telegram_bot_token').and_return(false)
        allow(telegram_config).to receive(:telegram_bot_token).and_return('env-token')
        allow(Kodo::Channels::Telegram).to receive(:new).and_return(telegram_channel)
      end

      it 'falls back to ENV token when broker has none' do
        daemon.send(:reconcile_channels!)

        expect(Kodo::Channels::Telegram).to have_received(:new).with(bot_token: 'env-token')
        expect(telegram_channel).to have_received(:connect!)
      end
    end

    context 'when telegram should be disabled and channel exists' do
      let(:telegram_channel) do
        instance_double(Kodo::Channels::Telegram, channel_id: 'telegram', disconnect!: nil, running?: true)
      end

      it 'disconnects and removes the Telegram channel' do
        daemon.channels << telegram_channel

        daemon.send(:reconcile_channels!)

        expect(telegram_channel).to have_received(:disconnect!)
        expect(daemon.channels).not_to include(telegram_channel)
        expect(logger).to have_received(:info).with('Telegram channel disconnected')
      end
    end

    context 'when connection fails' do
      let(:telegram_config) do
        Kodo::Config.new(
          Kodo::Config::DEFAULTS.merge(
            'channels' => { 'telegram' => { 'enabled' => true, 'bot_token_env' => 'TELEGRAM_BOT_TOKEN' } }
          )
        )
      end

      before do
        allow(Kodo).to receive(:config).and_return(telegram_config)
        allow(broker).to receive(:available?).with('telegram_bot_token').and_return(true)
        allow(broker).to receive(:fetch).with('telegram_bot_token', requestor: 'telegram').and_return('test-token')
        allow(Kodo::Channels::Telegram).to receive(:new).and_raise(StandardError, 'connection refused')
      end

      it 'logs the error without raising' do
        daemon.send(:reconcile_channels!)

        expect(logger).to have_received(:error).with(/Channel reconciliation failed: connection refused/)
        expect(daemon.channels).to be_empty
      end
    end

    context 'when no token is available' do
      let(:telegram_config) do
        Kodo::Config.new(
          Kodo::Config::DEFAULTS.merge(
            'channels' => { 'telegram' => { 'enabled' => true, 'bot_token_env' => 'TELEGRAM_BOT_TOKEN' } }
          )
        )
      end

      before do
        allow(Kodo).to receive(:config).and_return(telegram_config)
        allow(broker).to receive(:available?).with('telegram_bot_token').and_return(false)
        allow(telegram_config).to receive(:telegram_bot_token).and_raise(Kodo::Error, 'Missing environment variable')
      end

      it 'does not connect when no token can be resolved' do
        daemon.send(:reconcile_channels!)

        expect(daemon.channels).to be_empty
      end
    end
  end

  describe '#on_secret_stored' do
    it 'calls reconcile_channels!' do
      allow(daemon).to receive(:reconcile_channels!)
      allow(daemon).to receive(:rebuild_search_provider!)

      daemon.send(:on_secret_stored, 'telegram_bot_token')

      expect(daemon).to have_received(:reconcile_channels!)
    end
  end
end
