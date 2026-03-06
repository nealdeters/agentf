# frozen_string_literal: true

RSpec.describe Agentf::Agents::Security do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::SecurityScanner) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(memory).to receive(:store_success)
    allow(memory).to receive(:store_pitfall)
    allow(commands).to receive(:best_practices).and_return(["Use secret scanning"]) 
    allow(agent).to receive(:log)
  end

  describe "#assess" do
    it "stores success when no issues found" do
      allow(commands).to receive(:scan).and_return("issues" => [], "score" => 0, "recommendations" => [])

      result = agent.assess(task: "Build", context: {})

      expect(memory).to have_received(:store_success)
      expect(result["issues"]).to be_empty
      expect(result["best_practices"]).to include("Use secret scanning")
    end

    it "stores pitfall when issues are detected" do
      issues = [{ "issue" => "Potential Secret", "detail" => "detected" }]
      allow(commands).to receive(:scan).and_return("issues" => issues, "score" => 1, "recommendations" => [])

      result = agent.assess(task: "Deploy", context: { env: "SECRET=foo" })

      expect(memory).to have_received(:store_pitfall)
      expect(result["issues"]).to eq(issues)
    end
  end
end
