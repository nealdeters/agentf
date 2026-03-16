# frozen_string_literal: true

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  # Skip Redis-dependent tests if Redis Stack is not available
  # These tests verify the interface exists and works at a basic level
  
  describe "#initialize" do
    it "creates instance with project name" do
      memory = described_class.new(project: project)
      expect(memory.project).to eq(project)
    end

    it "uses default project from config"  , :aggregate_failures do
      expect(Agentf.config).to receive(:project_name).and_return("default")
      memory = described_class.new
      expect(memory.project).to eq("default")
    end
  end

  describe "#store_task" do
    it "responds to store_task method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_task)
    end

    it "serializes embedding as JSON, not Ruby Array#to_s"  , :aggregate_failures do
      memory = described_class.new(project: project)
      task_id = memory.store_task(content: "Test", embedding: [1.0, 2.0, 3.0])

      # Retrieve the stored task via find_similar_tasks
      # The embedding round-trips through JSON.generate -> hset -> hget -> JSON.parse
      results = memory.find_similar_tasks(query_embedding: [1.0, 2.0, 3.0], limit: 1)
      expect(results.length).to eq(1)
      expect(results.first["id"]).to eq(task_id)
      expect(results.first["score"]).to be_within(0.001).of(1.0)
    end
  end

  describe "#store_episode" do
    it "responds to store_episode method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_episode)
    end
  end

  describe "#store_success" do
    it "responds to store_success method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_success)
    end
  end

  describe "#store_pitfall" do
    it "responds to store_pitfall method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_pitfall)
    end
  end

  describe "#store_lesson" do
    it "responds to store_lesson method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_lesson)
    end
  end

  describe "intent APIs" do
    it "responds to business intent storage" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_business_intent)
    end

    it "responds to feature intent storage" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:store_feature_intent)
    end

    it "responds to intent retrieval" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:get_intents)
    end

    it "stores and retrieves business intent" do
      memory = described_class.new(project: project)
      memory.store_business_intent(
        title: "Reliability",
        description: "Prioritize uptime",
        constraints: ["No downtime"],
        tags: ["ops"]
      )

      intents = memory.get_intents(kind: "business", limit: 10)
      expect(intents.map { |intent| intent["type"] }).to include("business_intent")
    end
  end

  describe "learning model APIs" do
    it "stores and retrieves incidents" do
      memory = described_class.new(project: project)
      memory.store_incident(
        title: "Payment timeout",
        description: "Gateway timed out",
        root_cause: "Downstream latency",
        resolution: "Increase timeout",
        tags: ["payments"],
        confirm: true
      )

      incidents = memory.get_memories_by_type(type: "incident", limit: 10)
      expect(incidents.map { |incident| incident["type"] }).to include("incident")
    end

    it "stores playbook memories" do
      memory = described_class.new(project: project)
      memory.store_playbook(
        title: "Release rollout",
        description: "Safe deployment steps",
        steps: ["deploy canary", "monitor", "promote"],
        tags: ["release"],
        confirm: true
      )

      playbooks = memory.get_memories_by_type(type: "playbook", limit: 10)
      expect(playbooks.map { |record| record["type"] }).to include("playbook")
    end
  end

  describe "agent context ranking" do
    it "prioritizes architect intent and playbook records"  , :aggregate_failures do
      memory = described_class.new(project: project)
      memory.store_feature_intent(title: "Feature intent", description: "Build reporting", confirm: true)
      memory.store_playbook(title: "Architecture playbook", description: "Use modular boundaries", confirm: true)
      memory.store_pitfall(title: "Old pitfall", description: "Legacy mistake", confirm: true)

      context = memory.get_agent_context(agent: "PLANNER", task_type: "feature", limit: 2)

      expect(context["memories"].length).to eq(2)
      expect(context["profile"]).to have_key("preferred_types")
      expect(context["memories"].first).to have_key("rank_score")
    end
  end

  describe "#find_similar_tasks" do
    it "returns empty array (not implemented)" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [0.1, 0.2])
      expect(result).to eq([])
    end

    it "accepts limit parameter" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], limit: 10)
      expect(result).to eq([])
    end

    it "filters by language" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], language: "ruby")
      expect(result).to eq([])
    end

    it "filters by task_type" do
      memory = described_class.new(project: project)
      result = memory.find_similar_tasks(query_embedding: [], task_type: "feature")
      expect(result).to eq([])
    end

    it "returns similar tasks by embedding score"  , :aggregate_failures do
      memory = described_class.new(project: project)
      memory.store_task(content: "Build auth", embedding: [1.0, 0.0], task_type: "feature", language: "ruby")
      memory.store_task(content: "Fix bug", embedding: [0.0, 1.0], task_type: "bugfix", language: "ruby")

      result = memory.find_similar_tasks(query_embedding: [0.9, 0.1], limit: 1)

      expect(result.length).to eq(1)
      expect(result.first["content"]).to eq("Build auth")
    end
  end

  describe "#get_relevant_context" do
    it "returns structured context with intents and memories"  , :aggregate_failures do
      memory = described_class.new(project: project)
      context = memory.get_relevant_context(agent: "PLANNER", query_embedding: [0.2, 0.1], limit: 3)

      expect(context).to have_key("intent")
      expect(context).to have_key("memories")
      expect(context).to have_key("similar_tasks")
    end
  end

  describe "project scoping" do
    it "keeps recent memory queries isolated to the current project" do
      current_project_memory = described_class.new(project: project)
      other_project_memory = described_class.new(project: "other-project")

      current_project_memory.store_lesson(title: "Current lesson", description: "current", tags: [], confirm: true)
      other_project_memory.store_lesson(title: "Other lesson", description: "other", tags: [], confirm: true)

      recent = current_project_memory.get_recent_memories(limit: 10)

      expect(recent.map { |item| item["title"] }).to include("Current lesson")
      expect(recent.map { |item| item["title"] }).not_to include("Other lesson")
    end
  end

  # Redis Stack required - skip in tests without Redis Stack
  describe "#get_pitfalls", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#get_recent_memories", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#get_all_tags", skip: "Requires Redis Stack (FT.SEARCH)" do
  end

  describe "#close" do
    it "responds to close method" do
      memory = described_class.new(project: project)
      expect(memory).to respond_to(:close)
    end
  end

  describe "deletion APIs" do
    it "deletes memory by id in current project"  , :aggregate_failures do
      memory = described_class.new(project: project)
      id = memory.store_lesson(title: "L1", description: "d", tags: [])

      result = memory.delete_memory_by_id(id: id, scope: "project")
      expect(result["deleted_count"]).to be >= 1

      recent = memory.get_recent_memories(limit: 20)
      expect(recent.map { |m| m["id"] }).not_to include(id)
    end

    it "dry-runs delete all without removing records"  , :aggregate_failures do
      memory = described_class.new(project: project)
      memory.store_lesson(title: "L1", description: "d", tags: [])

      result = memory.delete_all(scope: "project", dry_run: true)
      expect(result["dry_run"]).to be(true)
      expect(result["deleted_count"]).to eq(0)
      expect(result["candidate_count"]).to be >= 1

      expect(memory.get_recent_memories(limit: 20)).not_to be_empty
    end

    it "deletes last N memories"  , :aggregate_failures do
      memory = described_class.new(project: project)
      3.times { |i| memory.store_lesson(title: "L#{i}", description: "d", tags: []) }

      result = memory.delete_recent(limit: 2, scope: "project")
      expect(result["deleted_count"]).to be >= 2
      expect(result["deleted_ids"].length).to eq(2)
    end

    it "filters delete all by type"  , :aggregate_failures do
      memory = described_class.new(project: project)
      memory.store_lesson(title: "L", description: "d", tags: [])
      memory.store_pitfall(title: "P", description: "d", tags: [])

      result = memory.delete_all(scope: "project", type: "lesson")
      expect(result["deleted_count"]).to be >= 1

      remaining = memory.get_recent_memories(limit: 20)
      expect(remaining.map { |m| m["type"] }).to include("pitfall")
    end
  end

  describe ".memory" do
    it "creates a new RedisMemory instance"  , :aggregate_failures do
      mem = Agentf::Memory.memory(project: "custom-project")
      expect(mem).to be_a(Agentf::Memory::RedisMemory)
      expect(mem.project).to eq("custom-project")
    end
  end
end
