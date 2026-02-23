# frozen_string_literal: true

RSpec.describe Kodo::Heartbeat do
  let(:channel) do
    instance_double(
      Kodo::Channels::Console,
      channel_id: 'console',
      running?: true,
      poll: [],
      send_message: nil
    )
  end
  let(:router) { instance_double(Kodo::Router, route_pulse: nil) }
  let(:audit) { instance_double(Kodo::Memory::Audit, log: nil) }

  let(:heartbeat) do
    described_class.new(
      channels: [channel],
      router: router,
      audit: audit,
      interval: 1
    )
  end

  before do
    allow(Kodo).to receive(:config).and_return(
      Kodo::Config.new(
        Kodo::Config::DEFAULTS.merge('daemon' => { 'pulse_interval' => 0 })
      )
    )
  end

  describe 'pulse evaluation' do
    it 'evaluates pulse when no messages and pulse interval elapsed' do
      pulse_response = Kodo::Message.new(
        channel_id: 'console', sender: :agent,
        content: 'Daily report: all clear.',
        metadata: { chat_id: 'pulse' }
      )
      allow(router).to receive(:route_pulse).and_return(pulse_response)

      # Run a single beat (not the full loop)
      heartbeat.send(:beat!)

      expect(router).to have_received(:route_pulse).with(
        an_instance_of(Kodo::Message),
        channel: channel
      )
      expect(channel).to have_received(:send_message).with(pulse_response)
    end

    it 'does not evaluate pulse when messages were received' do
      allow(channel).to receive(:poll).and_return([
                                                    Kodo::Message.new(
                                                      channel_id: 'console', sender: :user,
                                                      content: 'Hello', metadata: { chat_id: 'test' }
                                                    )
                                                  ])
      allow(router).to receive(:route).and_return(
        Kodo::Message.new(
          channel_id: 'console', sender: :agent,
          content: 'Hi!', metadata: { chat_id: 'test' }
        )
      )

      heartbeat.send(:beat!)

      expect(router).not_to have_received(:route_pulse)
    end

    it 'does not send message when pulse returns nil' do
      allow(router).to receive(:route_pulse).and_return(nil)

      heartbeat.send(:beat!)

      expect(channel).not_to have_received(:send_message)
    end

    it 'does not send message when pulse returns empty content' do
      empty_response = Kodo::Message.new(
        channel_id: 'console', sender: :agent,
        content: '   ', metadata: { chat_id: 'pulse' }
      )
      allow(router).to receive(:route_pulse).and_return(empty_response)

      heartbeat.send(:beat!)

      expect(channel).not_to have_received(:send_message)
    end

    it 'respects pulse interval' do
      allow(Kodo).to receive(:config).and_return(
        Kodo::Config.new(
          Kodo::Config::DEFAULTS.merge('daemon' => { 'pulse_interval' => 9999 })
        )
      )
      allow(router).to receive(:route_pulse).and_return(nil)

      # First beat triggers pulse (last_pulse_at is nil)
      heartbeat.send(:beat!)
      expect(router).to have_received(:route_pulse).once

      # Second beat should NOT trigger pulse (interval not elapsed)
      heartbeat.send(:beat!)
      expect(router).to have_received(:route_pulse).once
    end

    it 'handles pulse evaluation errors gracefully' do
      allow(router).to receive(:route_pulse).and_raise(StandardError, 'LLM failure')
      logger = instance_double(Logger, debug: nil, error: nil, info: nil)
      allow(Kodo).to receive(:logger).and_return(logger)

      # Should not raise
      heartbeat.send(:beat!)

      expect(logger).to have_received(:error).with(/Pulse evaluation error/)
    end
  end

  describe 'config reload detection', :tmpdir do
    let(:config_path) { File.join(@tmpdir, 'config.yml') }
    let(:on_reload) { instance_double(Proc, call: nil) }

    before do
      File.write(config_path, YAML.dump(Kodo::Config::DEFAULTS))
      allow(Kodo::Config).to receive(:config_path).and_return(config_path)
    end

    let(:reloadable_heartbeat) do
      described_class.new(
        channels: [channel],
        router: router,
        audit: audit,
        on_reload: on_reload,
        interval: 1
      )
    end

    it 'calls on_reload when config file mtime changes' do
      reloadable_heartbeat # capture initial mtime

      # Touch the file to change mtime
      sleep 0.05
      FileUtils.touch(config_path)

      reloadable_heartbeat.send(:check_config_reload!)

      expect(on_reload).to have_received(:call).once
    end

    it 'does not call on_reload when mtime is unchanged' do
      reloadable_heartbeat.send(:check_config_reload!)

      expect(on_reload).not_to have_received(:call)
    end

    it 'calls on_reload when request_reload! is set' do
      reloadable_heartbeat.request_reload!
      reloadable_heartbeat.send(:check_config_reload!)

      expect(on_reload).to have_received(:call).once
    end

    it 'handles missing config file gracefully' do
      File.delete(config_path)

      # Should not raise
      reloadable_heartbeat.send(:check_config_reload!)

      expect(on_reload).not_to have_received(:call)
    end

    it 'handles errors in on_reload callback gracefully' do
      allow(on_reload).to receive(:call).and_raise(StandardError, 'reload boom')
      logger = instance_double(Logger, debug: nil, error: nil, info: nil)
      allow(Kodo).to receive(:logger).and_return(logger)

      reloadable_heartbeat.request_reload!

      # Should not raise
      reloadable_heartbeat.send(:check_config_reload!)

      expect(logger).to have_received(:error).with(/Config reload check failed/)
    end
  end
end
