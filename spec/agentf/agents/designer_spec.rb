# frozen_string_literal: true

RSpec.describe Agentf::Agents::Designer do
  ComponentSpec = Struct.new(:name, :framework, :code)

  let(:memory) { instance_double(Agentf::Memory::RedisMemory, store_success: nil) }
  let(:commands) { instance_double(Agentf::Commands::Designer) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
    allow(commands).to receive(:generate_component).and_return(
      ComponentSpec.new("GeneratedComponent", "react", "export default function GeneratedComponent() {}")
    )
  end

  it "returns success=true when design is implemented"  , :aggregate_failures do
    result = agent.implement_design("Build a button")

    expect(result["component"]).to eq("GeneratedComponent")
    expect(result["generated_code"]).not_to be_empty
    expect(result["success"]).to be(true)
  end
end
