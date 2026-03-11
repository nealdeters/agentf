# frozen_string_literal: true

RSpec.describe Agentf::Agents::Debugger do
  ErrorAnalysis = Struct.new(:error_type, :possible_causes, :suggested_fix, :stack_trace)

  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::Debugger) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
    allow(commands).to receive(:parse_error).and_return(
      ErrorAnalysis.new("NoMethodError", ["Nil object"], "Add guard clause", ["app.rb:10"])
    )
    # Allow memory persistence in tests that expect success
    allow(memory).to receive(:store_episode).and_return("episode_debug")
  end

  it "returns success=true with analysis payload"  , :aggregate_failures do
    result = agent.diagnose("NoMethodError: undefined method foo for nil")

    expect(result["success"]).to be(true)
    expect(result["analysis"]).to be_a(Hash)
    expect(result.dig("analysis", "error_type")).to eq("NoMethodError")
  end

  it "returns confirmation_required when memory requires confirmation"  , :aggregate_failures do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_episode).and_raise(confirmation)

    result = agent.diagnose("NoMethodError: undefined method foo for nil")

    expect(result["success"]).to be(false)
    expect(result["confirmation_required"]).to be(true)
    expect(result["confirmation_details"]).to eq(confirmation.details)
  end
end
