# frozen_string_literal: true

RSpec.describe Agentf::Agents::Security do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::SecurityScanner) }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(memory).to receive(:store_episode)
    allow(commands).to receive(:best_practices).and_return(["Use secret scanning"]) 
    allow(agent).to receive(:log)
  end

  describe "#assess" do
    it "stores success when no issues found"  , :aggregate_failures do
      allow(commands).to receive(:scan).and_return("issues" => [], "score" => 0, "recommendations" => [])

      result = agent.assess(task: "Build", context: {})

      expect(memory).to have_received(:store_episode).with(hash_including(type: "episode", outcome: "positive"))
      expect(result["issues"]).to be_empty
      expect(result["best_practices"]).to include("Use secret scanning")
    end

    it "stores pitfall when issues are detected"  , :aggregate_failures do
      issues = [{ "issue" => "Potential Secret", "detail" => "detected" }]
      allow(commands).to receive(:scan).and_return("issues" => issues, "score" => 1, "recommendations" => [])

      result = agent.assess(task: "Deploy", context: { env: "SECRET=foo" })

      expect(memory).to have_received(:store_episode).with(hash_including(type: "episode", outcome: "negative"))
      expect(result["issues"]).to eq(issues)
    end
  end
end
