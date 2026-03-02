# frozen_string_literal: true

RSpec.describe Agentf::Orchestrator do
  let(:memory) { double("memory", get_recent_memories: [], get_pitfalls: [], store_episode: nil, store_success: nil, store_pitfall: nil) }
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  subject(:orchestrator) { described_class.new(memory: memory, base_path: base_path) }

  describe "#analyze_task" do
    it "detects bugfix workflow" do
      result = orchestrator.analyze_task("Fix the login bug")

      expect(result["workflow_type"]).to eq("bugfix")
    end

    it "detects feature workflow" do
      result = orchestrator.analyze_task("Add user authentication")

      expect(result["workflow_type"]).to eq("feature")
    end

    it "detects exploration workflow" do
      result = orchestrator.analyze_task("Find where the user model is")

      expect(result["workflow_type"]).to eq("exploration")
    end

    it "detects quick_fix workflow" do
      result = orchestrator.analyze_task("Quick small fix")

      expect(result["workflow_type"]).to eq("quick_fix")
    end

    it "detects refactor workflow" do
      result = orchestrator.analyze_task("Refactor the user service")

      expect(result["workflow_type"]).to eq("refactor")
    end

    it "returns correct agents for bugfix" do
      result = orchestrator.analyze_task("Fix bug")

      expect(result["agents_needed"]).to include("ARCHITECT", "DEBUGGER", "SPECIALIST", "TESTER", "REVIEWER")
    end

    it "returns correct agents for feature" do
      result = orchestrator.analyze_task("Add feature")

      expect(result["agents_needed"]).to include("ARCHITECT", "DESIGNER", "SPECIALIST", "TESTER", "REVIEWER")
    end
  end

  describe "#execute_workflow" do
    it "executes bugfix workflow" do
      result = orchestrator.execute_workflow("Fix login bug")

      expect(result).to have_key("task")
      expect(result).to have_key("workflow_type")
      expect(result).to have_key("results")
      expect(result).to have_key("completed_agents")
    end

    it "respects context" do
      context = { "design_spec" => "Button component" }
      result = orchestrator.execute_workflow("Create button", context: context)

      expect(result["context"]).to eq(context)
    end

    it "runs all agents in workflow" do
      result = orchestrator.execute_workflow("Quick fix")

      expect(result["completed_agents"]).not_to be_empty
      expect(result["results"]).not_to be_empty
    end
  end

  describe "workflow state" do
    it "tracks completed agents" do
      result = orchestrator.execute_workflow("Add feature")

      expect(result["completed_agents"]).to be_an(Array)
    end

    it "collects agent results" do
      result = orchestrator.execute_workflow("Add feature")

      expect(result["results"]).to be_an(Array)
      result["results"].each do |r|
        expect(r).to have_key("agent")
        expect(r).to have_key("result")
      end
    end
  end
end
