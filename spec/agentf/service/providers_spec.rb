# frozen_string_literal: true

RSpec.describe Agentf::Service::Providers::OpenCode do
  subject(:provider) { described_class.new }

  describe "#build_plan" do
    it "detects workflow type from task text" do
      result = provider.build_plan(
        task: "Fix login bug"
      )

      expect(result["workflow_type"]).to eq("bugfix")
      expect(result["agents_needed"]).to include("DEBUGGER")
      expect(result["provider"]).to eq("OPENCODE")
    end
  end

  describe "#execute_agent" do
    let(:architect) { instance_double(Agentf::Agents::Architect) }

    it "executes architect via shared contract" do
      allow(architect).to receive(:plan_task).with("Add auth").and_return("ok" => true)

      result = provider.execute_agent(
        agent_name: "ARCHITECT",
        task: "Add auth",
        context: {},
        agents: { "ARCHITECT" => architect },
        commands: {}
      )

      expect(result).to eq("ok" => true)
    end

    it "returns structured error for missing agent" do
      result = provider.execute_agent(
        agent_name: "UNKNOWN",
        task: "Add auth",
        context: {},
        agents: {},
        commands: {}
      )

      expect(result["error"]).to eq("Agent UNKNOWN not found")
    end
  end
end

RSpec.describe Agentf::Service::Providers::Copilot do
  subject(:provider) { described_class.new }

  describe "#build_plan" do
    it "uses copilot workflow templates" do
      result = provider.build_plan(task: "Add feature")

      expect(result["provider"]).to eq("COPILOT")
      expect(result["agents_needed"]).to include("SPECIALIST", "TESTER", "REVIEWER")
      expect(result["agents_needed"]).not_to include("EXPLORER")
    end
  end
end
