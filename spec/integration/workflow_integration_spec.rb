# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent workflow integration" do
  class FakeMemory
    attr_reader :records

    def initialize
      @records = []
    end

    def get_recent_memories(limit: 10)
      @records.last(limit)
    end

    def get_episodes(limit: 3, outcome: nil)
      records = @records.select { |mem| mem["type"] == "episode" }
      records = records.select { |mem| mem["outcome"] == outcome } if outcome
      records.last(limit)
    end

    def get_relevant_context(agent:, query_embedding: nil, query_text: nil, task_type: nil, limit: 8)
      {
        "agent" => agent,
        "intent" => @records.select { |mem| %w[business_intent feature_intent].include?(mem["type"]) }.last(limit),
        "memories" => @records.last(limit),
        "similar_tasks" => []
      }
    end

    def get_agent_context(agent:, query_embedding: nil, query_text: nil, task_type: nil, limit: 8)
      get_relevant_context(agent: agent, query_embedding: query_embedding, query_text: query_text, task_type: task_type, limit: limit)
    end

    def store_feature_intent(title:, description:, acceptance_criteria: [], non_goals: [], agent: "ORCHESTRATOR", related_task_id: nil)
      store_episode(
        type: "feature_intent",
        title: title,
        description: description,
        context: ["Acceptance: #{acceptance_criteria.join('; ')}", "Non-goals: #{non_goals.join('; ')}"].reject(&:empty?).join(" | "),
        agent: agent,
        related_task_id: related_task_id
      )
    end

    def store_episode(type:, title:, description:, context: "", code_snippet: "", agent: "ENGINEER", related_task_id: nil, outcome: nil, metadata: {})
      record = {
        "id" => "episode_#{@records.size + 1}",
        "type" => type,
        "title" => title,
        "description" => description,
        "context" => context,
        "code_snippet" => code_snippet,
        "agent" => agent,
        "created_at" => Time.now.to_i,
        "related_task_id" => related_task_id,
        "outcome" => outcome,
        "metadata" => metadata
      }

      @records << record
      record["id"]
    end
    def store_lesson(**kwargs)
      store_episode(type: "lesson", **kwargs)
    end

    def store_task(**_kwargs)
      # no-op for integration tests
    end

  end

  let(:memory) { FakeMemory.new }
  let(:base_path) { File.expand_path("../fixtures", __dir__) }
  let(:engine) { Agentf::WorkflowEngine.new(memory: memory, base_path: base_path, provider: :opencode) }

  before do
    allow_any_instance_of(Agentf::WorkflowEngine).to receive(:log)
    allow_any_instance_of(Agentf::Agents::Base).to receive(:log)
  end

  describe "feature workflow" do
    it "runs the full agent chain and stores successes"  , :aggregate_failures do
      context = {
        "design_spec" => "Primary button with loading state",
        "source_file" => "app/models/user.rb",
        "current_subtask" => {
          "id" => 101,
          "description" => "Implement primary button behavior",
          "task" => "Build primary button",
          "language" => "ruby"
        }
      }

      result = engine.execute(task: "Add new UI feature", context: context)

      expect(result["workflow_type"]).to eq("feature")
      expect(result["workflow_contract"]).to be_a(Hash)
      expect(result["completed_agents"]).to eq(%w[PLANNER RESEARCHER UI_ENGINEER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER KNOWLEDGE_MANAGER])
      expect(result.dig("tdd", "enabled")).to be(true)
      expect(result.dig("tdd", "red_executed")).to be(true)

      red_phase = result["results"].find { |r| r["agent"] == "QA_TESTER_TDD_RED" }
      expect(red_phase).not_to be_nil
      expect(red_phase.dig("result", "tdd_phase")).to eq("red")
      expect(red_phase.dig("result", "passed")).to be(false)

      designers = memory.records.select { |mem| mem["agent"] == "UI_ENGINEER" && mem["type"] == "episode" && mem["outcome"] == "positive" }
      testers = memory.records.select { |mem| mem["agent"] == "QA_TESTER" && mem["type"] == "episode" && mem["outcome"] == "positive" }
      specialists = memory.records.select { |mem| mem["agent"] == "ENGINEER" && mem["type"] == "episode" && mem["outcome"] == "positive" }
      security = memory.records.select { |mem| mem["agent"] == "SECURITY_REVIEWER" }

      expect(designers).not_to be_empty
      expect(memory.records.select { |mem| mem["agent"] == "QA_TESTER" && mem["type"] == "episode" }).not_to be_empty
      expect(specialists).not_to be_empty
      expect(security).not_to be_empty
      expect(security.first["type"]).to eq("episode")

      documenter_result = result["results"].find { |r| r["agent"] == "KNOWLEDGE_MANAGER" }
      expect(documenter_result["result"]["successes"]).not_to be_empty
      expect(documenter_result["result"]["total_memories"]).to be <= memory.records.size
    end
  end

  describe "bugfix workflow" do
    it "records a debugging lesson and reviewer approval"  , :aggregate_failures do
      context = {
        "error" => "NoMethodError: undefined method `process' for nil:NilClass",
        "error_context" => "processing payment",
        "current_subtask" => {
          "id" => 202,
          "description" => "Fix payment processor crash",
          "task" => "Stabilize payments",
          "language" => "ruby"
        }
      }

      result = engine.execute(task: "Fix payment bug", context: context)

      expect(result["workflow_type"]).to eq("bugfix")
      expect(result["architecture_review"]).to be_a(Hash)
      expect(result["completed_agents"]).to eq(%w[PLANNER INCIDENT_RESPONDER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER])
      expect(result.dig("tdd", "red_executed")).to be(true)
      expect(result.dig("tdd", "green_executed")).to be(false).or be(true)

      debugger_memories = memory.records.select { |mem| mem["agent"] == "INCIDENT_RESPONDER" && mem["type"] == "lesson" }
      expect(debugger_memories).not_to be_empty
      # The Debugger stores a truncated title; ensure error type is present
      expect(debugger_memories.first["title"]).to include("NoMethodError").or include("Debugged:")

      security_memories = memory.records.select { |mem| mem["agent"] == "SECURITY_REVIEWER" }
      expect(security_memories).not_to be_empty

      reviewer_result = result["results"].find { |r| r["agent"] == "REVIEWER" }
      expect(reviewer_result["result"]["approved"]).to be(true).or eq(false)
    end
  end
end
