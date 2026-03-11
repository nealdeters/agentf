# frozen_string_literal: true

RSpec.describe Agentf::Agents::Explorer do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::Explorer) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
  end

  it "returns files and context when exploring" do
    allow(commands).to receive(:glob).with("src/**/*.rb", file_types: nil).and_return(["lib/a.rb", "lib/b.rb"])
    allow(memory).to receive(:store_episode)

    result = agent.explore("src/**/*.rb")

    expect(result["files"]).to be_a(Array).and include("lib/a.rb")
    expect(result["context_gathered"]).to be true
  end

  it "returns confirmation_required when memory requires confirmation" do
    allow(commands).to receive(:glob).and_return(["lib/a.rb"])
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_episode).and_raise(confirmation)

    result = agent.explore("*.rb")

    expect(result["confirmation_required"]).to be(true)
    expect(result["confirmation_details"]).to eq(confirmation.details)
    expect(result["files"]).to include("lib/a.rb")
  end
end
