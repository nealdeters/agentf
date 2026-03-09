# frozen_string_literal: true

RSpec.describe Agentf::Agents::Debugger do
  ErrorAnalysis = Struct.new(:error_type, :possible_causes, :suggested_fix, :stack_trace)

  let(:memory) { instance_double(Agentf::Memory::RedisMemory, store_episode: nil) }
  let(:commands) { instance_double(Agentf::Commands::Debugger) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
    allow(commands).to receive(:parse_error).and_return(
      ErrorAnalysis.new("NoMethodError", ["Nil object"], "Add guard clause", ["app.rb:10"])
    )
  end

  it "returns success=true with analysis payload" do
    result = agent.diagnose("NoMethodError: undefined method foo for nil")

    expect(result["success"]).to be(true)
    expect(result["analysis"]).to be_a(Hash)
    expect(result.dig("analysis", "error_type")).to eq("NoMethodError")
  end
end
