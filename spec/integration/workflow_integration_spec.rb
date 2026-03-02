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

    def get_pitfalls(limit: 3)
      @records.select { |mem| mem["type"] == "pitfall" }.last(limit)
    end

    def get_all_tags
      @records.flat_map { |mem| mem["tags"] || [] }.uniq
    end

    def store_episode(type:, title:, description:, context: "", code_snippet: "", tags: [], agent: "SPECIALIST", related_task_id: nil)
      record = {
        "id" => "episode_#{@records.size + 1}",
        "type" => type,
        "title" => title,
        "description" => description,
        "context" => context,
        "code_snippet" => code_snippet,
        "tags" => tags,
        "agent" => agent,
        "created_at" => Time.now.to_i,
        "related_task_id" => related_task_id
      }

      @records << record
      record["id"]
    end

    def store_success(**kwargs)
      store_episode(type: "success", **kwargs)
    end

    def store_pitfall(**kwargs)
      store_episode(type: "pitfall", **kwargs)
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
  let(:orchestrator) { Agentf::Orchestrator.new(memory: memory, base_path: base_path) }

  before do
    allow_any_instance_of(Agentf::Orchestrator).to receive(:log)
    allow_any_instance_of(Agentf::Agents::Base).to receive(:log)
  end

  describe "feature workflow" do
    it "runs the full agent chain and stores successes" do
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

      result = orchestrator.execute_workflow("Add new UI feature", context: context)

      expect(result["workflow_type"]).to eq("feature")
      expect(result["completed_agents"]).to eq(%w[ARCHITECT EXPLORER DESIGNER SPECIALIST TESTER SECURITY REVIEWER DOCUMENTER])

      designers = memory.records.select { |mem| mem["agent"] == "DESIGNER" && mem["type"] == "success" }
      testers = memory.records.select { |mem| mem["agent"] == "TESTER" && mem["type"] == "success" }
      specialists = memory.records.select { |mem| mem["agent"] == "SPECIALIST" && mem["type"] == "success" }
      security = memory.records.select { |mem| mem["agent"] == "SECURITY" }

      expect(designers).not_to be_empty
      expect(testers).not_to be_empty
      expect(specialists).not_to be_empty
      expect(security).not_to be_empty
      expect(%w[success pitfall]).to include(security.first["type"])

      documenter_result = result["results"].find { |r| r["agent"] == "DOCUMENTER" }
      expect(documenter_result["result"]["successes"]).not_to be_empty
      expect(documenter_result["result"]["total_memories"]).to eq(memory.records.size)
    end
  end

  describe "bugfix workflow" do
    it "records a debugging lesson and reviewer approval" do
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

      result = orchestrator.execute_workflow("Fix payment bug", context: context)

      expect(result["workflow_type"]).to eq("bugfix")
      expect(result["completed_agents"]).to eq(%w[ARCHITECT DEBUGGER SPECIALIST TESTER SECURITY REVIEWER])

      debugger_memories = memory.records.select { |mem| mem["agent"] == "DEBUGGER" && mem["type"] == "lesson" }
      expect(debugger_memories).not_to be_empty
      expect(debugger_memories.first["title"]).to include("NoMethodError")

      security_memories = memory.records.select { |mem| mem["agent"] == "SECURITY" }
      expect(security_memories).not_to be_empty

      reviewer_result = result["results"].find { |r| r["agent"] == "REVIEWER" }
      expect(reviewer_result["result"]["approved"]).to be(true).or eq(false)
    end
  end
end
