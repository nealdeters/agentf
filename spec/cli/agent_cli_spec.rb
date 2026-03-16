# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "agentf/cli/agent"

RSpec.describe Agentf::CLI::Agent do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:fake_agent_class) do
    Class.new(Agentf::Agents::Base) do
      def self.typed_name
        Agentf::AgentRoles::ENGINEER
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        {
          "task" => task,
          "confirmed_write" => context["confirmed_write"],
          "auto_confirm_memories" => ENV["AGENTF_AUTO_CONFIRM_MEMORIES"],
          "suppress_logs" => ENV["AGENTF_SUPPRESS_AGENT_LOGS"]
        }
      end
    end
  end

  subject(:cli) { described_class.new }

  before do
    stub_const("Agentf::Agents::EvalFakeAgent", fake_agent_class)
    allow(Agentf::Memory::RedisMemory).to receive(:new).and_return(memory)
    allow(Agentf::Agents).to receive(:constants).and_return([:EvalFakeAgent])
    allow(Agentf::Agents).to receive(:const_get).with(:EvalFakeAgent).and_return(fake_agent_class)
  end

  it "passes through confirmed-write state for non-interactive retries" do
    output = capture_stdout do
      cli.run(["engineer", '{"description":"retry persistence"}', "--json", "--confirmed-write=token-123"])
    end

    payload = JSON.parse(output)
    expect(payload["confirmed_write"]).to eq("token-123")
    expect(payload["auto_confirm_memories"]).to eq("true")
    expect(payload["suppress_logs"]).to eq("true")
  end

  def capture_stdout
    original = $stdout
    io = StringIO.new
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end
end
