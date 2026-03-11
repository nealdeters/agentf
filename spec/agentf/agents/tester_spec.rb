# frozen_string_literal: true

require 'ostruct'

RSpec.describe Agentf::Agents::Tester do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::Tester) }
  let(:template) { OpenStruct.new(test_file: "spec/foo_spec.rb", framework: "rspec", test_code: "describe 'x' do end") }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
    allow(commands).to receive(:generate_unit_tests).and_return(template)
  end

  it "generates tests and stores success"  , :aggregate_failures do
    # Simulate successful persistence by returning an episode id
    allow(memory).to receive(:store_success).and_return("episode_ok")
    res = agent.generate_tests("app/models/user.rb")

    expect(res["test_file"]).to eq("spec/foo_spec.rb")
    expect(res["generated_code"]).to eq("describe 'x' do end")
  end

  it "returns confirmation_required when memory requires confirmation"  , :aggregate_failures do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_success).and_raise(confirmation)

    res = agent.generate_tests("app/models/user.rb")
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end
end
