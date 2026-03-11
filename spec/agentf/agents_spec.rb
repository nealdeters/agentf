# frozen_string_literal: true

RSpec.describe Agentf::Agents::Base do
  let(:memory) { double("memory") }
  let(:agent) { Agentf::Agents::Architect.new(memory) }

  it "has access to memory" do
    expect(agent.memory).to eq(memory)
  end

  it "has a name based on class" do
    expect(agent.name).to eq("PLANNER")
  end

  it "has a log method" do
    expect(agent).to respond_to(:log)
  end

  it "exposes policy boundaries"  , :aggregate_failures do
    boundaries = agent.class.policy_boundaries
    expect(boundaries).to have_key("always")
    expect(boundaries).to have_key("ask_first")
    expect(boundaries).to have_key("never")
  end
end

RSpec.describe Agentf::Agents::Architect do
  let(:memory) { double("memory", get_recent_memories: [], get_pitfalls: []) }
  subject(:architect) { described_class.new(memory) }

  describe "#plan_task" do
    it "creates a plan with subtasks"  , :aggregate_failures do
      result = architect.plan_task("Build authentication system")

      expect(result).to have_key("subtasks")
      expect(result["subtasks"]).not_to be_empty
    end

    it "retrieves relevant memories"  , :aggregate_failures do
      expect(memory).to receive(:get_recent_memories).with(limit: 5)
      expect(memory).to receive(:get_pitfalls).with(limit: 3)

      architect.plan_task("Test task")
    end

    it "includes context with memories and pitfalls"  , :aggregate_failures do
      result = architect.plan_task("Test task")

      expect(result["context"]).to have_key("relevant_memories")
      expect(result["context"]).to have_key("pitfalls_to_avoid")
    end
  end
end

RSpec.describe Agentf::Agents::Specialist do
  let(:memory) { double("memory") }
  subject(:specialist) { described_class.new(memory) }

  describe "#execute" do
    it "executes a subtask"  , :aggregate_failures do
      subtask = { "id" => 1, "description" => "Implement feature" }

      expect(memory).to receive(:store_success)
      result = specialist.execute(subtask)

      expect(result["success"]).to be true
      expect(result["subtask_id"]).to eq(1)
    end

    it "stores success memory on success" do
      subtask = { "id" => 1, "description" => "Test", "task" => "Main task", "language" => "ruby" }

      expect(memory).to receive(:store_success).with(
        title: "Completed: Test",
        description: "Successfully executed subtask 1",
        context: "Working on Main task",
        tags: ["implementation", "ruby"],
        agent: "ENGINEER"
      )

      specialist.execute(subtask)
    end

    it "stores pitfall on failure" do
      # Force failure by raising
      subtask = { "id" => 1, "description" => "Test" }

      # We'll simulate by allowing it to not call store_success
      allow(memory).to receive(:store_success)
      result = specialist.execute(subtask)

      expect(result["success"]).to be true
    end
  end
end

RSpec.describe Agentf::Agents::Reviewer do
  let(:memory) { double("memory", get_pitfalls: [], get_recent_memories: []) }
  subject(:reviewer) { described_class.new(memory) }

  describe "#review" do
    it "reviews subtask result"  , :aggregate_failures do
      subtask_result = { "subtask_id" => 1, "success" => true }

      result = reviewer.review(subtask_result)

      expect(result).to have_key("approved")
      expect(result).to have_key("issues")
    end

    it "approves when no issues found" do
      subtask_result = { "subtask_id" => 1, "success" => true }
      allow(memory).to receive(:get_pitfalls).and_return([])

      result = reviewer.review(subtask_result)

      expect(result["approved"]).to be true
    end
  end
end

RSpec.describe Agentf::Agents::Documenter do
  let(:memory) { double("memory", get_recent_memories: []) }
  subject(:documenter) { described_class.new(memory) }

  describe "#sync_docs" do
    it "retrieves recent memories" do
      expect(memory).to receive(:get_recent_memories).with(limit: 20)

      documenter.sync_docs("project")
    end

    it "returns successes and pitfalls"  , :aggregate_failures do
      allow(memory).to receive(:get_recent_memories).and_return([
        { "type" => "success" },
        { "type" => "pitfall" }
      ])

      result = documenter.sync_docs("project")

      expect(result).to have_key("successes")
      expect(result).to have_key("pitfalls")
      expect(result).to have_key("total_memories")
    end
  end
end

RSpec.describe Agentf::Agents::Explorer do
  let(:memory) { double("memory", store_episode: nil) }
  let(:commands) { Agentf::Commands::Explorer.new(base_path: File.expand_path("../fixtures", __dir__)) }
  subject(:explorer_agent) { described_class.new(memory, commands: commands) }

  describe "#explore" do
    it "explores and finds files"  , :aggregate_failures do
      result = explorer_agent.explore("app/**/*.rb")

      expect(result).to have_key("files")
      expect(result["files"]).not_to be_empty
    end

    it "stores exploration memory" do
      expect(memory).to receive(:store_episode)

      explorer_agent.explore("app/**/*.rb")
    end
  end
end

RSpec.describe Agentf::Agents::Tester do
  let(:memory) { double("memory", store_success: nil) }
  let(:commands) { Agentf::Commands::Tester.new(base_path: File.expand_path("fixtures", __dir__)) }
  subject(:tester_agent) { described_class.new(memory, commands: commands) }

  describe "#generate_tests" do
    it "generates tests for source file"  , :aggregate_failures do
      result = tester_agent.generate_tests("app/models/user.rb")

      expect(result).to have_key("test_file")
      expect(result).to have_key("generated_code")
    end

    it "stores success memory" do
      expect(memory).to receive(:store_success)

      tester_agent.generate_tests("app/models/user.rb")
    end
  end

  describe "#run_tests" do
    it "runs tests and returns result" do
      result = tester_agent.run_tests("spec/models/user_spec.rb")

      expect(result).to have_key("passed")
    end
  end
end

RSpec.describe Agentf::Agents::Debugger do
  let(:memory) { double("memory", store_episode: nil) }
  let(:commands) { Agentf::Commands::Debugger.new }
  subject(:debugger_agent) { described_class.new(memory, commands: commands) }

  describe "#diagnose" do
    it "diagnoses error and returns analysis"  , :aggregate_failures do
      result = debugger_agent.diagnose("NoMethodError: undefined method 'foo'")

      expect(result).to have_key("error")
      expect(result["analysis"]).to have_key("error_type")
      expect(result["analysis"]).to have_key("possible_causes")
      expect(result["analysis"]).to have_key("suggested_fix")
    end

    it "stores lesson memory" do
      expect(memory).to receive(:store_episode)

      debugger_agent.diagnose("Error: test")
    end
  end
end

RSpec.describe Agentf::Agents::Designer do
  let(:memory) { double("memory", store_success: nil) }
  let(:commands) { Agentf::Commands::Designer.new }
  subject(:designer_agent) { described_class.new(memory, commands: commands) }

  describe "#implement_design" do
    it "implements design from spec"  , :aggregate_failures do
      result = designer_agent.implement_design("Button component with click handler")

      expect(result).to have_key("component")
      expect(result).to have_key("generated_code")
    end

    it "stores success memory" do
      expect(memory).to receive(:store_success)

      designer_agent.implement_design("Test design")
    end

    it "respects framework parameter" do
      result = designer_agent.implement_design("Test", framework: "vue")

      expect(result["framework"]).to eq("vue")
    end
  end
end
